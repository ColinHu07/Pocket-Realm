import RealityKit
import RoomPlan
import UIKit

/// Places bundled Blender decorations only on observed wall patches. Never covers floors.
enum ThemeFactory {
    struct Result {
        let theme: RealmTheme
        let anchor: AnchorEntity
        let clusterCount: Int
        var hasContent: Bool { clusterCount > 0 }
        var message: String {
            hasContent ? "\(theme.name) decorations follow the visible walls in your scan."
                : "No clear wall patches for decorations yet. Rescan while looking at more open wall space."
        }
    }

    /// Only advertise surfaces the renderer can decorate. All geometry shares the ARSession's origin.
    static func context(for room: CapturedRoom) -> RoomScanContext {
        func measured(_ surface: CapturedRoom.Surface, kind: RoomSurfaceContext.Kind) -> RoomSurfaceContext? {
            let corners = surfaceCorners(surface).map { world($0, surface.transform) }
            let normal = SIMD3(surface.transform.columns.2.x, surface.transform.columns.2.y, surface.transform.columns.2.z)
            let center = world(.zero, surface.transform)
            let vectors = corners + [surface.dimensions, center, normal]
            guard (3...256).contains(corners.count), vectors.allSatisfy({ p in
                [p.x, p.y, p.z].allSatisfy { $0.isFinite && abs($0) <= 100 }
            }), simd_length_squared(normal) > 0.5 else { return nil }
            if kind == .floor {
                guard let low = corners.map(\.y).min(), let high = corners.map(\.y).max(), high - low < 0.08,
                      !ThemePolygon(corners.map { SIMD2($0.x, $0.z) }).triangles().isEmpty else { return nil }
            }
            func values(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }
            return RoomSurfaceContext(id: surface.identifier.uuidString, kind: kind,
                dimensions: values(surface.dimensions), position: values(center),
                corners: corners.map(values), normal: values(simd_normalize(normal)))
        }
        let floors = room.floors.sorted { $0.identifier.uuidString < $1.identifier.uuidString }.prefix(8)
            .filter { $0.confidence != .low }.compactMap { measured($0, kind: .floor) }
        let walls = room.walls.sorted { $0.identifier.uuidString < $1.identifier.uuidString }.prefix(24)
            .filter { $0.confidence != .low && $0.curve == nil && $0.dimensions.x > 0.3 && $0.dimensions.y > 0.5 }
            .compactMap { measured($0, kind: .wall) }
        let apertures = (room.doors.compactMap { measured($0, kind: .door) }
            + room.openings.compactMap { measured($0, kind: .opening) }
            + room.windows.compactMap { measured($0, kind: .window) }).prefix(32)
        let obstacles = room.objects.prefix(64).map {
            let p = world(.zero, $0.transform)
            return RoomObstacleContext(category: String(describing: $0.category),
                dimensions: [$0.dimensions.x, $0.dimensions.y, $0.dimensions.z], position: [p.x, p.y, p.z])
        }
        return RoomScanContext(surfaces: floors + walls + Array(apertures), obstacles: obstacles)
    }

