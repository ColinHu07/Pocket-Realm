import XCTest
@testable import AdventureCore

final class SketchQuestTests: XCTestCase {
    func testCardDecodesServerJSONAndDefaultsMissingFields() throws {
        let full = try JSONDecoder().decode(DrawingCard.self, from: Data(#"""
            {"name":"cool sun","kind":"character","title":"Sunny Shades","verb":"shine","uses":2,
             "arrival":"Sunny floats in!","success":"The ice melts.","lines":["Beach day!"],"voice":"high"}
            """#.utf8))
        XCTAssertEqual(full.displayName, "Sunny Shades")
        XCTAssertEqual(full.verbButton, "Shine!")
        XCTAssertEqual(full.voice, .high)
        let sparse = try JSONDecoder().decode(DrawingCard.self, from: Data(#"{"name":"rock","kind":"weapon","uses":"x","verb":""}"#.utf8))
        XCTAssertEqual(sparse.kind, .object)
        XCTAssertEqual(sparse.uses, 2)
        XCTAssertEqual(sparse.verb, "use")
        XCTAssertEqual(sparse.displayName, "your rock")
        XCTAssertEqual(Workshop.arrival(sparse), "Your rock just landed!")
    }

    func testStatusCarriesTheCard() throws {
        let status = try JSONDecoder().decode(DrawingStatus.self, from: Data(#"""
            {"id":"a","status":"ready","name":"fan","card":{"name":"fan","kind":"tool","verb":"blow","uses":3}}
            """#.utf8))
        XCTAssertEqual(status.card?.kind, .tool)
        XCTAssertEqual(status.card?.clampedUses, 3)
    }

    func testUsesAreClampedAndCounted() {
        var progress = TrapProgress(needed: 9)
        XCTAssertEqual(progress.needed, 5)
        for _ in 0..<5 { XCTAssertTrue(progress.use()) }
        XCTAssertTrue(progress.cleared)
        XCTAssertFalse(progress.use())
        XCTAssertEqual(TrapProgress(needed: 0).needed, 1)
        XCTAssertEqual(DrawingCard(name: "x", kind: .tool, uses: -4).clampedUses, 1)
    }

    func testEveryTrapHasCompleteCopyNamingTheItemAndPlace() {
        for (index, trap) in Challenge.Trap.allCases.enumerated() {
            let challenge = Challenge.pick(seed: index, item: "dew seed", place: "table")
            XCTAssertEqual(challenge.trap, trap)
            XCTAssertTrue(challenge.prompt.contains("dew seed"))
            XCTAssertTrue(challenge.prompt.contains("Draw"))
            XCTAssertTrue(challenge.plea.contains("dew seed"))
            XCTAssertFalse(challenge.title.isEmpty || challenge.cleared.isEmpty)
            XCTAssertTrue(challenge.codexContext.contains(challenge.prompt))
        }
        XCTAssertEqual(Challenge.pick(seed: -1, item: "a", place: "b").trap, Challenge.Trap.allCases.last)
    }

    func testWorkshopWhimsyCyclesAndMentionsTheFriend() {
        XCTAssertEqual(Workshop.whimsy(0, friend: "Nibbi"), Workshop.whimsy(12, friend: "Nibbi"))
        XCTAssertTrue((0..<12).map { Workshop.whimsy($0, friend: "Nibbi") }.contains { $0.contains("Nibbi") })
        XCTAssertFalse(Workshop.whimsy(-3, friend: "Nibbi").isEmpty)
    }
}
