import Foundation
import simd
import XCTest
@testable import AdventureCore

final class SavedRoomTests: XCTestCase {
    private func snapshot(friend: RealmFriend = .nibbi) throws -> SavedRoom {
        struct Fixture: Decodable {
            struct Scan: Decodable { let candidates: [RoomCandidate]; let roomContext: RoomScanContext }
            let scan: Scan
            let plan: EncounterPlan
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/room-plan.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        var plan = fixture.plan
        plan.challenge = QuestBlueprint.first(for: friend).map { QuestPlan(blueprintID: $0.rawValue, introduction: "Let's make a cookie!") }
        var transform = matrix_identity_float4x4
        transform.columns.3 = [1, 2, 3, 1]
        let view = WallObservation(cameraTransform: transform, intrinsics: simd_float3x3(diagonal: [100, 100, 1]), imageSize: [640, 480])
        return SavedRoom(savedAt: Date(timeIntervalSince1970: 1_700_000_000), friend: friend, plan: plan,
            candidates: fixture.scan.candidates,
            transforms: Dictionary(uniqueKeysWithValues: fixture.scan.candidates.map { ($0.id, SavedRoom.values(transform)) }),
            context: fixture.scan.roomContext, observer: [1, 2, 3], observations: [SavedWallObservation(view)],
            // Opaque payload stubs: real ARKit/RoomPlan decoding is checked in the iOS restore path.
            capturedRoom: Data([1, 2, 3]), worldMap: Data([4, 5, 6]), referenceAnchorID: UUID())
    }

    func testRoomRoundTripPreservesPlanCoordinatesObservationsAndAnchor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedRoomStore(directory: directory)
        XCTAssertNil(try store.load())
        let original = try snapshot()
        try store.save(original)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.referenceAnchorID, original.referenceAnchorID)
        XCTAssertEqual(loaded.savedAt, original.savedAt)
        XCTAssertEqual(loaded.plan.challenge, original.plan.challenge)
        XCTAssertEqual(loaded.transforms, original.transforms)
        XCTAssertEqual(loaded.worldMap, original.worldMap)
        XCTAssertEqual(try loaded.observations[0].restore().cameraTransform, try original.observations[0].restore().cameraTransform)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try store.delete()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.delete())
    }

    func testFailedReplacementPreservesPreviousRoomAndCorruptDataIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedRoomStore(directory: directory)
        let original = try snapshot()
        try store.save(original)
        var invalid = try snapshot()
        invalid.version = 99
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load()?.referenceAnchorID, original.referenceAnchorID)
        try Data("broken file".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        try store.save(original)
        XCTAssertNotNil(try store.load())
    }

    func testAllFriendsReuseSpatialPlanWithoutBorrowingTheOriginalPuzzle() throws {
        let saved = try snapshot()
        for friend in RealmFriend.allCases {
            let encounter = saved.encounter(for: friend)
            try encounter.validateRoom(against: saved.candidates, surfaces: saved.context.surfaces)
            XCTAssertEqual(encounter.objectID, saved.plan.objectID)
            XCTAssertEqual(encounter.room?.keepsakeObjectID, saved.plan.room?.keepsakeObjectID)
            XCTAssertEqual(encounter.room?.summary, saved.plan.room?.summary)
            if friend == saved.friend { XCTAssertEqual(encounter.challenge, saved.plan.challenge) }
            else {
                XCTAssertNil(encounter.challenge)
                XCTAssertTrue(encounter.greeting.contains(friend.name))
                XCTAssertFalse(encounter.greeting.contains(saved.friend.name))
            }
        }
    }

    func testBadTransformsAndVersionsCannotRestore() throws {
        var saved = try snapshot()
        saved.version = 0
        XCTAssertThrowsError(try saved.validate())
        XCTAssertThrowsError(try SavedRoom.matrix([0, 1]))
        XCTAssertThrowsError(try SavedRoom.matrix(Array(repeating: 0, count: 16)))
        var values = SavedRoom.values(matrix_identity_float4x4)
        values[12] = .nan
        XCTAssertThrowsError(try SavedRoom.matrix(values))
        values = SavedRoom.values(matrix_identity_float4x4)
        values[3] = 1
        XCTAssertThrowsError(try SavedRoom.matrix(values))
    }


    func testDepthSerializationPreservesOcclusionAndSanitizesMissingValues() throws {
        let view = WallObservation(cameraTransform: matrix_identity_float4x4,
            intrinsics: simd_float3x3(diagonal: [100, 100, 1]), imageSize: [640, 480],
            depth: [1.5, .nan, .infinity, -1], depthWidth: 2, depthHeight: 2)
        let saved = SavedWallObservation(view)
        let data = try PropertyListEncoder().encode(saved)
        let loaded = try PropertyListDecoder().decode(SavedWallObservation.self, from: data).restore()
        XCTAssertEqual(loaded.depth, [1.5, 0, 0, 0])
        XCTAssertEqual(loaded.intrinsics, view.intrinsics)
    }

    func testRelocalizationNeedsBothTheSavedAnchorAndContinuousNormalTracking() {
        var gate = RoomRelocalizationGate()
        XCTAssertFalse(gate.update(timestamp: 1, trackingNormal: true, referencePresent: false))
        XCTAssertFalse(gate.update(timestamp: 10, trackingNormal: false, referencePresent: true))
        XCTAssertFalse(gate.update(timestamp: 11, trackingNormal: true, referencePresent: true))
        XCTAssertFalse(gate.update(timestamp: 11.9, trackingNormal: true, referencePresent: true))
        XCTAssertFalse(gate.update(timestamp: 12, trackingNormal: false, referencePresent: true))
        XCTAssertFalse(gate.update(timestamp: 13, trackingNormal: true, referencePresent: true))
        XCTAssertTrue(gate.update(timestamp: 14, trackingNormal: true, referencePresent: true))
        XCTAssertFalse(gate.update(timestamp: .nan, trackingNormal: true, referencePresent: true))
    }

    func testRestoringCannotSkipToDiscoveryAndKeepsPuzzleRequirements() {
        var adventure = Adventure()
        adventure.beginRestoring()
        adventure.acceptPlan()
        adventure.beginExploring()
        XCTAssertEqual(adventure.phase, .restoring)
        XCTAssertFalse(adventure.reveal(trackingReady: true, proximitySatisfied: true))
        XCTAssertFalse(adventure.restorePlan(aligned: false))
        XCTAssertTrue(adventure.restorePlan(aligned: true, challenge: QuestGame(blueprint: .nibbiMint)))
        XCTAssertEqual(adventure.phase, .ready)
        XCTAssertEqual(adventure.challenge?.blueprint, .nibbiMint)
        XCTAssertFalse(adventure.restorePlan(aligned: true))
        adventure.beginExploring()
        XCTAssertTrue(adventure.reveal(trackingReady: true, proximitySatisfied: true))
    }
}
