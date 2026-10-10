import Foundation
import simd

/// Camera geometry retained locally after the six JPEGs are discarded. No image pixels are kept.
struct WallObservation {
    let cameraTransform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageSize: SIMD2<Float>
    var depth: [Float] = []
    var depthWidth = 0
    var depthHeight = 0

    var position: SIMD3<Float> {
        let p = cameraTransform.columns.3
        return SIMD3(p.x, p.y, p.z)
    }

    func sees(_ point: SIMD3<Float>) -> Bool {
        let local = simd_inverse(cameraTransform) * SIMD4(point, 1)
        let distance = -local.z
        guard distance.isFinite, distance >= 0.2, distance <= 6,
              imageSize.x > 0, imageSize.y > 0 else { return false }
        // ARKit camera: -Z forward, +Y up. Raw captured-image pixels: +Y down.
        let pixel = SIMD2(intrinsics[0][0] * local.x / distance + intrinsics[2][0],
                          intrinsics[2][1] - intrinsics[1][1] * local.y / distance)
        let uv = pixel / imageSize
        guard uv.x.isFinite, uv.y.isFinite, uv.x >= 0.04, uv.x <= 0.96,
              uv.y >= 0.04, uv.y <= 0.96 else { return false }
        if !depth.isEmpty {
            guard depthWidth > 0, depthHeight > 0, depth.count == depthWidth * depthHeight else { return false }
            let x = min(depthWidth - 1, Int(uv.x * Float(depthWidth)))
            let y = min(depthHeight - 1, Int(uv.y * Float(depthHeight)))
            let measured = depth[y * depthWidth + x]
            // Missing/unconfident depth is not evidence of a visible wall.
            guard measured.isFinite, measured > 0, abs(measured - distance) <= 0.20 else { return false }
        }
        return true
    }
}

struct DecorationVolume {
    let inverse: simd_float4x4
    let half: SIMD3<Float>

    /// Conservative box overlap in the obstacle's frame. Tests the complete
    /// character, rather than a single point near its feet.
    func intersects(minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> Bool {
        let center = inverse * SIMD4((minimum + maximum) / 2, 1)
        let radius = (maximum - minimum) / 2
        for axis in 0..<3 {
            let extent = abs(inverse[0][axis]) * radius.x
                + abs(inverse[1][axis]) * radius.y + abs(inverse[2][axis]) * radius.z
            if abs(center[axis]) >= half[axis] + extent { return false }
        }
        return true
    }

    func contains(_ point: SIMD3<Float>, padding: Float) -> Bool {
        let p = inverse * SIMD4(point, 1)
        return abs(p.x) <= half.x + padding && abs(p.y) <= half.y + padding && abs(p.z) <= half.z + padding
    }

    /// Segment/rotated-box intersection. Ignore the last few cm at the target wall.
    func blocks(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let a = inverse * SIMD4(start, 1), b = inverse * SIMD4(end, 1)
        let length = simd_distance(start, end)
        guard length > 0.1 else { return false }
        var low: Float = 0.01 / length, high: Float = 1 - 0.08 / length
        for axis in 0..<3 {
            let delta = b[axis] - a[axis]
            if abs(delta) < 0.00001 {
                if abs(a[axis]) > half[axis] { return false }
            } else {
                let near = (-half[axis] - a[axis]) / delta
                let far = (half[axis] - a[axis]) / delta
                low = max(low, min(near, far)); high = min(high, max(near, far))
                if low > high { return false }
            }
        }
        return low <= high
    }
}

enum WallVisibility {
    static func observed(_ point: SIMD3<Float>, in views: [WallObservation], blockers: [DecorationVolume]) -> Bool {
        views.contains { view in
            view.sees(point) && !blockers.contains { $0.blocks(from: view.position, to: point) }
        }
    }

    /// Check the whole asset footprint, including its leaves, rather than just its attachment point.
    static func footprint(minimum: SIMD2<Float>, maximum: SIMD2<Float>, polygon: ThemePolygon,
                          accepts: (SIMD2<Float>) -> Bool) -> Bool {
        let size = maximum - minimum
        guard size.x > 0, size.y > 0, size.x < 2, size.y < 2 else { return false }
        let columns = max(2, Int(ceil(size.x / 0.07)))
        let rows = max(2, Int(ceil(size.y / 0.07)))
        for row in 0...rows {
            for column in 0...columns {
                let p = minimum + size * SIMD2(Float(column) / Float(columns), Float(row) / Float(rows))
                if !polygon.contains(p, inset: 0.06) || !accepts(p) { return false }
            }
        }
        return true
    }
}
