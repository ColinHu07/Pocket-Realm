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
                    object: table, observer: observer, surfaces: []))
                let local = simd_inverse(table) * transform.columns.3
                XCTAssertEqual(local.y, 0.4, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(abs(local.x), 0.6 - SurfacePlacement.footprintRadius)
                XCTAssertLessThanOrEqual(abs(local.z), 0.4 - SurfacePlacement.footprintRadius)
                var crouched = observer; crouched.y -= 0.9
                let second = try XCTUnwrap(SurfacePlacement.transform(category: "table", dimensions: [1.2, 0.8, 0.8],
                    object: table, observer: crouched, surfaces: []))
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
        let cabinet = try XCTUnwrap(SurfacePlacement.transform(category: "storage", dimensions: [1, 0.8, 0.7],
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
    }
}
