import Foundation

enum MuseModel: String, CaseIterable, Identifiable {
    case spark13 = "muse-spark-1.3"
    case spark12 = "muse-spark-1.2"
    case spark11 = "muse-spark-1.1"
    var id: String { rawValue }
    var name: String { "Muse Spark " + rawValue.replacingOccurrences(of: "muse-spark-", with: "") }
}

/// Meta Model API integration. Independent of Gemini's transport and response format.
/// Reference: https://dev.meta.ai/docs/protocols/chat-completions
struct MuseClient {
    var model: MuseModel = .spark13
    static let connectionTimeout: TimeInterval = 60
    static let endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    var transport: (URLRequest) async throws -> (Data, URLResponse) = { try await session.data(for: $0) }

    func plan(key: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
              context: RoomScanContext) async throws -> EncounterPlan {
        let body = try Self.payload(candidates: candidates, photos: photos, friend: friend, context: context, model: model)
        let data = try await send(key: key, payload: body)
        return try RoomPlanRequest.parse(Self.outputText(data), candidates: candidates, friend: friend, context: context)
    }

    func test(key: String, timeout: TimeInterval = Self.connectionTimeout) async throws {
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await send(key: key, payload: ["model": model.rawValue,
                    "messages": [["role": "user", "content": "Reply with exactly READY."]],
                    "reasoning_effort": "low", "max_completion_tokens": 1024], timeout: timeout + 5)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw PlanError.server("No response from \(model.name) within \(Int(ceil(timeout))) seconds. Try again once or check your connection. This doesn't confirm a bad key or exhausted quota.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        _ = try Self.outputText(data)
    }

    static func payload(candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
                        context: RoomScanContext, model: MuseModel = .spark13) throws -> [String: Any] {
        let plan = try RoomPlanRequest.make(candidates: candidates, photos: photos, friend: friend, context: context)
        var content: [[String: Any]] = [["type": "text", "text": plan.prompt]]
        for (index, photo) in photos.enumerated() {
            let label: [String: Any] = ["yawRadians": photo.yaw, "cameraPosition": photo.position, "cameraForward": photo.forward]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: label), as: UTF8.self)
            content.append(["type": "text", "text": "Snapshot \(index + 1): \(json)"])
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(photo.jpeg)"]])
        }
        return ["model": model.rawValue, "messages": [["role": "user", "content": content]],
                "response_format": ["type": "json_schema", "json_schema": ["name": "room_adventure", "schema": plan.schema]],
                "reasoning_effort": "low", "max_completion_tokens": 8192]
    }

    static func outputText(_ data: Data) throws -> String {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = response["choices"] as? [[String: Any]], let choice = choices.first,
              choice["finish_reason"] as? String == "stop",
              let message = choice["message"] as? [String: Any],
              message["role"] as? String == "assistant",
              message["refusal"] == nil || message["refusal"] is NSNull,
              let text = message["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlanError.server("Muse didn't return a complete answer. Your scan is still here; try again.")
        }
        return text
    }

    func send(key: String, payload: [String: Any], timeout: TimeInterval = 75) async throws -> Data {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanKey.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw PlanError.server("Enter your Meta Model API key in Muse connection settings.")
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
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
            case .timedOut: message = "Muse timed out before an answer arrived. Your scan is still here; try again."
            case .notConnectedToInternet: message = "Your iPhone reports no internet connection. Connect to Wi-Fi or cellular data, then try again."
            case .networkConnectionLost: message = "The connection to Meta dropped before Muse answered. Reconnect and try again."
            default: message = "Couldn't reach Meta's API (network error \(error.code.rawValue)). Check your connection and try again."
            }
            throw PlanError.server(message)
        }
        catch { throw PlanError.server("Couldn't complete the Muse request. Try again once or check your connection.") }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PlanError.invalidPlan }
        guard http.statusCode == 200 else {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "Meta rejected this key or its access. Check your Meta Model API key and project access."
            case 404: message = "\(model.name) isn't available for this key. Choose another Muse model or check model access."
            case 429: message = "Meta returned a rate limit or quota error for \(model.name). Check your project limits before retrying. Saved rooms still work offline."
            case 400, 422: message = "Meta couldn't accept this Muse request. Check your model access and app version."
            case 504: message = "Meta returned HTTP 504: Muse took too long to respond. Your scan is still here; try again."
            case 500...599: message = "Muse is temporarily unavailable. Your scan is still here; try again in a moment."
            default: message = "Meta returned HTTP \(http.statusCode). Check your API access and try again."
            }
            // Never reflect a provider body: it can contain credentials or room data.
            throw PlanError.server(message)
        }
        return data
    }
}
