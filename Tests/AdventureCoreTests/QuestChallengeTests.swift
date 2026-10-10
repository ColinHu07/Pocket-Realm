import Foundation
import XCTest
@testable import AdventureCore

final class QuestChallengeTests: XCTestCase {
    private func finishPlayback(_ game: inout QuestGame) {
        for _ in 0..<100 { game.advancePlayback(delta: 0.1, available: true) }
        XCTAssertEqual(game.memoryStage, .recalling)
    }

    func testEveryRecipeAndWarmthVariationHasAPlayableSolution() {
        for blueprint in QuestBlueprint.allCases where blueprint.kind != .memory {
            var game = QuestGame(blueprint: blueprint)
            for id in blueprint.solution { XCTAssertEqual(game.perform(.select(id)), .changed) }
            XCTAssertEqual(game.perform(.submit), .won, blueprint.rawValue)
            XCTAssertTrue(game.solved)
            XCTAssertEqual(game.perform(.submit), .ignored)
            XCTAssertEqual(game.perform(.hint), .ignored)
        }
    }

    func testRecipeAcceptsAnyValidCombinationButRejectsForbiddenAndMissingTraits() {
        var game = QuestGame(blueprint: .nibbiCocoa)
        for id in ["oats", "berries", "lemon"] { game.perform(.select(id)) }
        XCTAssertEqual(game.perform(.submit), .retry)
        XCTAssertTrue(game.feedback.contains("sour"))
        XCTAssertFalse(game.solved)
        game.perform(.select("lemon"))
        game.perform(.select("mint"))
        XCTAssertEqual(game.perform(.submit), .retry)
        XCTAssertTrue(game.feedback.contains("chocolate"))
        game.perform(.select("mint")); game.perform(.select("cocoa"))
        // Honey is also sweet: there is no arbitrary single hidden recipe.
        game.perform(.select("berries")); game.perform(.select("honey"))
        XCTAssertEqual(game.perform(.submit), .won)
    }

    func testRecipeBowlLimitUnknownInputsAndHintsCannotAwardAWin() {
        var game = QuestGame(blueprint: .nibbiMint)
        XCTAssertEqual(game.perform(.select("invented")), .ignored)
        XCTAssertEqual(game.perform(.submit), .ignored)
        for id in ["oats", "berries", "honey", "mint"] { game.perform(.select(id)) }
        XCTAssertEqual(game.selected.count, 3)
        XCTAssertFalse(game.selected.contains("mint"))
        XCTAssertEqual(game.perform(.submit), .retry)
        for _ in 0..<3 { game.perform(.hint) }
        XCTAssertTrue(game.feedback.contains("Moon oats + Star berries + Mint leaf"))
        XCTAssertFalse(game.solved)
        game.perform(.select("honey")); game.perform(.select("mint"))
        XCTAssertEqual(game.perform(.submit), .won)
    }

    func testWarmthFeedbackSupportsRemovingTreatsAndExactTotals() {
        var game = QuestGame(blueprint: .cindletToast)
        game.perform(.select("ember-3"))
        XCTAssertEqual(game.perform(.submit), .retry)
        XCTAssertTrue(game.feedback.contains("5 more"))
        game.perform(.select("ember-5")); game.perform(.select("ember-2"))
        XCTAssertEqual(game.perform(.submit), .retry)
        XCTAssertTrue(game.feedback.contains("2 too much"))
        game.perform(.select("ember-2"))
        XCTAssertEqual(game.warmth, 8)
        XCTAssertEqual(game.perform(.submit), .won)
    }

    func testBothMemoryPatternsNeedThreeDemonstrationsAndOrderedAnswers() {
        for blueprint in QuestBlueprint.allCases where blueprint.kind == .memory {
            var game = QuestGame(blueprint: blueprint)
            XCTAssertEqual(game.perform(.select(blueprint.pattern[0])), .ignored)
            for round in 0..<3 {
                game.perform(.replay)
                XCTAssertEqual(game.highlightedID, blueprint.pattern[0])
                XCTAssertEqual(game.perform(.select(blueprint.pattern[0])), .ignored)
                finishPlayback(&game)
                let pattern = game.roundPattern
                for (index, id) in pattern.enumerated() {
                    let result = game.perform(.select(id))
                    XCTAssertEqual(result, index == pattern.count - 1 ? (round == 2 ? .won : .roundWon) : .changed)
                }
            }
            XCTAssertTrue(game.solved)
            XCTAssertEqual(game.perform(.replay), .ignored)
        }
    }

