import XCTest
@testable import AdventureCore

final class AdventureTests: XCTestCase {
    func testScanAndPlanMustFinishBeforeReveal() {
        var game = Adventure()
        game.acceptPlan()
        XCTAssertEqual(game.phase, .scanning)
        XCTAssertFalse(game.reveal(trackingReady: true, proximitySatisfied: true))
        game.finishScan()
        XCTAssertFalse(game.reveal(trackingReady: true, proximitySatisfied: true))
        game.acceptPlan()
        XCTAssertFalse(game.reveal(trackingReady: false, proximitySatisfied: true))
        XCTAssertFalse(game.reveal(trackingReady: true, proximitySatisfied: false))
        XCTAssertTrue(game.reveal(trackingReady: true, proximitySatisfied: true))
        XCTAssertFalse(game.reveal(trackingReady: true, proximitySatisfied: true))
        XCTAssertFalse(game.talk(trackingReady: true, inReach: false))
        XCTAssertTrue(game.talk(trackingReady: true, inReach: true))
    }
    func testProximityRequiresLeavingAndDwelling() {
        var gate = ProximityGate()
        XCTAssertFalse(gate.update(distance: 0.8, timestamp: 0, valid: true))
        XCTAssertFalse(gate.update(distance: 0.8, timestamp: 5, valid: true))
        XCTAssertFalse(gate.update(distance: 2, timestamp: 6, valid: true))
        XCTAssertFalse(gate.update(distance: 1.3, timestamp: 7, valid: true))
        XCTAssertFalse(gate.update(distance: 1.3, timestamp: 7.7, valid: true))
        XCTAssertTrue(gate.update(distance: 1.3, timestamp: 7.9, valid: true))
    }
    func testTrackingLossAndRangeExitCancelDwell() {
        var gate = ProximityGate()
        _ = gate.update(distance: 2, timestamp: 0, valid: true)
        _ = gate.update(distance: 1, timestamp: 1, valid: true)
        XCTAssertFalse(gate.update(distance: 1, timestamp: 2, valid: false))
        XCTAssertFalse(gate.update(distance: 1, timestamp: 3, valid: true))
        XCTAssertFalse(gate.update(distance: 1.6, timestamp: 3.7, valid: true))
        XCTAssertFalse(gate.update(distance: 1, timestamp: 4, valid: true))
        XCTAssertTrue(gate.update(distance: 1, timestamp: 5, valid: true))
    }
    func testSweepNeedsDistinctDirectionsAndIgnoresInvalidTracking() {
        var sweep = ScanCoverage()
        for _ in 0..<100 { sweep.observe(yaw: 0, trackingReady: true) }
        XCTAssertFalse(sweep.complete)
        sweep.observe(yaw: .pi, trackingReady: false)
        XCTAssertEqual(sweep.bins.count, 1)
        for index in 0..<24 { sweep.observe(yaw: (Double(index) + 0.5) / 24 * 2 * .pi, trackingReady: true) }
        XCTAssertTrue(sweep.complete)
        XCTAssertEqual(sweep.fraction, 1)
    }
    func testRejectsInventedLocationAndEmptyText() throws {
        let candidates = [RoomCandidate(id: "table-1", category: "table", dimensions: [1, 1, 1], position: [0, 0, 0], distance: 2)]
        XCTAssertThrowsError(try EncounterPlan(objectID: "invented", hint: "Go there", greeting: "Hello").validate(against: candidates))
        XCTAssertThrowsError(try EncounterPlan(objectID: "table-1", hint: " ", greeting: "Hello").validate(against: candidates))
        try EncounterPlan(objectID: "table-1", hint: "Near the table", greeting: "Hello").validate(against: candidates)
    }
}
