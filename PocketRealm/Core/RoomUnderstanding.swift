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
    enum Vines: String, Codable {
        case none, light, lush
    }
    struct Wall: Codable { let surfaceID: String; let vines: Vines }
    let palette: Palette
    let walls: [Wall]

    func validate(surfaces: [RoomSurfaceContext]) throws {
        let wallIDs = surfaces.filter { $0.kind == .wall }.map(\.id)
        guard walls.count == wallIDs.count,
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
