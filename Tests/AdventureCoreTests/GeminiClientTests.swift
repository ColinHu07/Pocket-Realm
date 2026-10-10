import Foundation
import XCTest
@testable import AdventureCore

final class GeminiClientTests: XCTestCase {
    struct Fixture: Decodable {
        struct Scan: Decodable {
            let candidates: [RoomCandidate]
            let photos: [ScanPhoto]
            let roomContext: RoomScanContext
        }
        let scan: Scan
        let plan: EncounterPlan
    }
    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/room-plan.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    private func response(_ text: String, status: String = "completed") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "steps": [
            ["type": "thought", "content": [["type": "text", "text": "Ignore this thought"]]],
            ["type": "model_output", "content": [["type": "text", "text": text]]]
        ]])
    }
    private func response(_ plan: EncounterPlan) throws -> Data {
        try response(String(decoding: JSONEncoder().encode(plan), as: UTF8.self))
    }

    func testPayloadPreservesSpatialPhotosAndRestrictsChoicesForEveryFriend() throws {
        let fixture = try fixture(), scan = fixture.scan
        for friend in RealmFriend.allCases {
            let payload = try GeminiClient.payload(candidates: scan.candidates, photos: scan.photos, friend: friend, context: scan.roomContext)
            XCTAssertEqual(payload["model"] as? String, "gemini-3.8-flash")
            XCTAssertEqual(payload["store"] as? Bool, false)
            let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
            XCTAssertEqual(input.count, 1 + 2 * scan.photos.count)
            XCTAssertEqual(input[2]["data"] as? String, scan.photos[0].jpeg)
            XCTAssertTrue(try XCTUnwrap(input[1]["text"] as? String).contains("cameraForward"))
            let format = try XCTUnwrap(payload["response_format"] as? [String: Any])
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertEqual((properties["objectID"] as? [String: Any])?["enum"] as? [String], scan.candidates.map(\.id))
            let expected = QuestBlueprint.allCases.filter { $0.friend == friend }.map(\.rawValue)
            if expected.isEmpty { XCTAssertNil(properties["challenge"]) }
            else {
                let challenge = try XCTUnwrap(properties["challenge"] as? [String: Any])
                let fields = try XCTUnwrap(challenge["properties"] as? [String: Any])
                XCTAssertEqual((fields["blueprintID"] as? [String: Any])?["enum"] as? [String], expected)
                XCTAssertTrue((schema["required"] as? [String])?.contains("challenge") == true)
            }
        }
    }

    func testProviderResponseUsesExistingRoomValidationAndRequiresPuzzles() throws {
        let fixture = try fixture(), scan = fixture.scan
        func parse(_ plan: EncounterPlan, friend: RealmFriend = .mosskip) throws -> EncounterPlan {
            try GeminiClient.parse(response(plan), candidates: scan.candidates, friend: friend, context: scan.roomContext)
        }
        XCTAssertEqual(try parse(fixture.plan).room?.summary, fixture.plan.room?.summary)
        var incomplete = fixture.plan
        incomplete.room = nil
        XCTAssertThrowsError(try parse(incomplete))
        XCTAssertThrowsError(try parse(fixture.plan, friend: .nibbi))
        var puzzle = fixture.plan
        puzzle.challenge = QuestPlan(blueprintID: "nibbi-cocoa", introduction: "Let's bake a cookie!")
        XCTAssertNoThrow(try parse(puzzle, friend: .nibbi))
        XCTAssertThrowsError(try parse(puzzle, friend: .bloopi))
        XCTAssertThrowsError(try parse(puzzle, friend: .mosskip))
        let invalid = EncounterPlan(objectID: "not-in-scan", hint: "Hi", greeting: "Hi", room: fixture.plan.room)
        XCTAssertThrowsError(try parse(invalid))
    }

    func testIncompleteAndNonModelOutputCannotBecomeAPlan() throws {
        XCTAssertThrowsError(try GeminiClient.outputText(response("READY", status: "incomplete")))
        XCTAssertEqual(try GeminiClient.outputText(response("READY")), "READY")
        XCTAssertThrowsError(try GeminiClient.outputText(Data("{}".utf8)))
    }

    func testTestConnectionSendsKeyOnlyInGoogleHTTPSHeader() async throws {
        var calls = 0
        let data = try response("READY")
        let client = GeminiClient { request in
            calls += 1
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-only-key")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-only-key"))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gemini-3.8-flash")
            XCTAssertEqual(payload["store"] as? Bool, false)
            let generation = try XCTUnwrap(payload["generation_config"] as? [String: Any])
            XCTAssertEqual(generation["thinking_level"] as? String, "low")
            XCTAssertGreaterThan(GeminiClient.connectionTimeout, 20)
            XCTAssertGreaterThan(request.timeoutInterval, GeminiClient.connectionTimeout)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await client.test(key: " test-only-key\n")
        XCTAssertEqual(calls, 1)
    }

    func testSelectedModelIsUsedForBothConnectionAndRoomPlanning() async throws {
        let fixture = try fixture()
        for model in GeminiModel.allCases {
            var calls = 0
            let reply = try response(fixture.plan)
            let client = GeminiClient(model: model) { request in
                calls += 1
                let body = try XCTUnwrap(request.httpBody)
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(payload["model"] as? String, model.rawValue)
                return (reply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            try await client.test(key: "test-only-key")
            let plan = try await client.plan(key: "test-only-key", candidates: fixture.scan.candidates,
                photos: fixture.scan.photos, friend: .mosskip, context: fixture.scan.roomContext)
            XCTAssertEqual(plan.objectID, fixture.plan.objectID)
            XCTAssertEqual(calls, 2)
        }
    }

    func testQuotaFailureNamesSelectedModelWithoutInventingDailyExhaustion() async throws {
        let client = GeminiClient(model: .flash36) { request in
            (Data("private-provider-error".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        do {
            try await client.test(key: "test-only-key")
            XCTFail("Expected a quota error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Gemini 3.6 Flash"))
            XCTAssertFalse(error.localizedDescription.contains("free-tier rate limit or quota was reached"))
            XCTAssertFalse(error.localizedDescription.contains("private-provider-error"))
        }
    }

    func testAuthAndQuotaFailuresAreNotRetriedOrReflected() async throws {
        for status in [400, 401, 403, 404, 429, 503, 504] {
            var calls = 0
            let client = GeminiClient { request in
                calls += 1
                return (Data("private-provider-error".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do {
                try await client.test(key: "test-only-key")
                XCTFail("Expected HTTP \(status) to fail")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("private-provider-error"))
                XCTAssertFalse(error.localizedDescription.contains("test-only-key"))
                if status == 429 { XCTAssertTrue(error.localizedDescription.contains("quota")) }
                if status == 504 { XCTAssertTrue(error.localizedDescription.contains("HTTP 504")) }
            }
            XCTAssertEqual(calls, 1)
        }
    }

    func testMissingKeyMakesNoRequestAndCancellationStaysCancellation() async throws {
        var calls = 0
        let client = GeminiClient { _ in calls += 1; throw URLError(.cancelled) }
        do { try await client.test(key: " \n"); XCTFail("Missing key accepted") } catch {}
        XCTAssertEqual(calls, 0)
        do { try await client.test(key: "test-only-key"); XCTFail("Cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 1)
    }

    func testSlowConnectionTimesOutAndCancelsRequest() async throws {
        var calls = 0
        var cancelled = false
        let client = GeminiClient { _ in
            calls += 1
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { cancelled = true; throw error }
            XCTFail("The timeout should cancel the network task")
            throw URLError(.timedOut)
        }
        let started = Date()
        do {
            try await client.test(key: "test-only-key", timeout: 0.05)
            XCTFail("A stalled request must time out")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No response from Gemini 3.8 Flash within"))
            XCTAssertTrue(error.localizedDescription.contains("doesn't confirm a bad key or exhausted quota"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(cancelled)
    }

    func testDelayedResponseCanSucceedBeforeDeadline() async throws {
        var calls = 0
        let data = try response("READY")
        let client = GeminiClient { request in
            calls += 1
            try await Task.sleep(nanoseconds: 75_000_000)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await client.test(key: "test-only-key", timeout: 1)
        XCTAssertEqual(calls, 1)
    }

    func testNetworkFailuresHaveSpecificMessagesWithoutLeakingDetailsOrRetrying() async throws {
        let cases: [(URLError.Code, String)] = [
            (.timedOut, "timed out before an answer arrived"),
            (.notConnectedToInternet, "no internet connection"),
            (.networkConnectionLost, "connection to Google dropped"),
            (.cannotFindHost, "couldn't connect to Google's API server"),
            (.cannotConnectToHost, "couldn't connect to Google's API server"),
            (.dnsLookupFailed, "couldn't connect to Google's API server"),
            (.secureConnectionFailed, "network error -1200")
        ]
        for (code, expected) in cases {
            var calls = 0
            let client = GeminiClient { _ in
                calls += 1
                throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "private-provider-error test-only-key"])
            }
            do { try await client.test(key: "test-only-key"); XCTFail("Expected a network failure") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
                XCTAssertFalse(error.localizedDescription.contains("private-provider-error"))
                XCTAssertFalse(error.localizedDescription.contains("test-only-key"))
            }
            XCTAssertEqual(calls, 1)
        }
    }

    func testSuccessfulConnectionAcceptsModelPunctuation() async throws {
        let data = try response("READY!")
        let client = GeminiClient { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await client.test(key: "test-only-key")
    }

    func testCancellingConnectionCancelsPendingRequest() async throws {
        let client = GeminiClient { _ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            throw URLError(.cancelled)
        }
        let task = Task { try await client.test(key: "test-only-key") }
        task.cancel()
        do { try await task.value; XCTFail("Cancellation should finish the test") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
