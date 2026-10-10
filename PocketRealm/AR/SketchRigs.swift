import RealityKit
import UIKit

/// A procedural trap around the friend's lost item: shakes when hit, bursts apart when cleared.
/// Built only from boxes, spheres, and text so it runs on iOS 17. +Z faces the player.
@MainActor
final class TrapRig {
    let root = Entity()
    let challenge: Challenge
    /// How far above its usual spot the item sits while trapped (the bubble floats it up).
    let keepsakeLift: Float
    let hidesKeepsake: Bool
    private var parts: [Entity] = []
    private var drips: [Entity] = []
    private var snores: [Entity] = []
    private var orbiters: [Entity] = []
    private var sparks: [(entity: ModelEntity, velocity: SIMD3<Float>, age: Float)] = []
    private var flying: [(entity: Entity, velocity: SIMD3<Float>, spin: SIMD3<Float>)] = []
    private var time: Float = 0
    private var shake: Float = 0
    private var hits = 0
    private(set) var shattered: Float?

    init(challenge: Challenge, accent: UIColor) {
        self.challenge = challenge
        root.name = "Trap"
        keepsakeLift = challenge.trap == .wobbleBubble ? 0.45 : 0
        hidesKeepsake = [.snoringBoulder, .shadowPuddle].contains(challenge.trap)
        switch challenge.trap {
        case .moonIce: buildIce()
        case .grumbleCloud: buildCloud()
        case .thornKnot: buildVines()
        case .snoringBoulder: buildBoulder()
        case .wobbleBubble: buildBubble()
        case .shadowPuddle: buildPuddle()
        }
        root.generateCollisionShapes(recursive: true)
    }

    var finished: Bool { (shattered ?? 0) > 1.2 }

    func hit() {
        hits += 1
        shake = 0.35
        burst(count: 10, colors: [.white, Self.color(for: challenge.trap)], speed: 0.6)
    }

    func shatter() {
        guard shattered == nil else { return }
        shattered = 0
        burst(count: 24, colors: [.white, .systemYellow, Self.color(for: challenge.trap)], speed: 1.0)
        for part in parts {
            var direction = part.position(relativeTo: root)
            if simd_length(direction) < 0.01 { direction = [Float.random(in: -1...1), 0.5, Float.random(in: -1...1)] }
            let velocity = simd_normalize(direction) * Float.random(in: 0.5...0.9) + [0, 0.5, 0]
            flying.append((part, velocity, [Float.random(in: -6...6), Float.random(in: -6...6), Float.random(in: -6...6)]))
        }
    }

    func update(delta: Float) {
        time += delta
        if let elapsed = shattered {
            shattered = elapsed + delta
            for index in flying.indices {
                flying[index].velocity.y -= 1.6 * delta
                let entity = flying[index].entity
                entity.position += flying[index].velocity * delta
                entity.orientation = simd_quatf(angle: flying[index].spin.x * delta, axis: [1, 0, 0])
                    * simd_quatf(angle: flying[index].spin.y * delta, axis: [0, 1, 0]) * entity.orientation
                entity.scale = .one * max(0.001, 1 - elapsed / 1.1)
            }
        } else {
            // Each hit leaves the trap a little smaller and wobblier.
            let worn = max(0.55, 1 - Float(hits) * 0.09)
            shake = max(0, shake - delta)
            let jitter = sin(time * 70) * 0.014 * (shake / 0.35)
            root.position = [jitter, keepsakeLift, 0]
            root.scale = .one * worn
            animateIdle()
        }
        for index in sparks.indices.reversed() {
            sparks[index].age += delta
            sparks[index].velocity.y -= 1.2 * delta
            sparks[index].entity.position += sparks[index].velocity * delta
            sparks[index].entity.scale = .one * max(0.001, 1 - sparks[index].age / 0.7)
            if sparks[index].age > 0.7 {
                sparks[index].entity.removeFromParent()
                sparks.remove(at: index)
            }
        }
    }

