import SceneKit
import SwiftUI
import UIKit

struct FriendPreview: View {
    let friend: RealmFriend
    @Environment(\.dismiss) private var dismiss
    @State private var reaction: FriendReaction = .appear
    @State private var command = 0
    @State private var error: String?
    @State private var practicing = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        if let error {
                            ContentUnavailableView("Couldn't load this friend", systemImage: "exclamationmark.triangle", description: Text(error))
                        } else {
                            FriendPreviewSurface(friend: friend, reaction: reaction, command: command, error: $error)
                                .frame(height: min(320, max(180, geometry.size.height * 0.4)))
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .accessibilityLabel("Animated \(friend.name). Use the reaction buttons below.")
                        }
                        VStack(spacing: 6) {
                            Text(friend.role).font(.headline)
                            Text(friend.personality).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Text("Drag to turn · Tap your friend to pet").font(.caption).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            reactionButton("Say hello", "hand.wave.fill", .greeting)
                            reactionButton("Pet", "heart.fill", .pet)
                            reactionButton("Play", "sparkles", .play)
                            reactionButton("Celebrate", "star.fill", .celebrate)
                        }
                        if QuestBlueprint.first(for: friend) != nil {
                            Button { practicing = true } label: {
                                Label("Try the quest · no camera needed", systemImage: "gamecontroller.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).tint(Color(red: 0.15, green: 0.38, blue: 0.29))
                                .accessibilityIdentifier("practiceQuest")
                        }
                        Text("\(friend.questTitle) · \(QuestBlueprint.first(for: friend) == nil ? "Find a \(friend.itemName)" : "Find a \(friend.itemName), then solve a puzzle together") in your room to earn the \(friend.reward) badge.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(20)
                }.scrollBounceBehavior(.basedOnSize)
            }.background(Color(red: 0.97, green: 0.96, blue: 0.92))
            .navigationTitle(friend.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $practicing) {
                if let blueprint = QuestBlueprint.first(for: friend) { QuestPractice(blueprint: blueprint) }
            }
        }.preferredColorScheme(.light)
    }

    private func reactionButton(_ label: String, _ symbol: String, _ value: FriendReaction) -> some View {
        Button { reaction = value; command += 1 } label: {
            Label(label, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(.bordered).tint(Color(red: 0.15, green: 0.38, blue: 0.29))
            .accessibilityIdentifier("preview_" + value.rawValue)
    }
}

/// Camera-free previews use their own renderer, independent of the room's AR session.
struct FriendPreviewSurface: UIViewRepresentable {
    let friend: RealmFriend
    let reaction: FriendReaction
    let command: Int
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = UIColor(red: 0.94, green: 0.93, blue: 0.87, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.preferredFramesPerSecond = 60

        let turntable = SCNNode()
        scene.rootNode.addChildNode(turntable)
        do {
            guard let url = Bundle.main.url(forResource: friend.rawValue, withExtension: "usdz", subdirectory: "Creatures") else {
                throw PlanError.server("Couldn't find \(friend.name)'s model.")
            }
            let asset = try SCNScene(url: url)
            let creature = SCNNode()
            creature.name = "Friend"
            for child in asset.rootNode.childNodes { creature.addChildNode(child) }
            turntable.addChildNode(creature)
            context.coordinator.animator = PreviewAnimator(root: creature, friend: friend)
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { self.error = message }
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 36
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 10
        camera.position = SCNVector3(0.44, 0.34, 1.05)
        camera.look(at: SCNVector3(0, 0.23, 0))
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.position = SCNVector3(-1, 2, 2)
        key.look(at: SCNVector3(0, 0.2, 0))
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 650
        fill.light?.color = UIColor(white: 0.96, alpha: 1)
        scene.rootNode.addChildNode(fill)

        let floor = SCNNode(geometry: SCNPlane(width: 3, height: 3))
        floor.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        floor.geometry?.firstMaterial?.roughness.contents = 1
        floor.eulerAngles.x = -.pi / 2
        floor.position.y = -0.018
        scene.rootNode.addChildNode(floor)

        context.coordinator.turntable = turntable
        context.coordinator.start()
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pet(_:))))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.turn(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard context.coordinator.lastCommand != command else { return }
        context.coordinator.lastCommand = command
        if context.coordinator.animator?.react(reaction) == true {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
        coordinator.animator = nil
        coordinator.turntable = nil
        view.isPlaying = false
        view.scene = nil
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var animator: PreviewAnimator?
        var turntable: SCNNode?
        var displayLink: CADisplayLink?
        var lastCommand = Int.min
        private var lastTime: CFTimeInterval?
        private var angle: Float = 0

        func start() {
            let link = CADisplayLink(target: self, selector: #selector(update(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func update(_ link: CADisplayLink) {
            let delta = lastTime.map { link.timestamp - $0 } ?? 0
            lastTime = link.timestamp
            animator?.update(delta: delta, reducedMotion: UIAccessibility.isReduceMotionEnabled)
        }

        @objc func pet(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            let touchedFriend = view.hitTest(recognizer.location(in: view)).contains { hit in
                var node: SCNNode? = hit.node
                while let current = node {
                    if current === turntable { return true }
                    node = current.parent
                }
                return false
            }
            if touchedFriend, animator?.react(.pet) == true {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func turn(_ recognizer: UIPanGestureRecognizer) {
            angle += Float(recognizer.translation(in: recognizer.view).x) * 0.008
            turntable?.simdOrientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            recognizer.setTranslation(.zero, in: recognizer.view)
        }
    }
}

/// Uses the same pose sampler and named model controls as CreatureAnimator in AR.
@MainActor final class PreviewAnimator {
    private let root: SCNNode
    private let friend: RealmFriend
    private var motion: FriendMotion
    private struct Control {
        let node: SCNNode
        let scale: SIMD3<Float>
        let rotation: simd_quatf
    }
    private var controls: [String: Control] = [:]
    private var hearts: [SCNNode] = []
    private var stars: [SCNNode] = []
    private let height: Float

    init(root: SCNNode, friend: RealmFriend) {
        self.root = root
        self.friend = friend
        motion = FriendMotion(friend: friend)
        height = root.boundingBox.max.y
        for name in ["EyeL", "EyeR", "Mouth", "AppendageL", "AppendageR", "Tail", "Shell"] {
            if let node = root.childNode(withName: friend.name + "__" + name, recursively: true) {
                controls[name] = Control(node: node, scale: node.simdScale, rotation: node.simdOrientation)
            }
        }
        for isHeart in [true, false] {
            let geometry = Self.symbolGeometry(heart: isHeart)
            for _ in 0..<7 {
                let particle = SCNNode(geometry: geometry)
                particle.isHidden = true
                root.addChildNode(particle)
                if isHeart { hearts.append(particle) } else { stars.append(particle) }
            }
        }
    }

    @discardableResult func react(_ reaction: FriendReaction) -> Bool { motion.trigger(reaction) }

    func update(delta: Double, reducedMotion: Bool) {
        let pose = motion.update(delta: delta, reducedMotion: reducedMotion)
        root.simdScale = pose.scale
        root.simdPosition = pose.position
        root.simdOrientation = simd_quatf(angle: pose.rotation.y, axis: [0, 1, 0])
            * simd_quatf(angle: pose.rotation.x, axis: [1, 0, 0])
            * simd_quatf(angle: pose.rotation.z, axis: [0, 0, 1])
        for (name, control) in controls {
            var scale = control.scale
            var rotation = control.rotation
            switch name {
            case "EyeL", "EyeR": scale.y *= max(0.06, pose.eyes)
            case "Mouth": scale.x *= 1 + (pose.mouth - 1) * 0.25; scale.y *= pose.mouth
            case "AppendageL", "AppendageR":
                let side: Float = name == "AppendageL" ? -1 : 1
                rotation *= simd_quatf(angle: pose.appendage * side, axis: friend == .glimlo ? [0, 1, 0] : [0, 0, 1])
                if friend == .nibbi { rotation *= simd_quatf(angle: pose.appendage * 0.4, axis: [1, 0, 0]) }
            case "Tail": rotation *= simd_quatf(angle: pose.tail, axis: [0, 1, 0])
            case "Shell": rotation *= simd_quatf(angle: pose.tail * (friend == .trufflet ? 0.65 : 0.15), axis: [0, 0, 1])
            default: break
            }
            control.node.simdScale = scale
            control.node.simdOrientation = rotation
        }
        for (isHeart, particles) in [(true, hearts), (false, stars)] {
            let enabled = !reducedMotion && pose.effect > 0 && motion.reaction == (isHeart ? .pet : .celebrate)
            for (index, particle) in particles.enumerated() {
                let progress = (pose.effectProgress - Float(index) * 0.045) / 0.72
                particle.isHidden = !enabled || progress <= 0 || progress >= 1
                guard !particle.isHidden else { continue }
                let angle = Float(index) * 2 * .pi / Float(particles.count)
                let spread: Float = isHeart ? 0.13 : 0.23
                particle.simdPosition = [cos(angle) * spread * (0.5 + progress),
                    height * 0.75 + progress * 0.22 + sin(angle) * 0.055, 0.14 + sin(angle) * 0.06]
                particle.simdScale = .one * max(0.001, sin(progress * .pi) * (isHeart ? 0.020 : 0.016))
                particle.simdOrientation = simd_quatf(angle: sin(progress * 5 + angle) * 0.25, axis: [0, 0, 1])
            }
        }
    }

    private static func symbolGeometry(heart: Bool) -> SCNGeometry {
        let path = UIBezierPath()
        let count = heart ? 40 : 10
        for index in 0..<count {
            let t = CGFloat(index) * 2 * .pi / CGFloat(count)
            let radius: CGFloat = index.isMultiple(of: 2) ? 1 : 0.46
            let point = heart
                ? CGPoint(x: pow(sin(t), 3), y: (13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t))/16)
                : CGPoint(x: sin(t) * radius, y: cos(t) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.001)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = heart
            ? UIColor(red: 1, green: 0.49, blue: 0.61, alpha: 1)
            : UIColor(red: 1, green: 0.83, blue: 0.32, alpha: 1)
        material.isDoubleSided = true
        shape.materials = [material]
        return shape
    }
}
