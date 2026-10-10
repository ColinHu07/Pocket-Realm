import Foundation

enum GeminiModel: String, CaseIterable, Identifiable {
    case flash38 = "gemini-3.8-flash"
    case flash36 = "gemini-3.6-flash"
    var id: String { rawValue }
    var name: String { self == .flash38 ? "Gemini 3.8 Flash" : "Gemini 3.6 Flash" }
}

/// Personal prototype connection. Credentials are sent only to Google's HTTPS endpoint.
struct GeminiClient {
    var model: GeminiModel = .flash38
    static let connectionTimeout: TimeInterval = 60
    static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        // Leave room for the connection test's explicit deadline to cancel its request.
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }()
    var transport: (URLRequest) async throws -> (Data, URLResponse) = { try await session.data(for: $0) }

    func plan(key: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
              context: RoomScanContext) async throws -> EncounterPlan {
        let payload = try Self.payload(candidates: candidates, photos: photos, friend: friend, context: context, model: model)
        let data = try await send(key: key, payload: payload)
        return try Self.parse(data, candidates: candidates, friend: friend, context: context)
    }

    func test(key: String, timeout: TimeInterval = Self.connectionTimeout) async throws {
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await send(key: key, payload: [
                    "model": model.rawValue, "input": "Reply with exactly READY.", "store": false,
                    // Both models support low thinking. Avoid a tiny output cap: thinking
                    // consumes that same budget and could prevent any visible answer.
                    "generation_config": ["thinking_level": "low"]
                ], timeout: timeout + 5)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw PlanError.server("No response from \(model.name) within \(Int(ceil(timeout))) seconds. The app stopped waiting. This doesn't confirm a bad key or exhausted quota. Google may be slow or the connection may have stalled; try again once, or try another network.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        // Any completed text response proves this key can generate with the selected model.
        // Punctuation or extra whitespace in READY should not report a false connection failure.
        _ = try Self.outputText(data)
    }

    func send(key: String, payload: [String: Any], timeout: TimeInterval = 55) async throws -> Data {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanKey.contains(where: { $0.isWhitespace }) else {
            throw PlanError.server("Enter your Gemini API key in Connection settings.")
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError {
            try Task.checkCancellation()
            let message: String
            switch error.code {
            case .timedOut:
                message = "The request to \(model.name) timed out before an answer arrived. This doesn't confirm a bad key or exhausted quota. Try again once, or try another network."
            case .notConnectedToInternet:
                message = "Your iPhone reports no internet connection. Connect to Wi-Fi or cellular data, then try again."
            case .networkConnectionLost:
                message = "The connection to Google dropped before Gemini answered. Reconnect or try another network."
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                message = "Your iPhone couldn't connect to Google's API server. Try another Wi-Fi network or cellular data."
            default:
                message = "Couldn't reach Google's API (network error \(error.code.rawValue)). Try another network, then try again."
            }
            throw PlanError.server(message)
        }
        catch { throw PlanError.server("Couldn't complete the Gemini request. Try again once, or try another network.") }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PlanError.invalidPlan }
        guard http.statusCode == 200 else {
            // Never display provider bodies: they can contain request data or credential details.
            let message: String
            switch http.statusCode {
            case 400, 401, 403: message = "Gemini rejected the request or key. Check your API key and Gemini API access in Google AI Studio."
            case 404: message = "\(model.name) isn't available for this key. Choose another model in Connection settings or check model access in Google AI Studio."
            case 429: message = "Google returned a rate limit or quota error for \(model.name). Check this model's minute and daily limits for your project in AI Studio. This response alone doesn't mean today's quota is used up. Saved rooms still work offline."
            case 504: message = "Google returned HTTP 504: \(model.name) took too long to respond. Your key wasn't confirmed or rejected by this response. Try again in a moment."
            case 500...599: message = "Gemini is temporarily unavailable. Your scan is still here; try again in a moment."
            default: message = "Gemini returned HTTP \(http.statusCode). Try again or check your API access in Google AI Studio."
            }
            throw PlanError.server(message)
        }
        return data
    }

    static func outputText(_ data: Data) throws -> String {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["status"] as? String == "completed", let steps = response["steps"] as? [[String: Any]] else {
            throw PlanError.server("Gemini couldn't finish its response. Please try again.")
        }
        let text = steps.filter { $0["type"] as? String == "model_output" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw PlanError.invalidPlan }
        return text
    }

    static func parse(_ data: Data, candidates: [RoomCandidate], friend: RealmFriend,
                      context: RoomScanContext) throws -> EncounterPlan {
        let text = try outputText(data)
        return try RoomPlanRequest.parse(text, candidates: candidates, friend: friend, context: context)
    }

    static func payload(candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
                        context: RoomScanContext, model: GeminiModel = .flash38) throws -> [String: Any] {
        let plan = try RoomPlanRequest.make(candidates: candidates, photos: photos, friend: friend, context: context)
        var input: [[String: Any]] = [["type": "text", "text": plan.prompt]]
        for (index, photo) in photos.enumerated() {
            let label: [String: Any] = ["yawRadians": photo.yaw, "cameraPosition": photo.position, "cameraForward": photo.forward]
            let labelJSON = String(decoding: try JSONSerialization.data(withJSONObject: label), as: UTF8.self)
            input.append(["type": "text", "text": "Snapshot \(index + 1): \(labelJSON)"])
            input.append(["type": "image", "data": photo.jpeg, "mime_type": "image/jpeg"])
        }
        return ["model": model.rawValue, "input": input, "store": false,
                "response_format": ["type": "text", "mime_type": "application/json", "schema": plan.schema],
                "generation_config": ["max_output_tokens": 4096]]
    }
}
