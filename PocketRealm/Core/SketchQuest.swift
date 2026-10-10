import Foundation

/// Why a drawing is being made; the server passes this to Codex as game context.
enum DrawingPurpose: String, Codable {
    case sidekick, challenge
}

/// How Codex decided a drawing behaves in the game.
struct DrawingCard: Codable, Equatable {
    enum Kind: String, Codable { case tool, character, object }
    enum Voice: String, Codable { case high, low, normal }

    let name: String
    let kind: Kind
    var title: String = ""
    var verb: String = "use"
    var uses: Int = 2
    var arrival: String = ""
    var success: String = ""
    var lines: [String] = []
    var voice: Voice = .normal

    /// What to call it on screen: a character's own name, otherwise "your <thing>".
    var displayName: String { kind == .character && !title.isEmpty ? title : "your \(name)" }
    var verbButton: String { verb.prefix(1).uppercased() + verb.dropFirst() + "!" }
    var clampedUses: Int { min(5, max(1, uses)) }

    enum CodingKeys: String, CodingKey { case name, kind, title, verb, uses, arrival, success, lines, voice }

    init(name: String, kind: Kind, title: String = "", verb: String = "use", uses: Int = 2,
         arrival: String = "", success: String = "", lines: [String] = [], voice: Voice = .normal) {
        (self.name, self.kind, self.title, self.verb, self.uses) = (name, kind, title, verb, uses)
        (self.arrival, self.success, self.lines, self.voice) = (arrival, success, lines, voice)
    }

    /// Missing or unknown fields fall back to safe defaults instead of failing the whole drawing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "drawing"
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .object
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        verb = (try? c.decode(String.self, forKey: .verb)).flatMap { $0.isEmpty ? nil : $0 } ?? "use"
        uses = (try? c.decode(Int.self, forKey: .uses)) ?? 2
        arrival = (try? c.decode(String.self, forKey: .arrival)) ?? ""
        success = (try? c.decode(String.self, forKey: .success)) ?? ""
        lines = (try? c.decode([String].self, forKey: .lines)) ?? []
        voice = (try? c.decode(Voice.self, forKey: .voice)) ?? .normal
    }
}

/// A predicament between the player and their friend's lost item; solved by drawing something.
struct Challenge: Equatable {
    enum Trap: String, CaseIterable, Codable {
        case moonIce, grumbleCloud, thornKnot, snoringBoulder, wobbleBubble, shadowPuddle
    }

    let trap: Trap
    let item: String
    let place: String

    static func pick(seed: Int, item: String, place: String) -> Challenge {
        let traps = Trap.allCases
        return Challenge(trap: traps[((seed % traps.count) + traps.count) % traps.count], item: item, place: place)
    }

    var title: String {
        switch trap {
        case .moonIce: return "Break the ice"
        case .grumbleCloud: return "Clear the storm cloud"
        case .thornKnot: return "Untangle the vines"
        case .snoringBoulder: return "Move the boulder"
        case .wobbleBubble: return "Bring down the bubble"
        case .shadowPuddle: return "Clear the shadow puddle"
        }
    }

    /// The open-ended drawing hint. Anything reasonable a player draws should be able to help.
    var prompt: String {
        switch trap {
        case .moonIce:
            return "The \(item) is trapped in sparkling ice near the \(place). Draw something warm to melt the ice, or a tool to crack it."
        case .grumbleCloud:
            return "A storm cloud is blocking the \(item) near the \(place). Draw something to blow the cloud away, like a fan or a windy creature."
        case .thornKnot:
            return "Vines are wrapped around the \(item) near the \(place). Draw a tool or a helper that could cut or untangle the vines."
        case .snoringBoulder:
            return "A boulder is covering the \(item) near the \(place). Draw a strong helper or a tool that could lift or push the boulder aside."
        case .wobbleBubble:
            return "The \(item) is floating in a bubble near the \(place). Draw something to pop the bubble, or a flying helper to bring it down."
        case .shadowPuddle:
            return "The \(item) is hidden in a magical shadow puddle near the \(place). Draw a light to clear the shadow, or a tool to lift the item out."
        }
    }

    /// What the friend says when they explain the problem.
    var plea: String {
        switch trap {
        case .moonIce: return "My \(item) is trapped in ice near the \(place)! Can you draw something to melt or break the ice?"
        case .grumbleCloud: return "A storm cloud is blocking my \(item) near the \(place)! Can you draw something to blow the cloud away?"
        case .thornKnot: return "Vines are tangled around my \(item) near the \(place)! Can you draw something to untangle them?"
        case .snoringBoulder: return "My \(item) is under a boulder near the \(place)! Can you draw something to move the boulder?"
        case .wobbleBubble: return "My \(item) is floating in a bubble near the \(place)! Can you draw something to bring it down?"
        case .shadowPuddle: return "My \(item) is hidden in a magical shadow puddle near the \(place)! Can you draw a light or something to lift it out?"
        }
    }

    var cleared: String {
        switch trap {
        case .moonIce: return "The ice is gone! Pick up the \(item)."
        case .grumbleCloud: return "The cloud has cleared! Pick up the \(item)."
        case .thornKnot: return "The vines are cleared away! Pick up the \(item)."
        case .snoringBoulder: return "The boulder is out of the way! Pick up the \(item)."
        case .wobbleBubble: return "Pop! The \(item) is free. Pick it up!"
        case .shadowPuddle: return "The shadow is gone! Pick up the \(item)."
        }
    }

    /// The full context Codex sees alongside the drawing.
    var codexContext: String {
        "Challenge: \(title). \(prompt) The player's drawing is their solution. Explain simply how it clears this obstacle and frees the item. Keep the explanation playful but concrete; do not invent another obstacle or extra tasks."
    }
}

/// Counts the uses a helper needs to clear a trap.
struct TrapProgress: Equatable {
    let needed: Int
    private(set) var done = 0
    init(needed: Int) { self.needed = min(5, max(1, needed)) }
    var remaining: Int { needed - done }
    var cleared: Bool { done >= needed }
    var fraction: Float { Float(done) / Float(needed) }
    @discardableResult mutating func use() -> Bool {
        guard !cleared else { return false }
        done += 1
        return true
    }
}

/// Things happening in the drawing workshop while Codex and Blender build a drawing.
enum Workshop {
    static func whimsy(_ index: Int, friend: String) -> String {
        let lines = [
            "The gnomes are sanding the edges…",
            "A tiny wizard is mixing your colors…",
            "Reading your drawing very, very carefully…",
            "The workshop cat is supervising. Strictly.",
            "\(friend) is pressing their face against the workshop window…",
            "Three moths are test-flying it around the rafters…",
            "Somebody dropped it. It's fine. It bounced.",
            "The gnomes are arguing about the color. Your drawing wins.",
            "Bolting on the extra-good parts…",
            "Waiting for the glue to agree with itself…",
            "Polishing every last sparkle…",
            "Wrapping it in tissue paper for the trip to your room…",
        ]
        return lines[((index % lines.count) + lines.count) % lines.count]
    }

    static func arrival(_ card: DrawingCard) -> String {
        if !card.arrival.isEmpty { return card.arrival }
        switch card.kind {
        case .character: return "Here comes \(card.displayName)!"
        case .tool: return "\(card.displayName.prefix(1).uppercased() + card.displayName.dropFirst()) is ready in your hand!"
        case .object: return "\(card.displayName.prefix(1).uppercased() + card.displayName.dropFirst()) just landed!"
        }
    }
}