    private func animateIdle() {
        switch challenge.trap {
        case .grumbleCloud:
            for (index, drop) in drips.enumerated() {
                let phase = (time * 0.9 + Float(index) * 0.21).truncatingRemainder(dividingBy: 1)
                drop.position.y = 0.04 - phase * 0.24
                drop.scale = .one * (phase < 0.9 ? 1 : 0.001)
            }
        case .snoringBoulder:
            for (index, z) in snores.enumerated() {
                let phase = (time * 0.35 + Float(index) / 3).truncatingRemainder(dividingBy: 1)
                z.position = [0.08 + phase * 0.08, 0.12 + phase * 0.18, 0.05]
                z.scale = .one * (0.6 + phase) * (phase < 0.85 ? 1 : 0.001)
            }
            parts.first?.scale = [1.1, 0.8 + sin(time * 1.6) * 0.03, 1]
        case .wobbleBubble:
            let wobble = sin(time * 3) * 0.04
            parts.first?.scale = [1 + wobble, 1 - wobble, 1 + wobble * 0.5]
        case .shadowPuddle:
            for (index, orb) in orbiters.enumerated() {
                let angle = time * 1.4 + Float(index) * .pi / 3
                orb.position = [cos(angle) * 0.15, -0.06 + sin(time * 2 + Float(index)) * 0.01, sin(angle) * 0.15]
            }
        case .thornKnot:
            root.orientation = simd_quatf(angle: sin(time * 0.8) * 0.06, axis: [0, 1, 0])
        case .moonIce:
            break
        }
    }

    private func burst(count: Int, colors: [UIColor], speed: Float) {
        let center = SIMD3<Float>(0, keepsakeLift, 0)
        for index in 0..<count {
            let spark = ModelEntity(mesh: .generateSphere(radius: 0.008),
                                    materials: [UnlitMaterial(color: colors[index % colors.count])])
            spark.position = center
            root.parent?.addChild(spark)
            let direction = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: 0...1.2), Float.random(in: -1...1)))
            sparks.append((spark, direction * speed * Float.random(in: 0.5...1), 0))
        }
    }

    private func part(_ mesh: MeshResource, _ material: RealityKit.Material, at position: SIMD3<Float>,
                      scale: SIMD3<Float> = .one, flies: Bool = true) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.scale = scale
        root.addChild(entity)
        if flies { parts.append(entity) }
        return entity
    }

    private static func matte(_ color: UIColor, roughness: Float = 0.7) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .init(floatLiteral: roughness), isMetallic: false)
    }

    private static func glass(_ color: UIColor, opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.05
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    static func color(for trap: Challenge.Trap) -> UIColor {
        switch trap {
        case .moonIce: return UIColor(red: 0.72, green: 0.92, blue: 1, alpha: 1)
        case .grumbleCloud: return UIColor(red: 0.55, green: 0.58, blue: 0.66, alpha: 1)
        case .thornKnot: return UIColor(red: 0.20, green: 0.42, blue: 0.22, alpha: 1)
        case .snoringBoulder: return UIColor(red: 0.55, green: 0.50, blue: 0.46, alpha: 1)
        case .wobbleBubble: return UIColor(red: 0.85, green: 0.80, blue: 1, alpha: 1)
        case .shadowPuddle: return UIColor(red: 0.30, green: 0.12, blue: 0.45, alpha: 1)
        }
    }

    private func buildIce() {
        // Eight chunks with visible seams, so it reads as ice that can crack apart.
        let ice = Self.glass(Self.color(for: .moonIce), opacity: 0.42)
        for x in [-1, 1] as [Float] { for y in [-1, 1] as [Float] { for z in [-1, 1] as [Float] {
            _ = part(.generateBox(size: 0.148, cornerRadius: 0.025), ice, at: [x * 0.076, y * 0.076, z * 0.076])
        } } }
        for _ in 0..<12 {
            _ = part(.generateSphere(radius: 0.005), UnlitMaterial(color: .white),
                     at: [Float.random(in: -0.13...0.13), Float.random(in: -0.13...0.13), Float.random(in: -0.13...0.13)])
        }
    }

    private func buildCloud() {
        let fluff = Self.matte(Self.color(for: .grumbleCloud), roughness: 0.95)
        let puffs: [(SIMD3<Float>, Float)] = [([0, 0.2, 0], 0.1), ([-0.1, 0.17, 0.01], 0.08), ([0.1, 0.17, 0.0], 0.085),
                                               ([-0.05, 0.25, -0.02], 0.08), ([0.06, 0.25, -0.02], 0.075), ([0, 0.15, 0.05], 0.07)]
        for (position, radius) in puffs { _ = part(.generateSphere(radius: radius), fluff, at: position) }
        let ink = UnlitMaterial(color: UIColor(white: 0.1, alpha: 1))
        for side in [-1, 1] as [Float] {
            _ = part(.generateSphere(radius: 0.013), ink, at: [side * 0.035, 0.205, 0.105])
            let brow = part(.generateBox(size: [0.04, 0.008, 0.008]), ink, at: [side * 0.038, 0.235, 0.1])
            brow.orientation = simd_quatf(angle: side * 0.45, axis: [0, 0, 1])
        }
        let rain = UnlitMaterial(color: UIColor(red: 0.45, green: 0.65, blue: 1, alpha: 1))
        for index in 0..<6 {
            drips.append(part(.generateSphere(radius: 0.008), rain, at: [Float(index - 3) * 0.035 + 0.015, 0.04, 0.02],
                              scale: [0.6, 1.6, 0.6], flies: false))
        }
    }

    private func buildVines() {
        let vine = Self.matte(Self.color(for: .thornKnot))
        let thorn = Self.matte(UIColor(red: 0.95, green: 0.55, blue: 0.6, alpha: 1), roughness: 0.4)
        for index in 0..<10 {
            let angle = Float(index) * 2 * .pi / 10
            let height = Float(index % 3 - 1) * 0.06
            let strand = part(.generateSphere(radius: 0.03), vine, at: [cos(angle) * 0.11, height, sin(angle) * 0.11],
                              scale: [0.7, 0.7, 3.2])
            strand.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0]) * simd_quatf(angle: Float(index % 2 == 0 ? 0.5 : -0.5), axis: [1, 0, 0])
            _ = part(.generateSphere(radius: 0.012), thorn, at: [cos(angle + 0.3) * 0.14, height + 0.02, sin(angle + 0.3) * 0.14],
                     scale: [0.6, 1.8, 0.6])
        }
    }

    private func buildBoulder() {
        _ = part(.generateSphere(radius: 0.17), Self.matte(Self.color(for: .snoringBoulder), roughness: 1), at: [0, 0, 0],
                 scale: [1.1, 0.8, 1])
        let ink = UnlitMaterial(color: UIColor(white: 0.12, alpha: 1))
        for side in [-1, 1] as [Float] {
            _ = part(.generateBox(size: [0.05, 0.007, 0.01], cornerRadius: 0.003), ink, at: [side * 0.055, 0.04, 0.17])
        }
        _ = part(.generateBox(size: [0.025, 0.012, 0.01], cornerRadius: 0.005), ink, at: [0, -0.02, 0.175])
        let letter = MeshResource.generateText("z", extrusionDepth: 0.003, font: .systemFont(ofSize: 0.05, weight: .bold))
        for _ in 0..<3 {
            snores.append(part(letter, UnlitMaterial(color: .white), at: [0.1, 0.15, 0.05], flies: false))
        }
    }

    private func buildBubble() {
        _ = part(.generateSphere(radius: 0.17), Self.glass(Self.color(for: .wobbleBubble), opacity: 0.28), at: [0, 0, 0])
        _ = part(.generateSphere(radius: 0.025), UnlitMaterial(color: UIColor(white: 1, alpha: 0.9)), at: [-0.07, 0.08, 0.12])
    }

    private func buildPuddle() {
        _ = part(.generateSphere(radius: 0.2), Self.matte(Self.color(for: .shadowPuddle), roughness: 0.2), at: [0, -0.08, 0],
                 scale: [1, 0.07, 1])
        let glow = UnlitMaterial(color: UIColor(red: 0.75, green: 0.5, blue: 1, alpha: 1))
        for _ in 0..<6 { orbiters.append(part(.generateSphere(radius: 0.012), glow, at: [0, -0.06, 0])) }
    }
}