    static func make(_ theme: RealmTheme, in room: CapturedRoom, observer: SIMD3<Float>, plan: JunglePlan,
                       questPositions: [SIMD3<Float>], observations: [WallObservation]) throws -> Result {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "\(theme.name) wall decorations"
        let furniture = room.objects.map { DecorationVolume(inverse: simd_inverse($0.transform), half: $0.dimensions / 2) }
        let apertures = (room.doors + room.openings + room.windows).map {
            DecorationVolume(inverse: simd_inverse($0.transform), half: SIMD3($0.dimensions.x / 2, $0.dimensions.y / 2, 0.35))
        }
        let assets = theme.assets(palette: plan.palette)
        guard !assets.isEmpty else { return Result(theme: theme, anchor: anchor, clusterCount: 0) }
        let models = try assets.map { asset -> Entity in
            guard let url = Bundle.main.url(forResource: asset.name, withExtension: "usdz", subdirectory: asset.directory) else {
                throw PlanError.server("The \(theme.name) models are missing. Rebuild the app with its theme assets.")
            }
            return try Entity.load(contentsOf: url)
        }
        var count = 0
        var triangleBudget = 350_000
        let costs = assets.map(\.triangles)
        for wall in room.walls.sorted(by: { $0.identifier.uuidString < $1.identifier.uuidString }).prefix(24)
            where wall.confidence != .low && wall.curve == nil {
            guard let treatment = plan.walls.first(where: { $0.surfaceID == wall.identifier.uuidString }),
                  treatment.vines != .none, wall.dimensions.x > 0.4, wall.dimensions.y > 0.6 else { continue }
            let polygon = ThemePolygon(surfaceCorners(wall).map { SIMD2($0.x, $0.y) })
            // Use a recorded viewpoint near this wall to select the interior face.
            let center = world(.zero, wall.transform)
            let nearest = observations.min { simd_distance($0.position, center) < simd_distance($1.position, center) }
            let localObserver = simd_inverse(wall.transform) * SIMD4(nearest?.position ?? observer, 1)
            let side: Float = localObserver.z >= 0 ? 1 : -1
            let blockers = furniture + room.walls.filter { $0.identifier != wall.identifier }.map {
                DecorationVolume(inverse: simd_inverse($0.transform), half: SIMD3($0.dimensions.x / 2, $0.dimensions.y / 2, 0.025))
            }
            let width = min(wall.dimensions.x, 20), height = min(wall.dimensions.y, 5)
            let columns = max(1, Int(ceil(width / (treatment.vines == .lush ? 0.72 : 1.15))))
            var random = ThemeRandom(seed: ThemeRandom.seed(wall.identifier.uuidString))
            var occupied: [(SIMD2<Float>, SIMD2<Float>)] = []
            let wallLimit = treatment.vines == .lush ? 5 : 3
            for column in 0..<columns {
                guard count < 20, occupied.count < wallLimit else { break }
                let x = -width / 2 + (Float(column) + 0.5) * width / Float(columns)
                let firstModel = (column + Int(random.unit() * 3)) % models.count
                var placed = false
                // Search downward through actual viewed regions; don't assume the ceiling was scanned.
                for row in 0..<max(1, Int(height / 0.25)) {
                    if placed { break }
                    let top = height / 2 - 0.12 - Float(row) * 0.25
                    for index in 0..<models.count {
                        let kind = (firstModel + index) % models.count
                        guard triangleBudget >= costs[kind] else { continue }
                        let scale: Float = treatment.vines == .lush ? 0.95 : 0.78
                        let bounds = models[kind].visualBounds(relativeTo: models[kind])
                        let depth = max(0, bounds.max.z * scale) + 0.025
                        let minX = min(bounds.min.x * side, bounds.max.x * side) * scale + x
                        let maxX = max(bounds.min.x * side, bounds.max.x * side) * scale + x
                        let low = SIMD2(minX, top + bounds.min.y * scale)
                        let high = SIMD2(maxX, top + bounds.max.y * scale)
                        guard !occupied.contains(where: { a, b in
                            low.x < b.x + 0.12 && high.x > a.x - 0.12 && low.y < b.y + 0.12 && high.y > a.y - 0.12
                        }) else { continue }
                        let fits = WallVisibility.footprint(minimum: low, maximum: high, polygon: polygon) { p in
                            let point = world(SIMD3(p.x, p.y, side * 0.025), wall.transform)
                            return !apertures.contains { $0.contains(point, padding: 0.14) }
                                && !furniture.contains { $0.contains(point, padding: max(0.16, depth + 0.04)) }
                                && !questPositions.contains { simd_distance(point, $0) < 0.5 }
                                && WallVisibility.observed(point, in: observations, blockers: blockers)
                        }
                        guard fits else { continue }
                        let mount = Entity()
                        var placement = matrix_identity_float4x4
                        placement.columns.0.x = side
                        placement.columns.2.z = side
                        placement.columns.3 = SIMD4(x, top, side * 0.025, 1)
                        mount.transform = Transform(matrix: wall.transform * placement)
                        let plant = models[kind].clone(recursive: true)
                        plant.scale *= SIMD3(repeating: scale)
                        mount.addChild(plant); anchor.addChild(mount)
                        occupied.append((low, high)); count += 1; triangleBudget -= costs[kind]
                        placed = true
                        break
                    }
                }
            }
        }
        return Result(theme: theme, anchor: anchor, clusterCount: count)
    }

    private static func surfaceCorners(_ surface: CapturedRoom.Surface) -> [SIMD3<Float>] {
        if surface.polygonCorners.count >= 3 { return surface.polygonCorners }
        let half = surface.dimensions / 2
        return [SIMD3(-half.x, -half.y, 0), SIMD3(half.x, -half.y, 0),
                SIMD3(half.x, half.y, 0), SIMD3(-half.x, half.y, 0)]
    }

    private static func world(_ p: SIMD3<Float>, _ transform: simd_float4x4) -> SIMD3<Float> {
        let result = transform * SIMD4(p, 1)
        return SIMD3(result.x, result.y, result.z)
    }

}
