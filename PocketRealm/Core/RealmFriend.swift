import Foundation

/// Original characters, authored in Blender; raw values are the bundled asset names.
enum RealmFriend: String, CaseIterable, Identifiable, Codable {
    case mosskip = "Mosskip", glimlo = "Glimlo", pebblin = "Pebblin"
    var id: String { rawValue }
    var name: String { rawValue }
    var role: String {
        switch self {
        case .mosskip: return "Sprout courier"
        case .glimlo: return "Lantern keeper"
        case .pebblin: return "Dream collector"
        }
    }
    var personality: String {
        switch self {
        case .mosskip: return "A pocket-sized gardener who delivers seeds and gets delightfully lost."
        case .glimlo: return "A bashful little moth who lights the way for friends afraid of the dark."
        case .pebblin: return "A sleepy pebble snail who keeps lovely dreams tucked inside a crystal shell."
        }
    }
    var questTitle: String {
        switch self {
        case .mosskip: return "A seed of friendship"
        case .glimlo: return "A little light, please"
        case .pebblin: return "The missing dream"
        }
    }
    var itemName: String {
        switch self {
        case .mosskip: return "dew seed"
        case .glimlo: return "lantern spark"
        case .pebblin: return "dream pearl"
        }
    }
    var questRequest: String {
        switch self {
        case .mosskip: return "My satchel has a teeny hole! Could you find my dew seed? It's going to grow into something wonderful."
        case .glimlo: return "Oh! My lantern lost its spark. Will you help me find it? Even little lights need a friend."
        case .pebblin: return "Yaaawn. One of my dreams rolled away. Could you bring back my dream pearl before it turns into a daydream?"
        }
    }
    var thanks: String {
        switch self {
        case .mosskip: return "You found it! I'll plant a whole garden for us. You're officially my best sprout!"
        case .glimlo: return "Look, we're glowing! I'll always save a little light for you."
        case .pebblin: return "There it is… the dream where we fly on a giant pancake. Next time, you're coming too."
        }
    }
    var reward: String {
        switch self {
        case .mosskip: return "Sprout Scout"
        case .glimlo: return "Little Light"
        case .pebblin: return "Dream Keeper"
        }
    }
    var symbol: String {
        switch self {
        case .mosskip: return "leaf.fill"
        case .glimlo: return "sun.max.fill"
        case .pebblin: return "moon.stars.fill"
        }
    }
    var chat: String {
        switch self {
        case .mosskip: return "Do you think this room needs a garden? I vote yes. I always vote yes."
        case .glimlo: return "I tried counting all the lights once. Fell asleep at three. Very cozy research."
        case .pebblin: return "I'm not slow. I'm taking the scenic route through this very excellent moment."
        }
    }
}

/// Uses only observed spawn points, including a one-location room without inventing geometry.
enum QuestLocation {
    static func choose(from candidates: [RoomCandidate], friendID: String) -> RoomCandidate? {
        guard let home = candidates.first(where: { $0.id == friendID }), home.position.count == 3 else { return nil }
        let others = candidates.filter { $0.id != friendID && $0.position.count == 3 }
        // Prefer the closest distinct landmark to avoid sending the player across the whole room.
        return others.min { distance($0, home) < distance($1, home) } ?? home
    }
    private static func distance(_ a: RoomCandidate, _ b: RoomCandidate) -> Float {
        let dx = a.position[0] - b.position[0], dz = a.position[2] - b.position[2]
        return dx * dx + dz * dz
    }
}
