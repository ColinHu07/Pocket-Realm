import Foundation

enum RealmTheme: String, CaseIterable, Identifiable {
    case original, jungle

    var id: String { rawValue }
    var name: String { self == .jungle ? "Jungle" : "Original" }
    var symbol: String { self == .jungle ? "leaf.fill" : "house.fill" }
    var subtitle: String {
        self == .jungle ? "Mossy floors, leafy vines, and tropical blooms." : "Your familiar room, with a little magic."
    }
}

/// Horizontal, world-space footprint. Also used in wall-local XY coordinates.
/// Keep the actual polygon: a bounding rectangle would fill missing corners of L-shaped rooms.
struct ThemePolygon {
    let vertices: [SIMD2<Float>]

    init(_ points: [SIMD2<Float>]) {
        var cleaned: [SIMD2<Float>] = []
        for point in points where point.x.isFinite && point.y.isFinite {
            if let last = cleaned.last, Self.distanceSquared(last, point) < 0.000001 { continue }
            cleaned.append(point)
        }
        if let first = cleaned.first, let last = cleaned.last,
           Self.distanceSquared(first, last) < 0.000001 { cleaned.removeLast() }
        vertices = cleaned
    }

    var area: Float {
        guard vertices.count >= 3 else { return 0 }
        return abs(signedArea)
    }

    private var signedArea: Float {
        vertices.indices.reduce(Float(0)) { sum, i in
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            return sum + (a.x * b.y - b.x * a.y) / 2
        }
    }

    func contains(_ point: SIMD2<Float>, inset: Float = 0) -> Bool {
        guard vertices.count >= 3, point.x.isFinite, point.y.isFinite else { return false }
        var inside = false
        for i in vertices.indices {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside && distanceToEdge(point) >= inset
    }

    func distanceToEdge(_ point: SIMD2<Float>) -> Float {
        guard vertices.count >= 3 else { return 0 }
        return vertices.indices.map { i in
            let a = vertices[i], edge = vertices[(i + 1) % vertices.count] - a
            let lengthSquared = edge.x * edge.x + edge.y * edge.y
            let relative = point - a
            let t = max(0, min(1, (relative.x * edge.x + relative.y * edge.y) / max(lengthSquared, 0.000001)))
            return sqrt(Self.distanceSquared(point, a + edge * t))
        }.min() ?? 0
    }

    /// Ear clipping handles concave floors and either winding. Invalid polygons render nothing.
    func triangles() -> [SIMD3<Int>] {
        guard vertices.count >= 3, vertices.count <= 256, area > 0.001 else { return [] }
        var remaining = signedArea > 0 ? Array(vertices.indices) : Array(vertices.indices.reversed())
        var result: [SIMD3<Int>] = []
        while remaining.count > 3 {
            var clipped = false
            for i in remaining.indices {
                let a = remaining[(i + remaining.count - 1) % remaining.count]
                let b = remaining[i], c = remaining[(i + 1) % remaining.count]
                let turn = Self.cross(vertices[b] - vertices[a], vertices[c] - vertices[b])
                if abs(turn) < 0.000001 {
                    remaining.remove(at: i)
                    clipped = true
                    break
                }
                guard turn > 0 else { continue }
                let occupied = remaining.contains { index in
                    guard index != a && index != b && index != c else { return false }
                    let p = vertices[index]
                    return Self.cross(vertices[b] - vertices[a], p - vertices[a]) >= -0.000001
                        && Self.cross(vertices[c] - vertices[b], p - vertices[b]) >= -0.000001
                        && Self.cross(vertices[a] - vertices[c], p - vertices[c]) >= -0.000001
                }
                guard !occupied else { continue }
                result.append([a, b, c])
                remaining.remove(at: i)
                clipped = true
                break
            }
            guard clipped else { return [] }
        }
        if remaining.count == 3 { result.append(SIMD3(remaining[0], remaining[1], remaining[2])) }
        return result
    }

    /// Bounded, repeatable scatter. Returning to a preset never shuffles its plants.
    func scatter(seed: UInt64, spacing: Float = 0.25, limit: Int = 700, inset: Float = 0.15) -> [SIMD2<Float>] {
        guard area > 0.001, vertices.count <= 256, spacing.isFinite, spacing > 0, limit > 0,
              let minX = vertices.map(\.x).min(), let maxX = vertices.map(\.x).max(),
              let minY = vertices.map(\.y).min(), let maxY = vertices.map(\.y).max() else { return [] }
        let width = maxX - minX, height = maxY - minY
        guard width.isFinite, height.isFinite, width < 100, height < 100 else { return [] }
        let step = max(spacing, sqrt(width * height / Float(limit)))
        var random = ThemeRandom(seed: seed)
        var points: [SIMD2<Float>] = []
        for row in 0..<max(1, Int(ceil(height / step))) {
            for column in 0..<max(1, Int(ceil(width / step))) {
                let p = SIMD2(minX + (Float(column) + 0.25 + random.unit() * 0.5) * step,
                              minY + (Float(row) + 0.25 + random.unit() * 0.5) * step)
                if contains(p, inset: inset) { points.append(p) }
            }
        }
        // Avoid filling just one side when the cell count slightly exceeds the budget.
        points.shuffle(using: &random)
        return Array(points.prefix(limit))
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
    private static func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d = a - b
        return d.x * d.x + d.y * d.y
    }
}

struct ThemeRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}
