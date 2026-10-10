// Compile with PocketRealm/Core/*.swift and PocketRealm/AR/CreatureAnimator.swift.
import Foundation
import RealityKit

@main struct ValidateAnimations {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        for friend in RealmFriend.allCases {
            let root = Entity()
            root.addChild(try Entity.load(contentsOf: folder.appendingPathComponent(friend.name + ".usdz")))
            let importedBounds = root.visualBounds(relativeTo: root)
            for child in root.children { child.position.y -= importedBounds.min.y }
            let surface = AnchorEntity(world: [1.2, 0.75, -2])
            surface.position = [1.2, 0.75, -2]
            surface.addChild(root)
            let geometry = Array(root.children)
            let animator = CreatureAnimator(root: root, friend: friend, grounded: true)
            let labels = ["EyeL", "EyeR", "Mouth", "AppendageL", "AppendageR", "Tail", "Shell"]
            let controls = labels.compactMap { root.findEntity(named: friend.name + "__" + $0) }
            let pivots = controls.map { $0.position(relativeTo: root) }
            precondition(controls.count >= 4)
            for reaction in FriendReaction.allCases {
                // Settle the previous reaction so every motion runs to completion.
                for _ in 0..<40 { animator.update(delta: 0.1) }
                precondition(animator.react(reaction))
                for frame in 0..<240 {
                    // Walk around the friend, then look away, during each reaction.
                    let angle = Float(frame) / 240 * 2 * .pi
                    let viewer = FriendAttention.View(cameraPosition: [sin(angle), 1.5, cos(angle)], isLooking: frame < 180)
                    animator.update(delta: 1.0/60, speaking: reaction == .chat, viewer: viewer)
                    if frame.isMultiple(of: 15) {
                        for (control, pivot) in zip(controls, pivots) {
                            let position = control.position(relativeTo: root)
                            precondition(simd_length(position-pivot) < 0.0001, "Detached pivot: \(control.name)")
                            precondition(control.scale.x > 0 && control.scale.y > 0 && control.scale.z > 0)
                        }
                        let size = root.visualBounds(relativeTo: nil).extents
                        precondition(size.x.isFinite && size.y.isFinite && size.z.isFinite)
                        precondition(size.x < 1.2 && size.y < 1.2 && size.z < 1.2, "Exploding animation: \(friend)")
                        let bottom = geometry.map { $0.visualBounds(relativeTo: surface).min.y }.min()!
                        precondition(bottom >= SurfacePlacement.supportClearance - 0.0002 && bottom < 0.17,
                                     "Lost surface contact: \(friend) \(reaction), \(bottom)")
                        let orientation = root.orientation
                        // Every reaction must fit at arbitrary viewer headings, not
                        // only along the original placement's forward direction.
                        for heading in 0..<8 {
                            root.orientation = simd_quatf(angle: Float(heading) * .pi / 4, axis: [0,1,0]) * orientation
                            for child in geometry {
                                let b = child.visualBounds(relativeTo: surface)
                                precondition(b.max.y <= SurfacePlacement.bodyHeight, "Insufficient headroom: \(friend)")
                                precondition(max(abs(b.min.x), abs(b.max.x), abs(b.min.z), abs(b.max.z))
                                             <= SurfacePlacement.footprintRadius, "Insufficient footprint: \(friend)")
                            }
                        }
                        root.orientation = orientation
                    }
                }
                precondition(animator.motion.reaction == nil)
                precondition(!animator.attention.isAttentive)
                precondition(root.children.filter { $0.name == "PetHeart" || $0.name == "RewardStar" }.allSatisfy { !$0.isEnabled })
                let idleBottom = geometry.map { $0.visualBounds(relativeTo: surface).min.y }.min()!
                precondition(idleBottom <= SurfacePlacement.supportClearance + 0.0102, "Idle floating above surface: \(friend), \(idleBottom)")
            }
            animator.update(delta: 0, reducedMotion: true)
            let reducedBottom = geometry.map { $0.visualBounds(relativeTo: surface).min.y }.min()!
            precondition(abs(reducedBottom - SurfacePlacement.supportClearance) < 0.0002)
            print("\(friend.name): all \(FriendReaction.allCases.count) reactions complete; \(controls.count) pivots stay attached; surface contact and particle cleanup verified.")
        }
        print("ALL_FRIEND_ANIMATIONS_VALID")
    }
}
