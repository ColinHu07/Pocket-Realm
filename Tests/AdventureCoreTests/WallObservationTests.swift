import XCTest
import simd
@testable import AdventureCore

final class WallObservationTests: XCTestCase {
    private func view() -> WallObservation {
        WallObservation(cameraTransform: matrix_identity_float4x4,
            intrinsics: simd_float3x3(columns: ([400, 0, 0], [0, 400, 0], [320, 240, 1])), imageSize: [640, 480])
    }

    func testObservedWallRequiresRealCameraFrustumAndPose() {
        var camera = view()
        XCTAssertTrue(camera.sees([0, 0, -2]))
        for point: SIMD3<Float> in [[0, 0, 2], [2, 0, -2], [0, 2, -2], [0, 0, -8], [.nan, 0, -2]] {
            XCTAssertFalse(camera.sees(point))
        }
        camera = WallObservation(cameraTransform: simd_float4x4(simd_quatf(angle: .pi, axis: [0, 1, 0])),
            intrinsics: camera.intrinsics, imageSize: camera.imageSize)
        XCTAssertTrue(camera.sees([0, 0, 2]))
        XCTAssertFalse(camera.sees([0, 0, -2]))
    }

    func testDepthRejectsOccludedUnmeasuredAndUnsupportedSurfaces() {
        var camera = view()
        camera.depthWidth = 2; camera.depthHeight = 2
        camera.depth = [2, 2, 2, 2]
        XCTAssertTrue(camera.sees([0, 0, -2]))
        XCTAssertFalse(camera.sees([0, 0, -3])) // a cabinet hides the wall
        XCTAssertFalse(camera.sees([0, 0, -1])) // inferred plane in front of actual surface
        for depth: Float in [0, .nan, .infinity] {
            camera.depth = Array(repeating: depth, count: 4)
            XCTAssertFalse(camera.sees([0, 0, -2]))
        }
        camera.depth = [2]
        XCTAssertFalse(camera.sees([0, 0, -2]))
    }

    func testRotatedFurnitureBlocksSightlineEvenWithoutDepth() {
        var transform = simd_float4x4(simd_quatf(angle: .pi / 4, axis: [0, 1, 0]))
        transform.columns.3 = [0, 0, -1, 1]
        let cabinet = DecorationVolume(inverse: simd_inverse(transform), half: [0.4, 0.6, 0.3])
        XCTAssertFalse(WallVisibility.observed([0, 0, -2], in: [view()], blockers: [cabinet]))
        XCTAssertTrue(WallVisibility.observed([1, 0, -2], in: [view()], blockers: [cabinet]))
        XCTAssertFalse(WallVisibility.observed([0, 0, -2], in: [], blockers: []))
        transform.columns.3 = [0, 0, -3, 1]
        let behind = DecorationVolume(inverse: simd_inverse(transform), half: [0.4, 0.6, 0.3])
        XCTAssertTrue(WallVisibility.observed([0, 0, -2], in: [view()], blockers: [behind]))
    }

    func testWholeFoliageFootprintMustFitObservedWallAndAvoidOpening() {
        let wall = ThemePolygon([[-1, -1], [1, -1], [1, 1], [-1, 1]])
        XCTAssertTrue(WallVisibility.footprint(minimum: [-0.3, -0.6], maximum: [0.3, 0.3], polygon: wall) { _ in true })
        XCTAssertFalse(WallVisibility.footprint(minimum: [-0.3, -0.6], maximum: [1.1, 0.3], polygon: wall) { _ in true })
        // Both outer corners and the attachment can fit while a window crosses the leaf footprint.
        XCTAssertFalse(WallVisibility.footprint(minimum: [-0.3, -0.6], maximum: [0.3, 0.3], polygon: wall) {
            !(abs($0.x) < 0.12 && abs($0.y + 0.2) < 0.12)
        })
    }
}
