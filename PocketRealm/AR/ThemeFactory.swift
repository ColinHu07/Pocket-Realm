import RealityKit
import RoomPlan
import UIKit

/// Builds a small set of batched meshes in the scan's existing world coordinates.
/// No downloaded assets, guessed room rectangles, or new coordinate origin are needed.
enum ThemeFactory {
    struct Result {
        let anchor: AnchorEntity
        let floorCount: Int
        let vineCount: Int
        var hasContent: Bool { floorCount > 0 || vineCount > 0 }
        var message: String {
            if floorCount == 0 { return "No clear floor detected. Scan again and include more of the floor." }
            if vineCount == 0 { return "Your jungle floor follows Gemini's room plan." }
            return "Gemini's Jungle plan is fitted to this room's floor and walls."
        }
    }

    private struct Volume {
        let inverse: simd_float4x4
        let half: SIMD3<Float>
        func contains(_ point: SIMD3<Float>, padding: Float) -> Bool {
            let p = inverse * SIMD4(point, 1)
            return abs(p.x) <= half.x + padding && abs(p.y) <= half.y + padding
                && abs(p.z) <= half.z + padding
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

    static func jungle(in room: CapturedRoom, observer: SIMD3<Float>, plan: JunglePlan,
                       questPositions: [SIMD3<Float>]) throws -> Result {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "Jungle theme"
        var mesh = GardenMesh()
        let furniture = room.objects.map { Volume(inverse: simd_inverse($0.transform), half: $0.dimensions / 2) }
        let apertures = (room.doors + room.openings + room.windows).map {
            Volume(inverse: simd_inverse($0.transform), half: SIMD3($0.dimensions.x / 2, $0.dimensions.y / 2, 0.3))
        }
        let doorways = (room.doors + room.openings).map {
            Volume(inverse: simd_inverse($0.transform), half: SIMD3($0.dimensions.x / 2, $0.dimensions.y / 2, 0.45))
        }
        var floorCount = 0
        var plantBudget = 900
        var flowerBudget = 36
        var fernBudget = 28

        for floor in room.floors.sorted(by: { $0.identifier.uuidString < $1.identifier.uuidString }).prefix(8)
            where floor.confidence != .low {
            guard let treatment = plan.floors.first(where: { $0.surfaceID == floor.identifier.uuidString }) else { continue }
            // RoomPlan surface corners are local XY; the surface transform places them in the room.
            let corners = surfaceCorners(floor).map { world($0, floor.transform) }
            guard let low = corners.map(\.y).min(), let high = corners.map(\.y).max(), high - low < 0.08 else { continue }
            let polygon = ThemePolygon(corners.map { SIMD2($0.x, $0.z) })
            let triangles = polygon.triangles()
            guard !triangles.isEmpty else { continue }
            let y = (low + high) / 2 + 0.018
            for indices in triangles {
                let points = [indices.x, indices.y, indices.z].map { index -> SIMD3<Float> in
                    let p = polygon.vertices[index]
                    return SIMD3(p.x, y, p.y)
                }
                mesh.triangle(points[0], points[2], points[1], material: 0)
            }
            floorCount += 1
            let seed = ThemeRandom.seed(floor.identifier.uuidString)
            var random = ThemeRandom(seed: seed)
            let points = polygon.scatter(seed: seed, spacing: treatment.growth.spacing, limit: plantBudget)
            plantBudget -= points.count
            for p in points {
                let base = SIMD3(p.x, y + 0.004, p.y)
                guard !questPositions.contains(where: { simd_distance(p, SIMD2($0.x, $0.z)) < 0.55 }) else { continue }
                // Check at plant height and just above the floor, including furniture not used by quests.
                guard !furniture.contains(where: {
                    $0.contains(base + SIMD3(0, 0.12, 0), padding: 0.12)
                        || $0.contains(base, padding: 0.12)
                }), !doorways.contains(where: { $0.contains(base + SIMD3(0, 0.3, 0), padding: 0.15) }) else { continue }

                let radius: Float = 0.07 + random.unit() * 0.06
                // Soft-looking, irregular islands break up the continuous moss carpet.
                if polygon.distanceToEdge(p) > radius {
                    for i in 0..<7 {
                        let a = Float(i) / 7 * 2 * Float.pi
                        let b = Float(i + 1) / 7 * 2 * Float.pi
                        mesh.triangle(base, base + SIMD3(cos(b) * radius, 0, sin(b) * radius),
                                      base + SIMD3(cos(a) * radius, 0, sin(a) * radius), material: 1)
                    }
                }
                for _ in 0..<5 {
                    let angle = random.unit() * 2 * .pi
                    let length: Float = 0.045 + random.unit() * 0.10
                    let side = SIMD3<Float>(cos(angle), 0, sin(angle)) * 0.013
                    let lean = SIMD3<Float>(-sin(angle), 0, cos(angle)) * (length * 0.3)
                    let bottom = base + side * (random.unit() * 3 - 1.5)
                    mesh.triangle(bottom - side, bottom + side, bottom + lean + SIMD3(0, length, 0),
                                  material: random.unit() > 0.5 ? 2 : 3)
                }
                let edgeDistance = polygon.distanceToEdge(p)
                if flowerBudget > 0, random.unit() < treatment.growth.flowerChance * (edgeDistance < 0.8 ? 1 : 0.25) {
                    flower(at: base, height: 0.19 + random.unit() * 0.13,
                           color: 5 + Int(random.unit() * 3), mesh: &mesh)
                    flowerBudget -= 1
                } else if fernBudget > 0, edgeDistance > 0.34, edgeDistance < 0.8, random.unit() < treatment.growth.fernChance,
                          !furniture.contains(where: { $0.contains(base + SIMD3(0, 0.15, 0), padding: 0.35) }),
                          !doorways.contains(where: { $0.contains(base + SIMD3(0, 0.3, 0), padding: 0.35) }) {
                    fern(at: base, angle: random.unit() * 2 * .pi, mesh: &mesh)
                    fernBudget -= 1
                }
            }
        }

        var vineCount = 0
        for wall in room.walls.sorted(by: { $0.identifier.uuidString < $1.identifier.uuidString }).prefix(24)
            where wall.confidence != .low && wall.curve == nil {
            guard let treatment = plan.walls.first(where: { $0.surfaceID == wall.identifier.uuidString }),
                  treatment.vines != .none else { continue }
            guard wall.dimensions.x.isFinite, wall.dimensions.y.isFinite,
                  wall.dimensions.x > 0.3, wall.dimensions.y > 0.5 else { continue }
            let polygon = ThemePolygon(surfaceCorners(wall).map { SIMD2($0.x, $0.y) })
            let localObserver = simd_inverse(wall.transform) * SIMD4(observer, 1)
            let side: Float = localObserver.z >= 0 ? 1 : -1
            let width = min(wall.dimensions.x, 20)
            let height = min(wall.dimensions.y, 5)
            let strands = min(9, max(1, Int(width / treatment.vines.spacing)))
            var random = ThemeRandom(seed: ThemeRandom.seed(wall.identifier.uuidString))
            for index in 0..<strands where vineCount < 60 {
                let x = -width / 2 + (Float(index) + 0.5) * width / Float(strands)
                let start = height / 2 - 0.12
                let length = min(height - 0.3, treatment.vines.length * (0.55 + random.unit() * 0.45))
                let phase = random.unit() * 6
                var previous: SIMD3<Float>?
                var drew = false
                for step in 0...14 {
                    let t = Float(step) / 14
                    let local = SIMD3<Float>(x + sin(t * 5 + phase) * 0.075, start - length * t, side * 0.07)
                    let point = world(local, wall.transform)
                    // Whole segments stop at openings, and at the boundary of slanted walls.
                    guard polygon.contains(SIMD2(local.x, local.y), inset: 0.15),
                          !apertures.contains(where: { $0.contains(point, padding: 0.2) }),
                          !furniture.contains(where: { $0.contains(point, padding: 0.1) }) else {
                        previous = nil
                        continue
                    }
                    if let previous {
                        mesh.stem(from: previous, to: point, radius: 0.008, material: 4)
                        drew = true
                    }
                    if step % 2 == 0 {
                        let direction: Float = step % 4 == 0 ? 1 : -1
                        let tip = world(local + SIMD3(direction * 0.13, -0.08, side * 0.025), wall.transform)
                        let across = world(local + SIMD3(0.025, 0.04, 0), wall.transform) - point
                        mesh.leaf(from: point, to: tip, across: across, material: step % 4 == 0 ? 2 : 3)
                    }
                    previous = point
                }
                if drew { vineCount += 1 }
            }
        }
        if let entity = try mesh.entity(palette: plan.palette) { anchor.addChild(entity) }
        return Result(anchor: anchor, floorCount: floorCount, vineCount: vineCount)
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

    private static func flower(at base: SIMD3<Float>, height: Float, color: Int, mesh: inout GardenMesh) {
        let center = base + SIMD3<Float>(0.015, height, 0)
        mesh.stem(from: base, to: center, radius: 0.006, material: 4)
        mesh.leaf(from: base + SIMD3(0, height * 0.4, 0), to: base + SIMD3(0.12, height * 0.7, 0),
                  across: SIMD3(0, 0.01, 0.035), material: 3)
        for i in 0..<6 {
            let angle = Float(i) * .pi / 3
            let direction = SIMD3<Float>(cos(angle), 0, sin(angle))
            let across = SIMD3<Float>(-sin(angle), 0, cos(angle)) * 0.037
            mesh.leaf(from: center, to: center + direction * 0.105 + SIMD3(0, 0.025, 0), across: across, material: color)
            let next = Float(i + 1) * .pi / 3
            mesh.triangle(center + SIMD3(0, 0.02, 0), center + direction * 0.026,
                          center + SIMD3(cos(next) * 0.026, 0, sin(next) * 0.026), material: 8)
        }
    }

    private static func fern(at base: SIMD3<Float>, angle: Float, mesh: inout GardenMesh) {
        for i in 0..<5 {
            let a = angle + Float(i) * .pi * 0.4
            let direction = SIMD3<Float>(cos(a), 0, sin(a))
            let across = SIMD3<Float>(-sin(a), 0, cos(a))
            let top = base + direction * 0.26 + SIMD3(0, 0.24, 0)
            mesh.stem(from: base, to: top, radius: 0.004, material: 4)
            for j in 1...5 {
                let t = Float(j) / 6
                let joint = base + (top - base) * t
                for side: Float in [-1, 1] {
                    let tip = joint + across * side * (0.10 * (1 - t) + 0.025) + direction * 0.05
                    mesh.leaf(from: joint, to: tip, across: direction * 0.016, material: i % 2 == 0 ? 2 : 3)
                }
            }
        }
    }
}

/// One model, nine material batches; plants don't add thousands of scene entities/draw calls.
private struct GardenMesh {
    private struct Batch {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
    }
    private var batches = Array(repeating: Batch(), count: 9)

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: Int) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length_squared(cross) > 0.000000000001 else { return }
        let normal = simd_normalize(cross)
        let index = UInt32(batches[material].positions.count)
        batches[material].positions.append(contentsOf: [a, b, c])
        batches[material].normals.append(contentsOf: [normal, normal, normal])
        batches[material].indices.append(contentsOf: [index, index + 1, index + 2])
    }

