import Foundation
import XCTest
@testable import AdventureCore

final class MuseClientTests: XCTestCase {
    private func fixture() throws -> GeminiClientTests.Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/room-plan.json")
        return try JSONDecoder().decode(GeminiClientTests.Fixture.self, from: Data(contentsOf: url))
    }

    private func response(_ text: String = "READY", finish: String = "stop", refusal: String? = nil) throws -> Data {
        var message: [String: Any] = ["role": "assistant", "content": text, "reasoning_content": "Never use this as the answer"]
        if let refusal { message["refusal"] = refusal }
        return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": message]]])
    }

    func testMusePayloadUsesAllPhotosAndSameFullPlanContractAsGemini() throws {
        let scan = try fixture().scan
        for friend in RealmFriend.allCases {
            let muse = try MuseClient.payload(candidates: scan.candidates, photos: scan.photos, friend: friend, context: scan.roomContext)
            let gemini = try GeminiClient.payload(candidates: scan.candidates, photos: scan.photos, friend: friend, context: scan.roomContext)
            XCTAssertEqual(muse["model"] as? String, "muse-spark-1.3")
            XCTAssertNil(muse["input"])
            XCTAssertNil(muse["generation_config"])
            XCTAssertEqual(muse["reasoning_effort"] as? String, "low")
            let messages = try XCTUnwrap(muse["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")
            let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 1 + 2 * scan.photos.count)
            let input = try XCTUnwrap(gemini["input"] as? [[String: Any]])
            XCTAssertEqual(content[0]["text"] as? String, input[0]["text"] as? String)
            for (index, photo) in scan.photos.enumerated() {
                func label(_ item: [String: Any]) throws -> NSDictionary {
                    let text = try XCTUnwrap(item["text"] as? String)
                    let prefix = "Snapshot \(index + 1): "
                    XCTAssertTrue(text.hasPrefix(prefix))
                    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.dropFirst(prefix.count).utf8)) as? NSDictionary)
                }
                // JSON object key order is immaterial; compare the measured pose.
                XCTAssertEqual(try label(content[index * 2 + 1]), try label(input[index * 2 + 1]))
                let image = try XCTUnwrap(content[index * 2 + 2]["image_url"] as? [String: String])
                XCTAssertEqual(image["url"], "data:image/jpeg;base64,\(photo.jpeg)")
            }
            let format = try XCTUnwrap(muse["response_format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            let schema = try XCTUnwrap((format["json_schema"] as? [String: Any])?["schema"] as? [String: Any])
            let geminiSchema = try XCTUnwrap((gemini["response_format"] as? [String: Any])?["schema"] as? [String: Any])
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys),
                           try JSONSerialization.data(withJSONObject: geminiSchema, options: .sortedKeys))
        }
    }

    func testBothTestAndRoomPlanSendSelectedMuseModelAndKeyOnlyToMetaHeader() async throws {
        let f = try fixture()
        for model in MuseModel.allCases {
            var calls = 0
            let reply = try response(String(decoding: JSONEncoder().encode(f.plan), as: UTF8.self))
            let client = MuseClient(model: model) { request in
                calls += 1
                XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer LLM|test|secret")
                XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
                let body = try XCTUnwrap(request.httpBody)
                XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("LLM|test|secret"))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["model"] as? String, model.rawValue)
                return (reply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            try await client.test(key: " LLM|test|secret\n")
            let result = try await client.plan(key: "LLM|test|secret", candidates: f.scan.candidates,
                photos: f.scan.photos, friend: .mosskip, context: f.scan.roomContext)
            XCTAssertEqual(result.objectID, f.plan.objectID)
            XCTAssertEqual(calls, 2)
        }
    }

    func testIncompleteRefusedAndMissingTextResponsesAreRejected() throws {
        XCTAssertEqual(try MuseClient.outputText(response()), "READY")
        for reason in ["length", "content_filter", "tool_calls", ""] {
            XCTAssertThrowsError(try MuseClient.outputText(response("valid-looking JSON", finish: reason)))
        }
        XCTAssertThrowsError(try MuseClient.outputText(response("READY", refusal: "No")))
        XCTAssertThrowsError(try MuseClient.outputText(response("   ")))
        XCTAssertThrowsError(try MuseClient.outputText(Data("{}".utf8)))
    }

    func testMuseCannotBypassMeasuredRoomOrPuzzleValidation() async throws {
        let f = try fixture()
        let invalid = EncounterPlan(objectID: "invented", hint: "Hi", greeting: "Hi", room: f.plan.room)
        for plan in [invalid, EncounterPlan(objectID: f.plan.objectID, hint: "Hi", greeting: "Hi")] {
            let reply = try response(String(decoding: JSONEncoder().encode(plan), as: UTF8.self))
            let client = MuseClient { request in
                (reply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do {
                _ = try await client.plan(key: "test", candidates: f.scan.candidates, photos: f.scan.photos,
                    friend: .mosskip, context: f.scan.roomContext)
                XCTFail("Invalid plan accepted")
            } catch {}
        }
        let text = String(decoding: try JSONEncoder().encode(f.plan), as: UTF8.self)
        XCTAssertThrowsError(try RoomPlanRequest.parse(text, candidates: f.scan.candidates, friend: .nibbi, context: f.scan.roomContext))
    }

    func testHTTPFailuresDoNotRetryLeakDetailsOrFallBackToGemini() async throws {
        for status in [400, 401, 403, 404, 429, 503, 504, 302] {
            var museCalls = 0, geminiCalls = 0
            let muse = MuseClient { request in
                museCalls += 1
                return (Data("private body test-secret".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            let gemini = GeminiClient { _ in geminiCalls += 1; throw PlanError.invalidPlan }
            let planner = PlanningClient(provider: .muse, muse: muse, gemini: gemini)
            do { try await planner.test(key: "test-secret"); XCTFail("Failure accepted") }
            catch {
                XCTAssertFalse(error.localizedDescription.contains("private body"))
                XCTAssertFalse(error.localizedDescription.contains("test-secret"))
                XCTAssertFalse(error.localizedDescription.contains("Gemini"))
            }
            XCTAssertEqual(museCalls, 1)
            XCTAssertEqual(geminiCalls, 0)
        }
    }

    func testProviderSelectionRoutesTheCompletePlanAndDefaultsToTheServer() async throws {
        // The server holds the Muse and Gemini keys, so it's the default; direct providers stay selectable.
        XCTAssertEqual(PlanningProvider.saved(nil), .server)
        XCTAssertEqual(PlanningProvider.saved("obsolete"), .server)
        XCTAssertEqual(PlanningProvider.saved("muse"), .muse)
        XCTAssertEqual(PlanningProvider.saved("gemini"), .gemini)
        XCTAssertFalse(PlanningProvider.server.needsKey)
        let f = try fixture()
        for provider in PlanningProvider.allCases {
            var museCalls = 0, geminiCalls = 0, serverCalls = 0
            let text = String(decoding: try JSONEncoder().encode(f.plan), as: UTF8.self)
            let museReply = try response(text)
            let geminiReply = try JSONSerialization.data(withJSONObject: ["status": "completed", "steps": [
                ["type": "model_output", "content": [["type": "text", "text": text]]]
            ]])
            let planner = PlanningClient(provider: provider, muse: MuseClient { request in
                museCalls += 1
                return (museReply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }, gemini: GeminiClient { request in
                geminiCalls += 1
                return (geminiReply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }, server: ServerPlanning(plan: { _, _, _, _ in serverCalls += 1; return f.plan }, test: nil))
            let result = try await planner.plan(key: "test", candidates: f.scan.candidates, photos: f.scan.photos,
                friend: .mosskip, context: f.scan.roomContext)
            XCTAssertEqual(result.room?.summary, f.plan.room?.summary)
            XCTAssertEqual(museCalls, provider == .muse ? 1 : 0)
            XCTAssertEqual(geminiCalls, provider == .gemini ? 1 : 0)
            XCTAssertEqual(serverCalls, provider == .server ? 1 : 0)
        }
    }

    func testMissingKeyCancellationAndDeadlineDoNotBecomeProviderFailures() async throws {
        var calls = 0
        let cancelled = MuseClient { _ in calls += 1; throw URLError(.cancelled) }
        do { try await cancelled.test(key: " \n"); XCTFail("Blank key accepted") } catch {}
        XCTAssertEqual(calls, 0)
        do { try await cancelled.test(key: "test"); XCTFail("Cancelled request accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        var stopped = false
        let slow = MuseClient { _ in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { stopped = true; throw error }
            throw PlanError.invalidPlan
        }
        let start = Date()
        do { try await slow.test(key: "test", timeout: 0.05); XCTFail("No timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("No response from Muse")) }
        XCTAssertTrue(stopped)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
