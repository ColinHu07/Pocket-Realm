import Foundation

/// Gemini selects a supported variation; puzzle rules and answers stay in the app.
struct QuestPlan: Codable, Equatable {
    let blueprintID: String
    let introduction: String

    func validate(for friend: RealmFriend) throws {
        guard let blueprint = QuestBlueprint(rawValue: blueprintID), blueprint.friend == friend,
              !introduction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              introduction.count <= 240 else { throw PlanError.invalidPlan }
    }
}

struct QuestOption: Identifiable {
    let id: String
    let name: String
    let symbol: String
    var traits: Set<String> = []
    var warmth: Int = 0
    var caption: String { warmth > 0 ? "+\(warmth) warmth" : traits.sorted().joined(separator: " · ") }
}

enum QuestKind { case recipe, warmth, memory }

enum QuestBlueprint: String, CaseIterable {
    case nibbiCocoa = "nibbi-cocoa", nibbiMint = "nibbi-mint"
    case cindletToast = "cindlet-toast", cindletStars = "cindlet-stars"
    case bloopiRipple = "bloopi-ripple", bloopiDance = "bloopi-dance"

    var friend: RealmFriend {
        switch self {
        case .nibbiCocoa, .nibbiMint: return .nibbi
        case .cindletToast, .cindletStars: return .cindlet
        case .bloopiRipple, .bloopiDance: return .bloopi
        }
    }
    var kind: QuestKind {
        switch friend {
        case .nibbi: return .recipe
        case .cindlet: return .warmth
        default: return .memory
        }
    }
    static func first(for friend: RealmFriend) -> Self? { allCases.first { $0.friend == friend } }
    var title: String {
        switch kind {
        case .recipe: return "The impossible snack"
        case .warmth: return "Too hot for toast"
        case .memory: return "Speak fluent Bloop"
        }
    }
    var introduction: String {
        switch kind {
        case .recipe: return "Emergency! I promised to invent the best cookie in the universe. Be my official taste-test partner?"
        case .warmth: return "My tail-powered oven is a little dramatic. Help me make the coziest toast in the realm!"
        case .memory: return "That ripple stone is our invitation to a puddle concert! I'll teach you the secret Bloop language."
        }
    }
    var requiredTraits: [String] { self == .nibbiMint ? ["crunchy", "sweet", "fresh"] : ["crunchy", "sweet", "chocolate"] }
    var forbiddenTrait: String { self == .nibbiMint ? "sticky" : "sour" }
    var targetWarmth: Int { self == .cindletStars ? 9 : 8 }
    var pattern: [String] { self == .bloopiDance ? ["wiggle", "bubble", "wiggle", "plop"] : ["bubble", "plop", "wiggle", "bubble"] }
    var instructions: String {
        switch kind {
        case .recipe: return "Choose 3 different ingredients. Together they need to be \(requiredTraits.joined(separator: ", ")). Nothing \(forbiddenTrait)!"
        case .warmth: return "Make exactly \(targetWarmth) warmth. Tap ember treats to add or remove them; use each treat once. Then try the oven."
        case .memory: return "Watch my moves, then tap them in the same order. Learn all 3 verses. Replay as often as you like!"
        }
    }
    var options: [QuestOption] {
        switch kind {
        case .recipe: return [
            .init(id: "oats", name: "Moon oats", symbol: "leaf.fill", traits: ["crunchy"]),
            .init(id: "berries", name: "Star berries", symbol: "sparkles", traits: ["sweet", "juicy"]),
            .init(id: "honey", name: "Cloud honey", symbol: "drop.fill", traits: ["sweet", "sticky"]),
            .init(id: "lemon", name: "Sour lemon", symbol: "sun.max.fill", traits: ["sour", "juicy"]),
            .init(id: "cocoa", name: "Cocoa chips", symbol: "square.grid.2x2.fill", traits: ["chocolate"]),
            .init(id: "mint", name: "Mint leaf", symbol: "leaf", traits: ["fresh"])
        ]
        case .warmth: return [1, 2, 3, 5].map { .init(id: "ember-\($0)", name: "\($0)", symbol: "flame.fill", warmth: $0) }
        case .memory: return [
            .init(id: "bubble", name: "Bubble", symbol: "circle.dotted"),
            .init(id: "wiggle", name: "Wiggle", symbol: "waveform.path"),
            .init(id: "plop", name: "Plop", symbol: "drop.fill")
        ]
        }
    }
    var solution: [String] {
        switch kind {
        case .recipe: return self == .nibbiMint ? ["oats", "berries", "mint"] : ["oats", "berries", "cocoa"]
        case .warmth: return self == .cindletStars ? ["ember-1", "ember-3", "ember-5"] : ["ember-3", "ember-5"]
        case .memory: return pattern
        }
    }
    var rewardName: String {
        switch kind {
        case .recipe: return self == .nibbiMint ? "Moon-mint friendship cookie" : "Chocolate-cloud friendship cookie"
        case .warmth: return "Perfectly cozy heart toast"
        case .memory: return "The Pocket Puddle Concert"
        }
    }
    var success: String {
        switch kind {
        case .recipe: return "CRUNCH! That's it! One \(rewardName.lowercased()) for you, one for me. Best taste-test partner ever."
        case .warmth: return "Ding! Golden toast, a tiny heart, and exactly the right amount of cozy. We make a brilliant team!"
        case .memory: return "Bubble, wiggle, PLOP! You speak fluent Bloop! This puddle concert is officially dedicated to you."
        }
    }
}

