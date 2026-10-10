import Foundation
import simd

/// A support point, with Y up and +Z facing the observer. Heights come from room
/// geometry, never from the camera's height or a point floating beside furniture.
enum SurfacePlacement {
    static let footprintRadius: Float = 0.24
    static let refinementLimit: Float = 0.12

    static func transform(category: String, dimensions: SIMD3<Float>, object: simd_float4x4,
                          observer: SIMD3<Float>, surfaces: [RoomSurfaceContext]) -> simd_float4x4? {
        guard [dimensions.x, dimensions.y, dimensions.z].allSatisfy({ $0.isFinite && $0 > 0 }),
              [observer.x, observer.y, observer.z].allSatisfy(\.isFinite),
              (0..<4).allSatisfy({ column in (0..<4).allSatisfy { object[column][$0].isFinite } }),
              abs(simd_determinant(object)) > 0.001,
              object.columns.1.y > 0.98 else { return nil }
        let half = dimensions / 2
        let localObserver = simd_inverse(object) * SIMD4(observer, 1)
        var direction = SIMD3<Float>(localObserver.x, 0, localObserver.z)
        if simd_length(direction) < 0.01 { direction = [0, 0, 1] }
        direction = simd_normalize(direction)
        let topIsUsable = (category == "table" || category == "storage")
            && dimensions.y <= 1.3 && min(half.x, half.z) >= footprintRadius + 0.03
        var local: SIMD3<Float>
        if topIsUsable {
            // Inset the entire support footprint, including at rotated/diagonal edges.
            let usable = SIMD2(half.x, half.z) - SIMD2(repeating: footprintRadius + 0.03)
            let travel = min(usable.x / max(abs(direction.x), 0.0001),
                             usable.y / max(abs(direction.z), 0.0001))
            local = direction * travel
            local.y = half.y
        } else {
            // A chair/sofa/bed bounding-box top may be its back or headboard.
            // Use the measured floor beside it instead of inventing a seat height.
            let tx = half.x / max(abs(direction.x), 0.0001)
            let tz = half.z / max(abs(direction.z), 0.0001)
            local = direction * min(tx, tz)
            let normal: SIMD3<Float> = tx < tz ? [direction.x >= 0 ? 1 : -1, 0, 0]
                : [0, 0, direction.z >= 0 ? 1 : -1]
            local += normal * (footprintRadius + 0.08)
            local.y = -half.y
        }
        let world = object * SIMD4(local, 1)
        var point = SIMD3(world.x, world.y, world.z)
        if !topIsUsable {
            guard let floor = floorHeight(at: point, surfaces: surfaces) else { return nil }
            point.y = floor
        }
        var facing = observer - point
        facing.y = 0
        if simd_length(facing) < 0.01 { facing = [0, 0, 1] }
        facing = simd_normalize(facing)
        var result = matrix_identity_float4x4
        result.columns.0 = SIMD4(simd_cross([0, 1, 0], facing), 0)
        result.columns.2 = SIMD4(facing, 0)
        result.columns.3 = SIMD4(point, 1)
        return result
    }

    static func floorHeight(at point: SIMD3<Float>, surfaces: [RoomSurfaceContext]) -> Float? {
        surfaces.filter { $0.kind == .floor }.compactMap { surface -> Float? in
            guard surface.corners.count >= 3,
                  surface.corners.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { return nil }
            let polygon = ThemePolygon(surface.corners.map { SIMD2($0[0], $0[2]) })
            guard polygon.contains(SIMD2(point.x, point.z), inset: footprintRadius),
                  let low = surface.corners.map({ $0[1] }).min(),
                  let high = surface.corners.map({ $0[1] }).max(), high - low < 0.08,
                  abs((low + high) / 2 - point.y) < 0.35 else { return nil }
            return (low + high) / 2
        }.min(by: { abs($0 - point.y) < abs($1 - point.y) })
    }

    /// Refine only the intended support. A floor below a table, a wall, or an
    /// unrelated elevated surface must never pull the character away from it.
    static func refined(_ transform: simd_float4x4, hits: [SIMD3<Float>]) -> simd_float4x4 {
        let expected = transform.columns.3
        let valid = hits.filter {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                && simd_length(SIMD2($0.x - expected.x, $0.z - expected.z)) <= 0.02
                && abs($0.y - expected.y) <= refinementLimit
        }
        guard let closest = valid.min(by: { abs($0.y - expected.y) < abs($1.y - expected.y) }) else { return transform }
        var result = transform
        result.columns.3.y = closest.y
        return result
    }
}
