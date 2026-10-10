import Foundation
import RealityKit
import simd

/// Shared by the live encounter and the no-camera character preview.
@MainActor
final class CreatureAnimator {
    let root: Entity
    let friend: RealmFriend
    private(set) var motion: FriendMotion
    private struct Control {
        let entity: Entity
        let rest: Transform
    }
    private var controls: [String: Control] = [:]
    private var hearts: [ModelEntity] = []
    private var stars: [ModelEntity] = []
    private let height: Float
    private let grounded: Bool
    private let visualChildren: [Entity]

    init(root: Entity, friend: RealmFriend, grounded: Bool = false) {
        self.root = root
        self.friend = friend
        self.grounded = grounded
        // Capture only the character geometry, before adding hearts and stars.
        visualChildren = Array(root.children)
        motion = FriendMotion(friend: friend)
        height = root.visualBounds(relativeTo: root).max.y
        for name in ["EyeL", "EyeR", "Mouth", "AppendageL", "AppendageR", "Tail", "Shell"] {
            if let entity = root.findEntity(named: friend.name + "__" + name) {
                controls[name] = Control(entity: entity, rest: entity.transform)
            }
        }
        for isHeart in [true, false] {
            let mesh = Self.symbolMesh(heart: isHeart)
            let material = UnlitMaterial(color: isHeart
                ? .init(red: 1, green: 0.49, blue: 0.61, alpha: 1)
                : .init(red: 1, green: 0.83, blue: 0.32, alpha: 1))
            for _ in 0..<7 {
                let particle = ModelEntity(mesh: mesh, materials: [material])
                particle.name = isHeart ? "PetHeart" : "RewardStar"
                particle.isEnabled = false
                particle.scale = .one * 0.001
                root.addChild(particle)
                if isHeart { hearts.append(particle) } else { stars.append(particle) }
            }
        }
    }

    @discardableResult func react(_ reaction: FriendReaction) -> Bool { motion.trigger(reaction) }

    func update(delta: Double, speaking: Bool = false, reducedMotion: Bool = false) {
        let pose = motion.update(delta: delta, speaking: speaking, reducedMotion: reducedMotion)
        root.transform = Transform(scale: pose.scale,
            rotation: simd_quatf(angle: pose.rotation.y, axis: [0,1,0])
                * simd_quatf(angle: pose.rotation.x, axis: [1,0,0])
                * simd_quatf(angle: pose.rotation.z, axis: [0,0,1]), translation: pose.position)
        for (name, control) in controls {
            var transform = control.rest
            switch name {
            case "EyeL", "EyeR": transform.scale.y *= max(0.06, pose.eyes)
            case "Mouth":
                transform.scale.x *= 1 + (pose.mouth - 1) * 0.25
                transform.scale.y *= pose.mouth
            case "AppendageL", "AppendageR":
                let side: Float = name == "AppendageL" ? -1 : 1
                let axis: SIMD3<Float> = friend == .glimlo ? [0,1,0] : [0,0,1]
                transform.rotation *= simd_quatf(angle: pose.appendage * side, axis: axis)
                if friend == .nibbi { transform.rotation *= simd_quatf(angle: pose.appendage * 0.4, axis: [1,0,0]) }
            case "Tail": transform.rotation *= simd_quatf(angle: pose.tail, axis: [0,1,0])
            case "Shell": transform.rotation *= simd_quatf(angle: pose.tail * (friend == .trufflet ? 0.65 : 0.15), axis: [0,0,1])
            default: break
            }
            control.entity.transform = transform
        }
        if grounded, let lowest = visualChildren.map({ $0.visualBounds(relativeTo: root.parent).min.y }).min(),
           lowest.isFinite {
            // Squashes and tilts change the bottom of the model. Keep it on the
            // support while preserving intentional upward hops; particles cannot lift it.
            root.position.y += SurfacePlacement.supportClearance + max(0, pose.position.y) - lowest
        }
        for (isHeart, particles) in [(true, hearts), (false, stars)] {
            let enabled = !reducedMotion && pose.effect > 0 && motion.reaction == (isHeart ? .pet : .celebrate)
            for (index, particle) in particles.enumerated() {
                let progress = (pose.effectProgress - Float(index) * 0.045) / 0.72
                particle.isEnabled = enabled && progress > 0 && progress < 1
                guard particle.isEnabled else { continue }
                let angle = Float(index) * 2 * .pi / Float(particles.count)
                let spread: Float = isHeart ? 0.13 : 0.23
                particle.position = [cos(angle) * spread * (0.5+progress),
                                     height * 0.75 + progress * 0.22 + sin(angle) * 0.055,
                                     0.14 + sin(angle) * 0.06]
                particle.scale = .one * max(0.001, sin(progress * .pi) * (isHeart ? 0.020 : 0.016))
                particle.orientation = simd_quatf(angle: sin(progress * 5 + angle) * 0.25, axis: [0,0,1])
            }
        }
    }

    private static func symbolMesh(heart: Bool) -> MeshResource {
        let count = heart ? 40 : 10
        var positions: [SIMD3<Float>] = [.zero]
        for index in 0..<count {
            let t = Float(index) * 2 * .pi / Float(count)
            if heart {
                positions.append([pow(sin(t),3), (13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t))/16, 0])
            } else {
                let radius: Float = index.isMultiple(of: 2) ? 1 : 0.46
                positions.append([sin(t)*radius, cos(t)*radius, 0])
            }
        }
        var indices: [UInt32] = []
        for index in 0..<count { indices += [0, UInt32((index+1)%count+1), UInt32(index+1)] }
        var mesh = MeshDescriptor(name: heart ? "Heart" : "Star")
        mesh.positions = MeshBuffers.Positions(positions)
        mesh.normals = MeshBuffers.Normals(Array(repeating: [0,0,1], count: positions.count))
        mesh.primitives = .triangles(indices)
        // These constant, local polygons are valid; a sphere keeps reactions available if an OS rejects a mesh.
        return (try? MeshResource.generate(from: [mesh])) ?? .generateSphere(radius: 0.7)
    }
}
