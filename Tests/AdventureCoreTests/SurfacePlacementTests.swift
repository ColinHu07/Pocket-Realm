import XCTest
import simd
@testable import AdventureCore

final class SurfacePlacementTests: XCTestCase {
    private func object(center: SIMD3<Float>, yaw: Float = 0) -> simd_float4x4 {
        var result = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        result.columns.3 = SIMD4(center, 1)
        return result
    }

    private func floor(y: Float = -1) -> RoomSurfaceContext {
        RoomSurfaceContext(id: "floor", kind: .floor, dimensions: [6, 6, 0], position: [0, y, 0],
            corners: [[-3, y, -3], [3, y, -3], [3, y, 3], [-3, y, 3]], normal: [0, 1, 0])
    }

    func testTabletopPlacementIsInsideRotatedFootprintAndIndependentOfCameraHeight() throws {
        for yaw: Float in [0, .pi / 4, -.pi / 2] {
            let table = object(center: [0.5, -0.6, -0.8], yaw: yaw)
            for observer: SIMD3<Float> in [[2, 0.5, 2], [-2, 0.5, -2], [0.5, 0.5, -0.8]] {
                let transform = try XCTUnwrap(SurfacePlacement.transform(category: "table", dimensions: [1.2, 0.8, 0.8],
                    object: table, observer: observer, surfaces: [floor()]))
                let local = simd_inverse(table) * transform.columns.3
                XCTAssertEqual(local.y, 0.4, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(abs(local.x), 0.6 - SurfacePlacement.footprintRadius)
                XCTAssertLessThanOrEqual(abs(local.z), 0.4 - SurfacePlacement.footprintRadius)
                var crouched = observer; crouched.y -= 0.3
                let second = try XCTUnwrap(SurfacePlacement.transform(category: "table", dimensions: [1.2, 0.8, 0.8],
                    object: table, observer: crouched, surfaces: [floor()]))
                XCTAssertEqual(transform.columns.3, second.columns.3)
                XCTAssertEqual(transform.columns.1, SIMD4(0, 1, 0, 0))
            }
        }
    }

    func testChairsAndTallFurnitureUseMeasuredFloorInsteadOfBoundingBoxTop() throws {
        for category in ["chair", "sofa", "bed", "refrigerator", "storage"] {
            let transform = try XCTUnwrap(SurfacePlacement.transform(category: category, dimensions: [1, 1.8, 1],
                object: object(center: [0, -0.1, 0], yaw: .pi / 4), observer: [0, 0.6, 2], surfaces: [floor()]))
            XCTAssertEqual(transform.columns.3.y, -1, accuracy: 0.0001)
            XCTAssertGreaterThan(transform.columns.3.z, 0.7)
        }
    }

    func testLowCabinetUsesTopAndNarrowTableRequiresFloor() throws {
        let cabinet = try XCTUnwrap(SurfacePlacement.transform(category: "storage", dimensions: [1, 0.8, 0.8],
            object: object(center: [0, -0.6, 0]), observer: [0, 0.5, 2], surfaces: [floor()]))
        XCTAssertEqual(cabinet.columns.3.y, -0.2, accuracy: 0.0001)
        let narrow = SurfacePlacement.transform(category: "table", dimensions: [0.3, 0.8, 0.3],
            object: object(center: [0, -0.6, 0]), observer: [0, 0.5, 2], surfaces: [])
        XCTAssertNil(narrow)
    }

    func testUnsupportedFloorPointsAreRejectedRatherThanLeftFloating() {
        let furniture = object(center: [0, -0.6, 0])
        XCTAssertNil(SurfacePlacement.transform(category: "chair", dimensions: [1, 0.8, 1],
            object: furniture, observer: [0, 0.5, 2], surfaces: []))
        XCTAssertNil(SurfacePlacement.floorHeight(at: [3, -1, 0], surfaces: [floor()]))
        XCTAssertNil(SurfacePlacement.floorHeight(at: [0, 1, 0], surfaces: [floor()]))
        // The empty corner in an L-shaped room is not part of its supporting floor.
        let lShape = RoomSurfaceContext(id: "L", kind: .floor, dimensions: [3, 3, 0], position: [0, -1, 0],
            corners: [[0,-1,0], [3,-1,0], [3,-1,1], [1,-1,1], [1,-1,3], [0,-1,3]], normal: [0,1,0])
        XCTAssertNil(SurfacePlacement.floorHeight(at: [2, -1, 2], surfaces: [lShape]))
        XCTAssertEqual(SurfacePlacement.floorHeight(at: [0.5, -1, 2], surfaces: [lShape]), -1)
    }

    func testRefinementCannotSnapTableToFloorOrUnrelatedPlane() {
        let support = object(center: [0, -0.25, 0])
        let unrelated: [SIMD3<Float>] = [[0,-1,0], [0,0.5,0], [0.4,-0.25,0], [0,.nan,0]]
        XCTAssertEqual(SurfacePlacement.refined(support, hits: unrelated).columns.3, support.columns.3)
        let corrected = SurfacePlacement.refined(support, hits: unrelated + [[0,-0.21,0], [0,-0.32,0]])
        XCTAssertEqual(corrected.columns.3, SIMD4(0,-0.21,0,1))
        XCTAssertEqual(corrected.columns.2, support.columns.2)
        XCTAssertEqual(SurfacePlacement.refined(support, hits: [[0,-0.32,0]]).columns.3, support.columns.3)
    }

    func testShortUpperCabinetAboveFridgeUsesClearFloorInsteadOfCabinetTop() throws {
        // Regression: a 49cm tall cabinet was mistaken for low furniture even
        // though its top was 2.29m above the room floor.
        let fridge = object(center: [0, -0.1, 0])
        let obstruction = DecorationVolume(inverse: simd_inverse(fridge), half: [0.4, 0.9, 0.4])
        let result = try XCTUnwrap(SurfacePlacement.transform(category: "storage", dimensions: [0.9, 0.49, 0.8],
            object: object(center: [0, 1.05, 0]), observer: [0, 0.6, 2], surfaces: [floor()], obstacles: [obstruction]))
        XCTAssertEqual(result.columns.3.y, -1, accuracy: 0.001)
        XCTAssertGreaterThan(result.columns.3.z, 0.4 + SurfacePlacement.footprintRadius)
    }

    func testWholeBodyRejectsShelfAtHeadHeightAndFallsBackToFloor() throws {
        let shelf = DecorationVolume(inverse: simd_inverse(object(center: [0, 0.3, 0])), half: [0.6, 0.08, 0.45])
        let result = try XCTUnwrap(SurfacePlacement.transform(category: "table", dimensions: [1, 0.8, 0.8],
            object: object(center: [0,-0.6,0]), observer: [0,0.6,2], surfaces: [floor()], obstacles: [shelf]))
        XCTAssertEqual(result.columns.3.y, -1, accuracy: 0.001)
        XCTAssertFalse(SurfacePlacement.hasRoom(at: [0,-0.2,0], surfaces: [floor()], obstacles: [shelf]))
    }

    func testFloorSearchFindsDiagonalClearanceInFurnishedRoom() throws {
        let obstacle = DecorationVolume(inverse: simd_inverse(object(center: [0,-0.75,1.1])), half: [0.12,0.25,0.15])
        let result = try XCTUnwrap(SurfacePlacement.transform(category: "chair", dimensions: [1,0.8,1],
            object: object(center: [0,-0.6,0]), observer: [0,0.6,2], surfaces: [floor()], obstacles: [obstacle]))
        XCTAssertEqual(result.columns.3.y, -1, accuracy: 0.001)
        XCTAssertGreaterThan(abs(result.columns.3.x), 0.48)
        XCTAssertTrue(SurfacePlacement.hasRoom(at: SIMD3(result.columns.3.x, result.columns.3.y, result.columns.3.z),
            surfaces: [floor()], obstacles: [obstacle]))
    }

    func testRoundTableStaysAtCentreAndWidestFriendFits() throws {
        let table = object(center: [0,-0.6,0], yaw: .pi / 4)
        let result = try XCTUnwrap(SurfacePlacement.transform(category: "table", dimensions: [0.9,0.8,0.82],
            object: table, observer: [1,0.5,2], surfaces: [floor()]))
        let local = simd_inverse(table) * result.columns.3
        XCTAssertEqual(local.x, 0, accuracy: 0.001)
        XCTAssertEqual(local.z, 0, accuracy: 0.001)
        XCTAssertGreaterThan(SurfacePlacement.footprintRadius, 0.5514 / 2) // Glimlo's wing span
    }

    func testBodyCannotCrossWallOrCeiling() {
        let wall = RoomSurfaceContext(id: "wall", kind: .wall, dimensions: [4,2.5,0], position: [0,0.25,-1],
            corners: [[-2,-1,-1],[2,-1,-1],[2,1.5,-1],[-2,1.5,-1]], normal: [0,0,1])
        XCTAssertFalse(SurfacePlacement.hasRoom(at: [0,-1,-0.8], surfaces: [wall], obstacles: []))
        XCTAssertFalse(SurfacePlacement.hasRoom(at: [0,1,0], surfaces: [wall], obstacles: []))
        XCTAssertTrue(SurfacePlacement.hasRoom(at: [0,-1,0], surfaces: [wall], obstacles: []))
    }
}
