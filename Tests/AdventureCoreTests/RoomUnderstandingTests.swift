import Foundation
import XCTest
@testable import AdventureCore

final class RoomUnderstandingTests: XCTestCase {
    struct Fixture: Decodable {
        struct Scan: Decodable { let candidates: [RoomCandidate]; let roomContext: RoomScanContext }
        let scan: Scan
        let plan: EncounterPlan
    }

    private func fixture(edit: ((inout [String: Any]) -> Void)? = nil) throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/room-plan.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var plan = try XCTUnwrap(json["plan"] as? [String: Any])
        edit?(&plan)
        json["plan"] = plan
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func validate(_ fixture: Fixture) throws {
        try fixture.plan.validateRoom(against: fixture.scan.candidates, surfaces: fixture.scan.roomContext.surfaces)
    }

    func testSharedServerContractDecodesAndPreservesTreatments() throws {
        let value = try fixture()
        try validate(value)
        let decoded = try JSONDecoder().decode(EncounterPlan.self, from: JSONEncoder().encode(value.plan))
        XCTAssertEqual(decoded.room?.jungle.palette, .tropical)
        XCTAssertEqual(decoded.room?.jungle.floors.first?.growth, .meadow)
        XCTAssertEqual(decoded.room?.jungle.walls.map(\.vines), [.light, .lush])
        XCTAssertEqual(decoded.room?.keepsakeObjectID, "table-1")
    }

    func testLegacyQuestOnlyResponseCannotStartNewFlow() throws {
        let value = try fixture { $0.removeValue(forKey: "room") }
        XCTAssertThrowsError(try validate(value)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Restart server/server.py"))
        }
    }

    func testUnknownDuplicateMissingAndWrongKindSurfacesAreRejected() throws {
        for replacement in ["invented", "wall-2", "door-1", "floor-1", ""] {
            let value = try fixture { plan in
                var room = plan["room"] as! [String: Any]
                var jungle = room["jungle"] as! [String: Any]
                var walls = jungle["walls"] as! [[String: Any]]
                if replacement.isEmpty { walls.removeFirst() }
                else { walls[0]["surfaceID"] = replacement }
                jungle["walls"] = walls; room["jungle"] = jungle; plan["room"] = room
            }
            XCTAssertThrowsError(try validate(value), replacement)
        }
    }

    func testQuestLocationsMustExistAndDifferUnlessOnlyOneCandidate() throws {
        for keepsakeID in ["invented", "cabinet-1"] {
            let value = try fixture { plan in
                var room = plan["room"] as! [String: Any]
                room["keepsakeObjectID"] = keepsakeID; plan["room"] = room
            }
            XCTAssertThrowsError(try validate(value))
            if keepsakeID == "cabinet-1" {
                try value.plan.validateRoom(against: [value.scan.candidates[0]], surfaces: value.scan.roomContext.surfaces)
            }
        }
    }

    func testUnsupportedTreatmentCannotDecode() throws {
        XCTAssertThrowsError(try fixture { plan in
            var room = plan["room"] as! [String: Any]
            var jungle = room["jungle"] as! [String: Any]
            jungle["palette"] = "invented"; room["jungle"] = jungle; plan["room"] = room
        })
    }

    func testReviewMustFinishBeforeExplorationAndCannotBypassScan() {
        var game = Adventure()
        game.beginExploring()
        XCTAssertEqual(game.phase, .scanning)
        game.finishScan()
        game.beginExploring()
        XCTAssertEqual(game.phase, .planning)
        game.acceptPlan()
        XCTAssertEqual(game.phase, .ready)
        XCTAssertFalse(game.reveal(trackingReady: true, proximitySatisfied: true))
        XCTAssertFalse(game.talk(trackingReady: true, inReach: true))
        game.beginExploring()
        XCTAssertTrue(game.reveal(trackingReady: true, proximitySatisfied: true))
        game.beginExploring()
        XCTAssertEqual(game.phase, .revealed)
    }
}