    func testMemoryMistakesReplayHintsAndTrackingPausePreserveCompletedRounds() {
        var game = QuestGame(blueprint: .bloopiRipple)
        game.perform(.replay); finishPlayback(&game)
        for id in game.roundPattern { game.perform(.select(id)) }
        XCTAssertEqual(game.round, 1)
        game.perform(.replay)
        game.advancePlayback(delta: 0.1, available: true)
        game.advancePlayback(delta: 0, available: false)
        XCTAssertEqual(game.memoryStage, .ready)
        XCTAssertNil(game.highlightedID)
        XCTAssertEqual(game.round, 1)
        game.perform(.replay); finishPlayback(&game)
        XCTAssertEqual(game.perform(.select("wiggle")), .retry)
        XCTAssertEqual(game.round, 1)
        game.perform(.hint)
        game.perform(.replay); finishPlayback(&game)
        XCTAssertEqual(game.coaching, "Next move: Bubble")
        game.perform(.select("bubble"))
        XCTAssertEqual(game.coaching, "Next move: Plop")
        game.perform(.replay)
        XCTAssertEqual(game.inputIndex, 0)
        game.perform(.hint)
        XCTAssertEqual(game.memoryStage, .ready)
        XCTAssertFalse(game.solved)
    }

    func testInteractiveAdventureCannotBypassPuzzleOrCompleteTwice() {
        var adventure = Adventure()
        adventure.finishScan()
        adventure.acceptPlan(challenge: QuestGame(blueprint: .cindletToast))
        XCTAssertFalse(adventure.beginChallenge(trackingReady: true, inReach: true))
        adventure.beginExploring()
        adventure.reveal(trackingReady: true, proximitySatisfied: true)
        adventure.talk(trackingReady: true, inReach: true)
        adventure.collect(trackingReady: true, inReach: true)
        XCTAssertFalse(adventure.finishQuest(trackingReady: true, inReach: true))
        XCTAssertFalse(adventure.beginChallenge(trackingReady: false, inReach: true))
        XCTAssertFalse(adventure.beginChallenge(trackingReady: true, inReach: false))
        XCTAssertTrue(adventure.beginChallenge(trackingReady: true, inReach: true))
        XCTAssertFalse(adventure.finishQuest(trackingReady: true, inReach: true))
        XCTAssertEqual(adventure.playChallenge(.select("ember-1"), trackingReady: false, inReach: true), .ignored)
        XCTAssertEqual(adventure.playChallenge(.select("ember-1"), trackingReady: true, inReach: false), .ignored)
        adventure.playChallenge(.select("ember-3"), trackingReady: true, inReach: true)
        adventure.playChallenge(.select("ember-5"), trackingReady: true, inReach: true)
        XCTAssertEqual(adventure.playChallenge(.submit, trackingReady: true, inReach: true), .won)
        XCTAssertFalse(adventure.finishQuest(trackingReady: false, inReach: true))
        XCTAssertTrue(adventure.finishQuest(trackingReady: true, inReach: true))
        XCTAssertFalse(adventure.finishQuest(trackingReady: true, inReach: true))
        XCTAssertEqual(adventure.playChallenge(.replay, trackingReady: true, inReach: true), .ignored)
    }

    func testSharedGeminiContractAndFriendValidation() throws {
        struct Fixture: Decodable { let friend: RealmFriend; let challenge: QuestPlan }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/quest-plans.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(fixtures.map { $0.challenge.blueprintID }), Set(QuestBlueprint.allCases.map(\.rawValue)))
        for fixture in fixtures {
            try fixture.challenge.validate(for: fixture.friend)
            XCTAssertThrowsError(try fixture.challenge.validate(for: .mosskip))
        }
        XCTAssertThrowsError(try QuestPlan(blueprintID: "invented", introduction: "Hello").validate(for: .nibbi))
        XCTAssertThrowsError(try QuestPlan(blueprintID: "nibbi-cocoa", introduction: " ").validate(for: .nibbi))
        XCTAssertThrowsError(try QuestPlan(blueprintID: "nibbi-cocoa", introduction: String(repeating: "a", count: 241)).validate(for: .nibbi))
    }
}