    mutating func leaf(from start: SIMD3<Float>, to end: SIMD3<Float>, across: SIMD3<Float>, material: Int) {
        let mid = start + (end - start) * 0.55
        let ridge = mid + SIMD3<Float>(0, 0.012, 0)
        triangle(start, mid + across, ridge, material: material)
        triangle(mid + across, end, ridge, material: material)
        triangle(end, mid - across, ridge, material: material)
        triangle(mid - across, start, ridge, material: material)
    }

    mutating func stem(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, material: Int) {
        guard simd_distance(start, end) > 0.0001 else { return }
        let axis = simd_normalize(end - start)
        let right = simd_normalize(simd_cross(axis, abs(axis.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)))
        let forward = simd_cross(axis, right)
        for i in 0..<5 {
            let a = Float(i) / 5 * .pi * 2, b = Float(i + 1) / 5 * .pi * 2
            let offsetA = (right * cos(a) + forward * sin(a)) * radius
            let offsetB = (right * cos(b) + forward * sin(b)) * radius
            triangle(start + offsetA, start + offsetB, end + offsetA, material: material)
            triangle(start + offsetB, end + offsetB, end + offsetA, material: material)
        }
    }

    func entity(palette: JunglePlan.Palette) throws -> ModelEntity? {
        let colors: [UInt32] = palette == .forest
            ? [0x244C32, 0x38613B, 0x508E42, 0x88B951, 0x355B32, 0xF078AC, 0xF5A353, 0xBC91EA, 0xFFE193]
            : [0x245C3E, 0x3D784A, 0x30A569, 0xB1D858, 0x347046, 0xFF696B, 0xFFC04C, 0xDA82DB, 0xFFF2B0]
        let moss = try mossTexture()
        let materials: [PhysicallyBasedMaterial] = colors.enumerated().map { index, hex in
            let color = UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                                blue: CGFloat(hex & 255) / 255, alpha: 1)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.92)
            material.specular = .init(floatLiteral: 0.15)
            material.faceCulling = .none
            if index < 2, let moss {
                material.baseColor = .init(tint: index == 0 ? .white : UIColor(white: 0.82, alpha: 1), texture: moss)
            }
            return material
        }
        let descriptors: [MeshDescriptor] = batches.enumerated().compactMap { index, batch in
            guard !batch.indices.isEmpty else { return nil }
            var descriptor = MeshDescriptor(name: "Jungle material \(index)")
            descriptor.positions = MeshBuffers.Positions(batch.positions)
            descriptor.normals = MeshBuffers.Normals(batch.normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(batch.positions.map { SIMD2($0.x * 1.6, $0.z * 1.6) })
            descriptor.primitives = .triangles(batch.indices)
            descriptor.materials = .allFaces(UInt32(index))
            return descriptor
        }
        guard !descriptors.isEmpty else { return nil }
        return ModelEntity(mesh: try MeshResource.generate(from: descriptors), materials: materials)
    }

