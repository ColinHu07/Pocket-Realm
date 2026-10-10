import Foundation
import simd

/// One local room snapshot. Camera JPEGs and credentials are deliberately absent.
struct SavedRoom: Codable {
    static let currentVersion = 1
    var version = Self.currentVersion
    let savedAt: Date
    let friend: RealmFriend
    let plan: EncounterPlan
    let candidates: [RoomCandidate]
    let transforms: [String: [Float]]
    let context: RoomScanContext
    let observer: [Float]
    let observations: [SavedWallObservation]
    let capturedRoom: Data
    let worldMap: Data
    let referenceAnchorID: UUID

    func validate() throws {
        guard version == Self.currentVersion else { throw SavedRoomError.unsupportedVersion }
        guard (1...24).contains(candidates.count), Set(candidates.map(\.id)).count == candidates.count,
              Set(transforms.keys) == Set(candidates.map(\.id)),
              observer.count == 3, observer.allSatisfy({ $0.isFinite }), observations.count <= 72,
              !capturedRoom.isEmpty, capturedRoom.count <= 8_000_000,
              !worldMap.isEmpty, worldMap.count <= 48_000_000,
              savedAt.timeIntervalSince1970.isFinite else { throw SavedRoomError.invalidData }
        for transform in transforms.values { _ = try Self.matrix(transform) }
        for observation in observations { _ = try observation.restore() }
        for candidate in candidates {
            guard candidate.position.count == 3, candidate.dimensions.count == 3,
                  candidate.position.allSatisfy({ $0.isFinite }),
                  candidate.dimensions.allSatisfy({ $0.isFinite && $0 > 0 }),
                  candidate.distance.isFinite else { throw SavedRoomError.invalidData }
        }
        try plan.validateRoom(against: candidates, surfaces: context.surfaces)
        try plan.challenge?.validate(for: friend)
    }

    /// Spatial decisions are reusable. Never give a new friend another friend's generated dialogue/puzzle.
    func encounter(for selected: RealmFriend) -> EncounterPlan {
        RoomPlanReplay(friend: friend, plan: plan, candidates: candidates).encounter(for: selected)
    }

    static func values(_ matrix: simd_float4x4) -> [Float] { (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } } }
    static func matrix(_ values: [Float]) throws -> simd_float4x4 {
        guard values.count == 16, values.allSatisfy({ $0.isFinite }),
              abs(values[3]) < 0.001, abs(values[7]) < 0.001, abs(values[11]) < 0.001,
              abs(values[15] - 1) < 0.001 else { throw SavedRoomError.invalidData }
        let columns = stride(from: 0, to: 16, by: 4).map { SIMD4<Float>(values[$0], values[$0 + 1], values[$0 + 2], values[$0 + 3]) }
        let result = simd_float4x4(columns)
        guard abs(simd_determinant(result)) > 0.001 else { throw SavedRoomError.invalidData }
        return result
    }
}

/// Immutable source plan for both in-session replay and saved-room restoration. No network dependency.
struct RoomPlanReplay {
    let friend: RealmFriend
    let plan: EncounterPlan
    let candidates: [RoomCandidate]

    func encounter(for selected: RealmFriend) -> EncounterPlan {
        guard selected != friend else { return plan }
        let category = candidates.first { $0.id == plan.objectID }?.category ?? "furniture"
        let place = category == "storage" ? "cabinet" : category
        return EncounterPlan(objectID: plan.objectID,
            hint: "A little rustle near the \(place)… \(selected.name) is waiting for you.",
            greeting: "You found me! I'm \(selected.name). It's lovely to meet you.", room: plan.room)
    }
}

struct SavedWallObservation: Codable {
    let cameraTransform: [Float]
    let intrinsics: [Float]
    let imageSize: [Float]
    let depth: [Float]
    let depthWidth: Int
    let depthHeight: Int

    init(_ view: WallObservation) {
        cameraTransform = SavedRoom.values(view.cameraTransform)
        intrinsics = (0..<3).flatMap { column in (0..<3).map { view.intrinsics[column][$0] } }
        imageSize = [view.imageSize.x, view.imageSize.y]
        depth = view.depth.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        depthWidth = view.depthWidth; depthHeight = view.depthHeight
    }
    func restore() throws -> WallObservation {
        guard intrinsics.count == 9, intrinsics.allSatisfy({ $0.isFinite }),
              intrinsics[0] > 0, intrinsics[4] > 0,
              imageSize.count == 2, imageSize.allSatisfy({ $0.isFinite && $0 > 0 }),
              (0...64).contains(depthWidth), (0...48).contains(depthHeight),
              depth.count == depthWidth * depthHeight, depth.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw SavedRoomError.invalidData }
        let columns = stride(from: 0, to: 9, by: 3).map { SIMD3<Float>(intrinsics[$0], intrinsics[$0 + 1], intrinsics[$0 + 2]) }
        return WallObservation(cameraTransform: try SavedRoom.matrix(cameraTransform), intrinsics: simd_float3x3(columns),
            imageSize: SIMD2(imageSize[0], imageSize[1]), depth: depth, depthWidth: depthWidth, depthHeight: depthHeight)
    }
}

enum SavedRoomError: LocalizedError {
    case unsupportedVersion, invalidData
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This saved room needs a fresh scan after the app update."
        case .invalidData: return "This saved room couldn't be read. Scan it again to make a new copy."
        }
    }
}

/// Atomic replacement keeps the previous good room if a new save fails.
struct SavedRoomStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("room.plist") }
    static var local: Self {
        .init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketRealmSavedRoom", isDirectory: true))
    }
    func load() throws -> SavedRoom? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 64_000_000 else { throw SavedRoomError.invalidData }
        let room = try PropertyListDecoder().decode(SavedRoom.self, from: Data(contentsOf: fileURL))
        try room.validate()
        return room
    }
    func save(_ room: SavedRoom) throws {
        try room.validate()
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(room)
        guard data.count <= 64_000_000 else { throw SavedRoomError.invalidData }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}

/// Never place saved geometry into a new coordinate frame before ARKit recognizes the map.
struct RoomRelocalizationGate {
    private var normalSince: Double?
    mutating func update(timestamp: Double, trackingNormal: Bool, referencePresent: Bool) -> Bool {
        guard timestamp.isFinite, trackingNormal, referencePresent else { normalSince = nil; return false }
        if normalSince == nil || timestamp < normalSince! { normalSince = timestamp }
        return timestamp - normalSince! >= 1
    }
}
