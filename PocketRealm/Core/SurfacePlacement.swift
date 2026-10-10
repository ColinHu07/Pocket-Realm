import Foundation
import simd

/// A support point, with Y up and +Z facing the observer. Validate the whole
/// animated roster against measured room geometry, including on saved-room replay.
enum SurfacePlacement {
    // Includes Glimlo's animated wings while turning toward any camera heading.
    static let footprintRadius: Float = 0.36
    static let bodyHeight: Float = 0.70
    static let supportClearance: Float = 0.02
    static let refinementLimit: Float = 0.12

    static func transform(category: String, dimensions: SIMD3<Float>, object: simd_float4x4,
                          observer: SIMD3<Float>, surfaces: [RoomSurfaceContext],
                          obstacles: [DecorationVolume] = []) -> simd_float4x4? {
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
        func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
            let p = object * SIMD4(local, 1); return SIMD3(p.x, p.y, p.z)
        }
        let furniture = obstacles + [DecorationVolume(inverse: simd_inverse(object), half: half)]
        var points: [SIMD3<Float>] = []
        let bottom = world([0, -half.y, 0])
        let top = world([0, half.y, 0])
        // Object height alone mistakes short wall-mounted cabinets for low furniture.
        // Require a measured floor under the object and an accessible top above it.
        if (category == "table" || category == "storage"),
           min(half.x, half.z) >= footprintRadius + 0.03,
           let floor = floorHeight(at: bottom, surfaces: surfaces),
           top.y - floor <= 1.15, top.y - floor >= 0.25 {
            // The centre also supports round/elliptical tables; a rectangle's inset
            // corners do not necessarily lie on their actual tabletop.
            points.append(top)
        }
        // A bounding-box top can be a chair back, headboard, or upper cabinet.
        // Search the observed side for clear floor, including below mounted storage.
        for extra: Float in [0, 0.10, 0.20, 0.30, 0.40, 0.60] {
            for angle: Float in [0, .pi / 12, -.pi / 12, .pi / 6, -.pi / 6, .pi / 4, -.pi / 4] {
                let d = simd_act(simd_quatf(angle: angle, axis: [0, 1, 0]), direction)
                let tx = half.x / max(abs(d.x), 0.0001), tz = half.z / max(abs(d.z), 0.0001)
                var local = d * min(tx, tz)
                let normal: SIMD3<Float> = tx < tz ? [d.x >= 0 ? 1 : -1, 0, 0] : [0, 0, d.z >= 0 ? 1 : -1]
                local += normal * (footprintRadius + 0.10 + extra)
                local.y = -half.y
                var point = world(local)
                guard let floor = floorHeight(at: point, surfaces: surfaces, maximumDrop: 3) else { continue }
                point.y = floor
                points.append(point)
            }
        }
        guard let point = points.first(where: { point in
            hasRoom(at: point, surfaces: surfaces, obstacles: furniture)
                && !furniture.contains { $0.blocks(from: observer, to: point + SIMD3(0, bodyHeight / 2, 0)) }
        }) else { return nil }
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

    static func hasRoom(at point: SIMD3<Float>, surfaces: [RoomSurfaceContext], obstacles: [DecorationVolume]) -> Bool {
        let low = point + SIMD3(-footprintRadius, supportClearance, -footprintRadius)
        let high = point + SIMD3(footprintRadius, bodyHeight, footprintRadius)
        guard !obstacles.contains(where: { $0.intersects(minimum: low, maximum: high) }) else { return false }
        for wall in surfaces where wall.kind == .wall && wall.normal.count == 3 && wall.position.count == 3 {
            let normal = SIMD3(wall.normal[0], wall.normal[1], wall.normal[2])
            let center = SIMD3(wall.position[0], wall.position[1], wall.position[2])
            guard simd_length(normal) > 0.9, abs(normal.y) < 0.1 else { continue }
            let distance = abs(simd_dot(point - center, normal))
            // Test only the actual wall segment, not its infinite extension.
            let along = simd_cross([0, 1, 0], normal)
            let projected = wall.corners.filter { $0.count == 3 }.map { simd_dot(SIMD3($0[0], $0[1], $0[2]) - center, along) }
            if let min = projected.min(), let max = projected.max(),
               distance < footprintRadius + 0.04 {
                let x = simd_dot(point - center, along)
                if x > min - footprintRadius && x < max + footprintRadius { return false }
            }
        }
        // RoomPlan walls give a conservative ceiling bound even without a ceiling mesh.
        let ceiling = surfaces.filter { $0.kind == .wall }.flatMap(\.corners)
            .filter { $0.count == 3 }.map { $0[1] }.max()
        return ceiling.map { high.y + 0.05 < $0 } ?? true
    }

    static func floorHeight(at point: SIMD3<Float>, surfaces: [RoomSurfaceContext], maximumDrop: Float = 0.35) -> Float? {
        surfaces.filter { $0.kind == .floor }.compactMap { surface -> Float? in
            guard surface.corners.count >= 3,
                  surface.corners.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { return nil }
            let polygon = ThemePolygon(surface.corners.map { SIMD2($0[0], $0[2]) })
            guard polygon.contains(SIMD2(point.x, point.z), inset: footprintRadius),
                  let low = surface.corners.map({ $0[1] }).min(),
                  let high = surface.corners.map({ $0[1] }).max(), high - low < 0.08,
                  point.y - (low + high) / 2 < maximumDrop,
                  (low + high) / 2 - point.y < 0.35 else { return nil }
            return (low + high) / 2
        }.min(by: { abs($0 - point.y) < abs($1 - point.y) })
    }

    /// Never lower a support into its own scanned furniture or snap to another storey.
    static func refined(_ transform: simd_float4x4, hits: [SIMD3<Float>]) -> simd_float4x4 {
        let expected = transform.columns.3
        let valid = hits.filter {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
                && simd_length(SIMD2($0.x - expected.x, $0.z - expected.z)) <= 0.02
                && $0.y >= expected.y && $0.y - expected.y <= refinementLimit
        }
        guard let closest = valid.min(by: { abs($0.y - expected.y) < abs($1.y - expected.y) }) else { return transform }
        var result = transform
        result.columns.3.y = closest.y
        return result
    }
}
