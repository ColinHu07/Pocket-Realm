// Compile with RealmFriend.swift, FriendMotion.swift, and CreatureAnimator.swift.
import Foundation
import RealityKit

@main struct ValidateAnimations {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        for friend in RealmFriend.allCases {
            let root = Entity()
            root.addChild(try Entity.load(contentsOf: folder.appendingPathComponent(friend.name + ".usdz")))
            let animator = CreatureAnimator(root: root, friend: friend)
            let labels = ["EyeL", "EyeR", "Mouth", "AppendageL", "AppendageR", "Tail", "Shell"]
            let controls = labels.compactMap { root.findEntity(named: friend.name + "__" + $0) }
            let pivots = controls.map { $0.position(relativeTo: root) }
            precondition(controls.count >= 4)
            for reaction in FriendReaction.allCases {
                // Settle any previous reaction so all six motions run to completion.
                for _ in 0..<40 { animator.update(delta: 0.1) }
                precondition(animator.react(reaction))
                for frame in 0..<240 {
                    animator.update(delta: 1.0/60, speaking: reaction == .chat)
                    if frame.isMultiple(of: 15) {
                        for (control, pivot) in zip(controls, pivots) {
                            let position = control.position(relativeTo: root)
                            precondition(simd_length(position-pivot) < 0.0001, "Detached pivot: \(control.name)")
                            precondition(control.scale.x > 0 && control.scale.y > 0 && control.scale.z > 0)
                        }
                        let size = root.visualBounds(relativeTo: nil).extents
                        precondition(size.x.isFinite && size.y.isFinite && size.z.isFinite)
                        precondition(size.x < 1.2 && size.y < 1.2 && size.z < 1.2, "Exploding animation: \(friend)")
                    }
                }
                precondition(animator.motion.reaction == nil)
                precondition(root.children.filter { $0.name == "PetHeart" || $0.name == "RewardStar" }.allSatisfy { !$0.isEnabled })
            }
            print("\(friend.name): all six reactions complete; \(controls.count) pivots stay attached; particles clean up.")
        }
        print("ALL_FRIEND_ANIMATIONS_VALID")
    }
}
