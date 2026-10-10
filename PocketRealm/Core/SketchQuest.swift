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
        case .moonIce: return "Frozen in moon-ice"
        case .grumbleCloud: return "A very grumpy cloud"
        case .thornKnot: return "Tangled in thornvines"
        case .snoringBoulder: return "A boulder took a nap"
        case .wobbleBubble: return "Bubbled away"
        case .shadowPuddle: return "Sunk in a shadow puddle"
        }
    }

    /// The open-ended drawing hint. Anything reasonable a player draws should be able to help.
    var prompt: String {
        switch trap {
        case .moonIce:
            return "The \(item) is frozen inside a block of glittering moon-ice by the \(place). Draw something that could thaw it, crack it, or politely ask the ice to let go."
        case .grumbleCloud:
            return "A grumpy little storm cloud is sulking on top of the \(item) and won't budge. Draw someone who could cheer it up, or something that could blow it far away."
        case .thornKnot:
            return "Sleepy thornvines have curled around the \(item) by the \(place). Draw something that could snip them, untangle them, or tickle them awake."
        case .snoringBoulder:
            return "A boulder fell asleep right on top of the \(item), and it's snoring. Draw something loud, strong, or very persuasive enough to move it."
        case .wobbleBubble:
            return "The \(item) floated up inside a giant wobbly bubble. Draw something that could pop it, catch it, or fly up to fetch it."
        case .shadowPuddle:
            return "The \(item) sank into a swirly puddle of shadow by the \(place). Draw something that makes light, or something that could fish it out."
        }
    }

    /// What the friend says when they explain the problem.
    var plea: String {
        switch trap {
        case .moonIce: return "My \(item) got frozen solid in moon-ice! Can you draw something to get it out?"
        case .grumbleCloud: return "A grumbly cloud is sitting on my \(item) and it won't move! Maybe you could draw something to help?"
        case .thornKnot: return "Thornvines grabbed my \(item)! Could you draw something to free it?"
        case .snoringBoulder: return "A big sleepy boulder is snoozing on my \(item)! Can you draw something to move it?"
        case .wobbleBubble: return "My \(item) floated off in a bubble! Can you draw something to bring it down?"
        case .shadowPuddle: return "My \(item) sank into a shadow puddle! Could you draw something to get it back?"
        }
    }

    var cleared: String {
        switch trap {
        case .moonIce: return "The moon-ice cracks into a hundred sparkles!"
        case .grumbleCloud: return "The cloud giggles, sprinkles a tiny rainbow, and drifts away!"
        case .thornKnot: return "The thornvines yawn, stretch, and let go!"
        case .snoringBoulder: return "The boulder wakes up, says sorry, and rolls aside!"
        case .wobbleBubble: return "Pop! The bubble bursts into glitter!"
        case .shadowPuddle: return "Light floods the puddle and it shrinks away to nothing!"
        }
    }

    /// The full context Codex sees alongside the drawing.
    var codexContext: String {
        "Challenge: \(title). \(prompt) The player's drawing is their solution. Decide how it helps."
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
