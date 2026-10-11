import XCTest
@testable import AdventureCore

final class PoetryQuestTests: XCTestCase {
    func testCompletesOnlyAfterBothCouplets() throws {
        var quest = PoetryQuest()
        let a = "My little cookie shines so bright!"
        XCTAssertTrue(quest.submit(a, pairIndex: 0, heard: a).hasPrefix("Accepted"))
        XCTAssertFalse(quest.complete)
        XCTAssertEqual(quest.pair, 1)
        let b = "Then all my friends came out to play."
        XCTAssertTrue(quest.submit(b, pairIndex: 1, heard: b).contains("Poem complete"))
        XCTAssertTrue(quest.complete)
        XCTAssertEqual(quest.lines.count, 2)
        let restored = try JSONDecoder().decode(PoetryQuest.self, from: JSONEncoder().encode(quest))
        XCTAssertEqual(restored, quest)
    }
    func testWrongRhymeDoesNotAdvance() {
        var quest = PoetryQuest()
        let line = "I ate a tasty cookie."
        _ = quest.submit(line, pairIndex: 0, heard: line)
        XCTAssertTrue(quest.lines.isEmpty)
    }
    func testPhoneticsNotSpelling() {
        XCTAssertTrue(RhymeWords.night.contains("white"))
        XCTAssertFalse(RhymeWords.night.contains("eight"))
        XCTAssertTrue(RhymeWords.day.contains("cafe"))
    }
    func testCannotInventLineOrSkipPairOrRepeatTarget() {
        var quest = PoetryQuest()
        _ = quest.submit("Cookies glow so bright", pairIndex: 0, heard: "What are the rules?")
        _ = quest.submit("Cookies glow so bright", pairIndex: 1, heard: "Cookies glow so bright")
        _ = quest.submit("We love the night", pairIndex: 0, heard: "We love the night")
        _ = quest.submit("bright", pairIndex: 0, heard: "bright")
        XCTAssertTrue(quest.lines.isEmpty)
    }
    func testDuplicateOldPairDoesNotCountTwice() {
        var quest = PoetryQuest()
        let line = "Cookies glow so bright"
        _ = quest.submit(line, pairIndex: 0, heard: line)
        _ = quest.submit(line, pairIndex: 0, heard: line)
        XCTAssertEqual(quest.lines.count, 1)
    }
}