enum QuestAction { case select(String), submit, hint, replay }
enum QuestOutcome { case ignored, changed, retry, roundWon, won }

/// Value-state rules also drive the camera-free practice screen. No network calls during play.
struct QuestGame {
    enum MemoryStage { case ready, showing, recalling }
    let blueprint: QuestBlueprint
    private(set) var selected: Set<String> = []
    private(set) var attempts = 0
    private(set) var hints = 0
    private(set) var solved = false
    private(set) var feedback: String
    private(set) var round = 0
    private(set) var inputIndex = 0
    private(set) var memoryStage: MemoryStage = .ready
    private(set) var playbackTime: Double = 0

    init(blueprint: QuestBlueprint, introduction: String? = nil) {
        self.blueprint = blueprint
        feedback = introduction ?? blueprint.introduction
    }
    var warmth: Int { blueprint.options.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.warmth } }
    var roundPattern: [String] { Array(blueprint.pattern.prefix(min(4, round + 2))) }
    var beatDuration: Double { hints > 0 ? 1.5 : 1.05 }
    var highlightedID: String? {
        guard memoryStage == .showing else { return nil }
        let index = Int(playbackTime / beatDuration)
        guard roundPattern.indices.contains(index), playbackTime.truncatingRemainder(dividingBy: beatDuration) < beatDuration * 0.75 else { return nil }
        return roundPattern[index]
    }
    var coaching: String? {
        guard hints > 0, memoryStage == .recalling, roundPattern.indices.contains(inputIndex) else { return nil }
        return "Next move: " + (blueprint.options.first { $0.id == roundPattern[inputIndex] }?.name ?? "")
    }
    var canSubmit: Bool { !solved && (blueprint.kind == .recipe ? selected.count == 3 : blueprint.kind == .warmth && !selected.isEmpty) }

    @discardableResult mutating func perform(_ action: QuestAction) -> QuestOutcome {
        guard !solved else { return .ignored }
        switch action {
        case .select(let id):
            guard blueprint.options.contains(where: { $0.id == id }) else { return .ignored }
            if blueprint.kind == .memory {
                guard memoryStage == .recalling, roundPattern.indices.contains(inputIndex) else { return .ignored }
                guard roundPattern[inputIndex] == id else {
                    attempts += 1; inputIndex = 0; memoryStage = .ready
                    feedback = "A wonderfully silly remix! Let's replay this verse. Your finished verses are safe."
                    return .retry
                }
                inputIndex += 1
                if inputIndex == roundPattern.count {
                    round += 1; inputIndex = 0; memoryStage = .ready
                    if round == 3 { return win() }
                    feedback = "Perfect plopping! Verse \(round) learned. Ready for a longer one?"
                    return .roundWon
                }
                feedback = "Yes! \(inputIndex) of \(roundPattern.count) moves. Keep going!"
            } else {
                if selected.contains(id) { selected.remove(id) }
                else {
                    guard blueprint.kind != .recipe || selected.count < 3 else {
                        feedback = "Three ingredients fit in my bowl. Tap one to take it out first."
                        return .changed
                    }
                    selected.insert(id)
                }
            }
            return .changed
        case .submit:
            guard canSubmit else { return .ignored }
            attempts += 1
            if blueprint.kind == .recipe {
                let traits = selectedTraits
                if traits.contains(blueprint.forbiddenTrait) {
                    feedback = "Ooh! My ears folded. Something \(blueprint.forbiddenTrait) sneaked in. Swap that ingredient!"
                } else {
                    let missing = blueprint.requiredTraits.filter { !traits.contains($0) }
                    if missing.isEmpty { return win() }
                    let good = blueprint.requiredTraits.filter { traits.contains($0) }
                    feedback = (good.isEmpty ? "A brave first batch! " : "The \(good.joined(separator: " and ")) part is perfect! ") + "We still need something \(missing.joined(separator: " and "))."
                }
            } else {
                if warmth == blueprint.targetWarmth { return win() }
                let difference = abs(warmth - blueprint.targetWarmth)
                feedback = warmth > blueprint.targetWarmth
                    ? "Whoa, crispy whiskers! That's \(difference) too much warmth. Take out a treat or swap one."
                    : "Still a little chilly! We need \(difference) more warmth. Try a different combination."
            }
            return .retry
        case .hint:
            hints = min(3, hints + 1)
            if blueprint.kind == .memory {
                // Restart an in-flight demonstration when changing its timing.
                if memoryStage == .showing { memoryStage = .ready; playbackTime = 0 }
                feedback = "Let's do it together. Replays are slower now, and I'll name your next move."
            } else if hints >= 3 || attempts >= 3 {
                feedback = "Let's try " + blueprint.solution.compactMap { id in blueprint.options.first { $0.id == id }?.name }.joined(separator: " + ") + "."
            } else if blueprint.kind == .recipe {
                let missing = blueprint.requiredTraits.first { !selectedTraits.contains($0) } ?? blueprint.requiredTraits[0]
                let option = blueprint.options.first { $0.traits.contains(missing) && !$0.traits.contains(blueprint.forbiddenTrait) }!
                feedback = "\(option.name) brings the \(missing) part. Remember: nothing \(blueprint.forbiddenTrait)."
            } else {
                feedback = hints == 1 ? "Start with the 5-warmth treat. What is \(blueprint.targetWarmth) minus 5?" : "We need \(blueprint.targetWarmth - 5) more after the 5. You can tap a selected treat to remove it."
            }
            return .changed
        case .replay:
            guard blueprint.kind == .memory else { return .ignored }
            inputIndex = 0; playbackTime = 0; memoryStage = .showing
            feedback = "Watch verse \(round + 1). I'll light up each move; then it's your turn."
            return .changed
        }
    }

    /// Losing tracking or walking away restarts only the demonstration, never completed rounds.
    mutating func advancePlayback(delta: Double, available: Bool) {
        guard memoryStage == .showing, !solved else { return }
        guard available else {
            memoryStage = .ready; playbackTime = 0
            feedback = "Your verse is saved. Tap Watch again when you're ready."
            return
        }
        guard delta.isFinite, delta > 0 else { return }
        playbackTime += min(delta, 0.1)
        if playbackTime >= Double(roundPattern.count) * beatDuration {
            memoryStage = .recalling; inputIndex = 0
            feedback = "Your turn! Repeat the \(roundPattern.count) moves in order."
        }
    }
    private var selectedTraits: Set<String> {
        blueprint.options.filter { selected.contains($0.id) }.reduce(into: Set<String>()) { $0.formUnion($1.traits) }
    }
    private mutating func win() -> QuestOutcome {
        solved = true; feedback = blueprint.success
        return .won
    }
}
