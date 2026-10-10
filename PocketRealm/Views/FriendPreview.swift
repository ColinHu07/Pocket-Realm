import Combine
import RealityKit
import SwiftUI
import UIKit

struct FriendPreview: View {
    let friend: RealmFriend
    @Environment(\.dismiss) private var dismiss
    @State private var reaction: FriendReaction = .appear
    @State private var command = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let error {
                    ContentUnavailableView("Couldn't load this friend", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    FriendPreviewSurface(friend: friend, reaction: reaction, command: command, error: $error)
                        .frame(minHeight: 260, maxHeight: .infinity)
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
                Text("\(friend.questTitle) · Find a \(friend.itemName) in your room to earn the \(friend.reward) badge.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20).background(Color(red: 0.97, green: 0.96, blue: 0.92))
            .navigationTitle(friend.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func reactionButton(_ label: String, _ symbol: String, _ value: FriendReaction) -> some View {
        Button { reaction = value; command += 1 } label: {
            Label(label, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(.bordered).tint(Color(red: 0.15, green: 0.38, blue: 0.29))
            .accessibilityIdentifier("preview_" + value.rawValue)
    }
}

private struct FriendPreviewSurface: UIViewRepresentable {
    let friend: RealmFriend
    let reaction: FriendReaction
    let command: Int
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.init(red: 0.94, green: 0.93, blue: 0.87, alpha: 1))
        let anchor = AnchorEntity(world: .zero)
        let turntable = Entity(); anchor.addChild(turntable)
        do {
            let creature = try CreatureFactory.make(friend)
            turntable.addChild(creature)
            context.coordinator.animator = CreatureAnimator(root: creature, friend: friend)
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { self.error = message }
        }
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 36
        camera.look(at: [0,0.23,0], from: [0.54,0.37,1.25], relativeTo: nil)
        anchor.addChild(camera)
        let key = DirectionalLight(); key.light.intensity = 1800
        key.look(at: [0,0.2,0], from: [-1,2,2], relativeTo: nil); anchor.addChild(key)
        let fill = DirectionalLight(); fill.light.intensity = 900
        fill.look(at: [0,0.2,0], from: [2,1,-1], relativeTo: nil); anchor.addChild(fill)
        let floor = ModelEntity(mesh: .generatePlane(width: 3, depth: 3),
                                materials: [SimpleMaterial(color: .init(white: 0.85, alpha: 1), roughness: 1, isMetallic: false)])
        floor.position.y = -0.018; anchor.addChild(floor)
        view.scene.addAnchor(anchor)
        context.coordinator.turntable = turntable
        context.coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator = context.coordinator] event in
            Task { @MainActor in
                coordinator?.animator?.update(delta: event.deltaTime, reducedMotion: UIAccessibility.isReduceMotionEnabled)
            }
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pet(_:))))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.turn(_:))))
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        guard context.coordinator.lastCommand != command else { return }
        context.coordinator.lastCommand = command
        if context.coordinator.animator?.react(reaction) == true { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }
    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel(); coordinator.updates = nil
        coordinator.animator = nil; coordinator.turntable = nil
        view.scene.anchors.removeAll()
    }

    @MainActor final class Coordinator: NSObject {
        var animator: CreatureAnimator?
        var turntable: Entity?
        var updates: Cancellable?
        var lastCommand = 0
        private var angle: Float = 0
        @objc func pet(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? ARView, view.entity(at: recognizer.location(in: view)) != nil else { return }
            if animator?.react(.pet) == true { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        @objc func turn(_ recognizer: UIPanGestureRecognizer) {
            let delta = recognizer.translation(in: recognizer.view)
            angle += Float(delta.x) * 0.008
            turntable?.orientation = simd_quatf(angle: angle, axis: [0,1,0])
            recognizer.setTranslation(.zero, in: recognizer.view)
        }
    }
}
