import XCTest
@testable import AdventureCore

final class DrawingTests: XCTestCase {
    func testDrawingWorkshopDoesNotNeedAServerGeminiKey() throws {
        let health = try JSONDecoder().decode(AdventureServerHealth.self,
            from: Data(#"{"geminiConfigured":false,"drawings":true}"#.utf8))
        XCTAssertNoThrow(try health.validate(drawingsRequired: true))
        XCTAssertThrowsError(try health.validate(drawingsRequired: false))
    }

    func testLegacyPlanningServerCannotAcceptDrawingJobs() throws {
        let health = try JSONDecoder().decode(AdventureServerHealth.self,
            from: Data(#"{"geminiConfigured":true}"#.utf8))
        XCTAssertNoThrow(try health.validate(drawingsRequired: false))
        XCTAssertThrowsError(try health.validate(drawingsRequired: true))
        let unrelated = try JSONDecoder().decode(AdventureServerHealth.self, from: Data("{}".utf8))
        XCTAssertThrowsError(try unrelated.validate(drawingsRequired: true))
        XCTAssertThrowsError(try unrelated.validate(drawingsRequired: false))
    }

    private func status(_ json: String) throws -> DrawingStatus {
        try JSONDecoder().decode(DrawingStatus.self, from: Data(json.utf8))
    }

    func testServerStatusesMapToProgress() throws {
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"queued","ahead":2}"#)), .queued(ahead: 2))
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"working"}"#)), .building)
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"ready","name":"paper boat"}"#)), .ready(name: "paper boat"))
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"failed","error":"Too faint."}"#)), .failed("Too faint."))
    }

    func testUnknownOrIncompleteStatusesFailSafely() throws {
        guard case .failed = DrawingProgress(try status(#"{"id":"a","status":"exploded"}"#)) else { return XCTFail() }
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"ready"}"#)).readyName, "drawing")
        XCTAssertEqual(DrawingProgress(try status(#"{"id":"a","status":"queued","ahead":-3}"#)), .queued(ahead: 0))
    }

    func testOnlyInFlightStatesAreWorking() {
        XCTAssertTrue(DrawingProgress.uploading.isWorking)
        XCTAssertTrue(DrawingProgress.queued(ahead: 0).isWorking)
        XCTAssertTrue(DrawingProgress.building.isWorking)
        XCTAssertFalse(DrawingProgress.none.isWorking)
        XCTAssertFalse(DrawingProgress.ready(name: "rocket").isWorking)
        XCTAssertFalse(DrawingProgress.failed("x").isWorking)
        XCTAssertNil(DrawingProgress.building.readyName)
        XCTAssertTrue(DrawingProgress.ready(name: "rocket").message.contains("rocket"))
    }
}
