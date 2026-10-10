import XCTest
@testable import AdventureCore

final class ThemeTests: XCTestCase {
    private let lShape: [SIMD2<Float>] = [[0, 0], [4, 0], [4, 1], [1, 1], [1, 4], [0, 4]]

    func testConcaveFloorTriangulationPreservesAreaAndMissingCorner() {
        for points in [lShape, Array(lShape.reversed()), lShape + [lShape[0]]] {
            let polygon = ThemePolygon(points)
            XCTAssertEqual(polygon.area, 7, accuracy: 0.0001)
            let triangles = polygon.triangles()
            XCTAssertEqual(triangles.count, 4)
            var area: Float = 0
            for triangle in triangles {
                let a = polygon.vertices[triangle.x], b = polygon.vertices[triangle.y], c = polygon.vertices[triangle.z]
                area += abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
                XCTAssertTrue(polygon.contains((a + b + c) / 3))
            }
            XCTAssertEqual(area, polygon.area, accuracy: 0.0001)
            XCTAssertFalse(polygon.contains([2, 2]))
        }
    }

    func testScatterStaysInsideConcaveFloorAndAwayFromWalls() {
        let polygon = ThemePolygon(lShape)
        let points = polygon.scatter(seed: 1234)
        XCTAssertGreaterThan(points.count, 20)
        for point in points {
            XCTAssertTrue(polygon.contains(point, inset: 0.15))
            XCTAssertFalse(point.x > 1 && point.y > 1)
        }
        XCTAssertFalse(polygon.contains([0.05, 2], inset: 0.15))
    }

    func testSameScanAlwaysGetsSameBoundedLayout() {
        let polygon = ThemePolygon([[0, 0], [40, 0], [40, 40], [0, 40]])
        let seed = ThemeRandom.seed("scanned-floor-id")
        let first = polygon.scatter(seed: seed, limit: 120)
        XCTAssertFalse(first.isEmpty)
        XCTAssertLessThanOrEqual(first.count, 120)
        XCTAssertEqual(first, polygon.scatter(seed: seed, limit: 120))
        XCTAssertNotEqual(first, polygon.scatter(seed: seed + 1, limit: 120))
        XCTAssertTrue(first.contains(where: { $0.x > 30 && $0.y > 30 }))
    }

    func testIncompleteOrDegenerateFloorsDoNotInventGeometry() {
        for points: [SIMD2<Float>] in [[], [[0, 0]], [[0, 0], [1, 1]], [[0, 0], [1, 1], [2, 2]], [[.nan, 0], [0, 0]]] {
            let polygon = ThemePolygon(points)
            XCTAssertTrue(polygon.triangles().isEmpty)
            XCTAssertTrue(polygon.scatter(seed: 0).isEmpty)
        }
        let floor = ThemePolygon(lShape)
        XCTAssertTrue(floor.scatter(seed: 0, limit: 0).isEmpty)
        XCTAssertTrue(floor.scatter(seed: 0, spacing: 0).isEmpty)
    }

    func testDuplicateAndCollinearCornersStillProduceFloor() {
        let polygon = ThemePolygon([[0, 0], [1, 0], [1, 0], [2, 0], [2, 2], [0, 2]])
        let triangles = polygon.triangles()
        XCTAssertFalse(triangles.isEmpty)
        let area = triangles.reduce(Float(0)) { sum, t in
            let a = polygon.vertices[t.x], b = polygon.vertices[t.y], c = polygon.vertices[t.z]
            return sum + abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        }
        XCTAssertEqual(area, 4, accuracy: 0.0001)
    }
}
