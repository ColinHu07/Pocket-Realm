import Foundation

/// Measured geometry only. Gemini selects IDs and treatments; it never supplies AR coordinates.
struct RoomSurfaceContext: Codable, Identifiable {
    enum Kind: String, Codable { case floor, wall, door, opening, window }
    let id: String
    let kind: Kind
    let dimensions: [Float]
    let position: [Float]
    let corners: [[Float]]
    let normal: [Float]
}

struct RoomObstacleContext: Codable {
    let category: String
    let dimensions: [Float]
    let position: [Float]
}

struct RoomScanContext: Codable {
    let surfaces: [RoomSurfaceContext]
    let obstacles: [RoomObstacleContext]
}

struct JunglePlan: Codable {
    enum Palette: String, Codable { case forest, tropical }
    enum Growth: String, Codable {
        case moss, meadow, ferns
        var spacing: Float { self == .moss ? 0.36 : 0.25 }
        var flowerChance: Float { self == .meadow ? 0.32 : (self == .ferns ? 0.04 : 0.07) }
        var fernChance: Float { self == .ferns ? 0.65 : 0.15 }
    }
    enum Vines: String, Codable {
        case none, light, lush
        var spacing: Float { self == .lush ? 0.7 : 1.4 }
        var length: Float { self == .lush ? 1.75 : 0.9 }
    }
    struct Floor: Codable { let surfaceID: String; let growth: Growth }
    struct Wall: Codable { let surfaceID: String; let vines: Vines }
    let palette: Palette
    let floors: [Floor]
    let walls: [Wall]

    func validate(surfaces: [RoomSurfaceContext]) throws {
        let floorIDs = surfaces.filter { $0.kind == .floor }.map(\.id)
        let wallIDs = surfaces.filter { $0.kind == .wall }.map(\.id)
        guard floors.count == floorIDs.count, walls.count == wallIDs.count,
              Set(floors.map(\.surfaceID)) == Set(floorIDs),
              Set(walls.map(\.surfaceID)) == Set(wallIDs) else { throw PlanError.invalidPlan }
    }
}

struct RoomUnderstanding: Codable {
    let summary: String
    let designNote: String
    let keepsakeObjectID: String
    let questReason: String
    let jungle: JunglePlan

    func validate(candidates: [RoomCandidate], surfaces: [RoomSurfaceContext], friendID: String) throws {
        for (text, limit) in [(summary, 400), (designNote, 280), (questReason, 240)] {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= limit else {
                throw PlanError.invalidPlan
            }
        }
        guard candidates.contains(where: { $0.id == keepsakeObjectID }),
              candidates.count == 1 || keepsakeObjectID != friendID else { throw PlanError.invalidPlan }
        try jungle.validate(surfaces: surfaces)
    }
}