    /// A seamless, deterministic moss texture made locally, at a constant scale in meters.
    private func mossTexture() throws -> MaterialParameters.Texture? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            let context = renderer.cgContext
            UIColor(red: 0.19, green: 0.31, blue: 0.14, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var random = ThemeRandom(seed: 714)
            for i in 0..<2400 {
                let x = CGFloat(random.unit()) * 256, y = CGFloat(random.unit()) * 256
                let size = CGFloat(random.unit()) * (i < 160 ? 26 : 3) + 1
                let shade = CGFloat(random.unit())
                UIColor(red: 0.15 + shade * 0.20, green: 0.25 + shade * 0.25, blue: 0.08 + shade * 0.12,
                        alpha: i < 160 ? 0.3 : 0.65).setFill()
                // Wrap edge marks so repeated tiles have no seams.
                for dx: CGFloat in [-256, 0, 256] {
                    for dy: CGFloat in [-256, 0, 256] {
                        context.fillEllipse(in: CGRect(x: x + dx, y: y + dy, width: size, height: size * 0.6))
                    }
                }
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        let resource = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        var texture = MaterialParameters.Texture(resource)
        texture.sampler.modify { sampler in
            sampler.sAddressMode = .repeat
            sampler.tAddressMode = .repeat
        }
        return texture
    }
}
