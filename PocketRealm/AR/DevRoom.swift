import ARKit
import Foundation
import RoomPlan

/// Dev-only shortcut: keep the last scanned room and its Gemini plan so testers in the same room
/// can skip the scan and the Gemini call. ARKit relocalizes against the saved world map, so
/// saved furniture positions line up with the room again.
struct DevRoom: Codable {
    let plan: EncounterPlan
    let candidates: [RoomCandidate]
    let spawnTransforms: [String: [Float]]
    let context: RoomScanContext
    let room: CapturedRoom
    let observer: SIMD3<Float>
    let friend: String
    let saved: Date

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevRoom", isDirectory: true)
    }
    private static var snapshotURL: URL { folder.appendingPathComponent("room.json") }
    private static var worldMapURL: URL { folder.appendingPathComponent("world.map") }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: snapshotURL.path) && FileManager.default.fileExists(atPath: worldMapURL.path)
    }

    static var savedDate: Date? { (try? JSONDecoder().decode(DevRoom.self, from: Data(contentsOf: snapshotURL)))?.saved }

    static func save(_ room: DevRoom, worldMap: ARWorldMap) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let map = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        try map.write(to: worldMapURL, options: .atomic)
        try JSONEncoder().encode(room).write(to: snapshotURL, options: .atomic)
    }

    static func load() throws -> (room: DevRoom, worldMap: ARWorldMap) {
        let room = try JSONDecoder().decode(DevRoom.self, from: Data(contentsOf: snapshotURL))
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: Data(contentsOf: worldMapURL)) else {
            throw PlanError.server("The saved room map is unreadable. Do a normal scan to save a new one.")
        }
        return (room, map)
    }

    static func encode(_ transforms: [String: simd_float4x4]) -> [String: [Float]] {
        transforms.mapValues { m in [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] } }
    }

    static func decode(_ transforms: [String: [Float]]) -> [String: simd_float4x4] {
        transforms.compactMapValues { v in
            guard v.count == 16 else { return nil }
            return simd_float4x4(SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
                                 SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15]))
        }
    }
}