/// A drawing brought into the room: a tool held in hand, a character or object beside the trap,
/// or the player's sidekick pet, which stands on the floor and trots after them.
@MainActor
final class HelperRig {
    enum Placement { case hand, beside, pet }

    let creation: Creation
    let root = Entity()
    let placement: Placement
    /// World floor height from the room scan; the pet stands on it.
    var floorY: Float?
    private let body = Entity()
    private let size: Float
    private var time: Float = 0
    private var arrival: Float = 0
    private var action: Float?
    private var placed = false
    private var walking = false
    private var heading: Float = 0

    init(creation: Creation, placement: Placement) throws {
        self.creation = creation
        self.placement = placement
        let model = try Entity.load(contentsOf: creation.modelURL)
        let bounds = model.visualBounds(relativeTo: nil)
        let longest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard longest.isFinite, longest > 0 else { throw PlanError.server("That drawing's 3D model was empty.") }
        switch placement {
        case .hand: size = 0.13
        case .pet: size = creation.card.kind == .character ? 0.26 : 0.2
        case .beside: size = creation.card.kind == .character ? 0.3 : 0.24
        }
        let scale = size / longest
        model.scale = .one * scale
        // Pets stand on the floor, so their feet (the bottom of the model) sit at the body origin.
        model.position = placement == .pet
            ? SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z) * scale
            : -bounds.center * scale
        body.addChild(model)
        root.addChild(body)
        root.name = "Helper-\(creation.id)"
        root.scale = .one * 0.001
        model.generateCollisionShapes(recursive: true)
        switch placement {
        case .hand:
            root.position = [0.1, -0.11, -0.3]
            root.orientation = simd_quatf(angle: -0.35, axis: [0, 0, 1]) * simd_quatf(angle: -0.4, axis: [0, 1, 0])
        case .pet:
            break
        case .beside:
            // To the player's left of the trap, a little closer to them.
            root.position = creation.card.kind == .character ? [-0.36, -0.02, 0.12] : [0.34, -0.04, 0.1]
        }
    }

    var kind: DrawingCard.Kind { creation.card.kind }

    func perform() { action = 0 }

    func update(delta: Float, camera: simd_float4x4) {
        time += delta
        arrival = min(1, arrival + delta / 0.55)
        let cameraPosition = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        // Pop in with a little overshoot; objects beside the trap also drop from above.
        let pop = arrival < 1 ? 1 + sin(arrival * .pi) * 0.25 : 1
        root.scale = .one * max(0.001, min(arrival * 1.6, 1) * pop)
        var offset = SIMD3<Float>(0, 0, 0)
        var tilt = simd_quatf(angle: 0, axis: [0, 1, 0])
        switch placement {
        case .hand:
            offset.y = sin(time * 2) * 0.004
        case .pet:
            follow(cameraPosition, forward: -SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z), delta: delta)
            offset.y = walking ? abs(sin(time * 9)) * 0.05 : abs(sin(time * 2.4)) * 0.012
            tilt = simd_quatf(angle: walking ? sin(time * 9) * 0.12 : 0, axis: [0, 0, 1])
        case .beside:
            if kind == .object { offset.y = max(0, (1 - arrival) * 0.6) }
            else { offset.y = abs(sin(time * 3)) * 0.02 }
        }
        if let elapsed = action {
            let t = elapsed / 0.4
            let swing = sin(min(t, 1) * .pi)
            switch placement {
            case .hand:
                tilt = simd_quatf(angle: -1.1 * swing, axis: [1, 0, 0]) * tilt
                offset.z -= 0.07 * swing
            case .beside:
                // Lunge toward the trap at the anchor's origin, then hop back.
                offset += -root.position * 0.55 * swing
                offset.y += 0.05 * swing
            case .pet:
                offset.y += 0.12 * swing
                tilt = simd_quatf(angle: swing * 2 * .pi, axis: [0, 1, 0]) * tilt
            }
            action = t >= 1 ? nil : elapsed + delta
        }
        body.position = offset
        body.orientation = tilt
        if placement == .beside {
            // Face the player, staying upright.
            let local = root.convert(position: cameraPosition, from: nil) - body.position
            if simd_length(SIMD2(local.x, local.z)) > 0.01 {
                body.orientation = simd_quatf(angle: atan2(local.x, local.z), axis: [0, 1, 0]) * tilt
            }
        }
    }

    /// Keeps the pet on the floor about a meter ahead and to the left of the player.
    private func follow(_ camera: SIMD3<Float>, forward: SIMD3<Float>, delta: Float) {
        var ahead = SIMD3<Float>(forward.x, 0, forward.z)
        if simd_length(ahead) < 0.1 { ahead = [0, 0, -1] }
        ahead = simd_normalize(ahead)
        let left = SIMD3<Float>(ahead.z, 0, -ahead.x)
        let floor = floorY ?? camera.y - 1.35
        var goal = camera + ahead * 0.95 + left * 0.35
        goal.y = floor
        var here = root.position
        let away = SIMD2(goal.x - here.x, goal.z - here.z)
        let distance = simd_length(away)
        if !placed || distance > 4 {
            // First appearance, or the player teleported across the room: just be there.
            here = goal
            placed = true
            walking = false
        } else if distance > (walking ? 0.12 : 0.45) {
            // Trot over once the player has wandered off, then settle.
            walking = true
            let step = min(distance, max(0.9, distance * 1.4) * delta)
            here.x += away.x / distance * step
            here.z += away.y / distance * step
            heading = atan2(away.x, away.y)
        } else {
            walking = false
        }
        here.y += (floor - here.y) * min(1, delta * 6)
        root.position = here
        if !walking {
            // Idle pets look up at the player.
            let look = SIMD2(camera.x - here.x, camera.z - here.z)
            if simd_length(look) > 0.05 {
                let target = atan2(look.x, look.y)
                heading += remainder(target - heading, 2 * .pi) * min(1, delta * 5)
            }
        }
        root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
    }
}
