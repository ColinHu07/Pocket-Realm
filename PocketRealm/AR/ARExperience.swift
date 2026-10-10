import ARKit
import AVFoundation
import Combine
import CoreImage
import RealityKit
import RoomPlan
import SwiftUI

@MainActor
final class ARExperience: NSObject, ObservableObject, ARSessionDelegate, RoomCaptureSessionDelegate {
    @Published private(set) var started = false
    @Published private(set) var game = Adventure()
    @Published private(set) var trackingReady = false
    @Published private(set) var trackingMessage = "Move slowly and include furniture in your scan."
    @Published private(set) var distance: Float?
    @Published private(set) var issue: String?
    @Published private(set) var cameraDenied = false
    @Published private(set) var interrupted = false
    @Published private(set) var coverage = ScanCoverage()
    @Published private(set) var objectCount = 0
    @Published private(set) var scanInstruction = "Slowly turn all the way around. Include walls, furniture, and the floor."
    @Published private(set) var planningError: String?
    @Published private(set) var plan: EncounterPlan?
    @Published private(set) var proximity = ProximityGate()
    @Published private(set) var selectedCategory = ""
    @Published private(set) var requesting = false
    @Published var serverAddress = UserDefaults.standard.string(forKey: "adventureServer") ?? "" {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "adventureServer") }
    }
    @Published var connectionPresented = false

    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let supported = RoomCaptureSession.isSupported
    private var capture: RoomCaptureSession?
    private var anchor: AnchorEntity?
    private var worldAnchor: ARAnchor?
    private var creature: Entity?
    private var updates: Cancellable?
    private var elapsed: Double = 0
    private var scanStarted: Double = 0
    private var revealTime: Double = 0
    private var lastHUDUpdate: Double = 0
    private var suspended = false
    private var failed = false
    private var scanNeedsRestart = false
    private var generation = UUID()
    private var planTask: Task<Void, Never>?
    private var candidates: [RoomCandidate] = []
    private var spawnTransforms: [String: simd_float4x4] = [:]
    private var cameraPositions: [SIMD3<Float>] = []
    private var photos: [ScanPhoto] = []
    private var photoSectors: Set<Int> = []
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let speech = AVSpeechSynthesizer()

    var phase: Adventure.Phase { game.phase }
    var inReach: Bool { anchor?.isAnchored == true && (distance ?? .infinity) <= 2 }
    var canRetryPlan: Bool { !candidates.isEmpty && !requesting }
    var addressIsValid: Bool { (try? AdventureClient.endpoint(serverAddress)) != nil }

    override init() {
        super.init()
        arView.session.delegate = self
        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            Task { @MainActor [weak self] in self?.tick(event.deltaTime) }
        }
    }

    func start() {
        guard supported else { issue = "Room scanning needs a LiDAR-equipped iPhone Pro or iPad Pro. Run on your iPhone instead of the simulator."; return }
        guard addressIsValid else { connectionPresented = true; return }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                cameraDenied = true
                issue = "Allow camera access in Settings to scan your room."
                return
            }
            cameraDenied = false
            started = true
            rescan()
        }
    }

    private func configure(reset: Bool) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func rescan() {
        generation = UUID()
        planTask?.cancel()
        planTask = nil
        capture?.delegate = nil
        capture?.stop(pauseARSession: false)
        capture = nil
        speech.stopSpeaking(at: .immediate)
        if let anchor { arView.scene.removeAnchor(anchor) }
        if let worldAnchor { arView.session.remove(anchor: worldAnchor) }
        anchor = nil
        worldAnchor = nil
        creature = nil
        candidates = []
        spawnTransforms = [:]
        cameraPositions = []
        photos = []
        photoSectors = []
        plan = nil
        planningError = nil
        issue = nil
        failed = false
        interrupted = false
        requesting = false
        scanNeedsRestart = false
        distance = nil
        coverage = ScanCoverage()
        proximity = ProximityGate()
        objectCount = 0
        game = Adventure()
        scanStarted = elapsed
        trackingReady = false
        scanInstruction = "Slowly turn all the way around. Include walls, furniture, and the floor."
        configure(reset: true)
        // RoomPlan and gameplay use this exact ARSession and therefore the same coordinate origin.
        let session = RoomCaptureSession(arSession: arView.session)
        capture = session
        session.delegate = self
        session.run(configuration: .init())
    }

    func suspend() {
        guard started else { return }
        suspended = true
        trackingReady = false
        _ = proximity.update(distance: .infinity, timestamp: elapsed, valid: false)
        speech.stopSpeaking(at: .immediate)
        if phase == .scanning {
            scanNeedsRestart = true
            capture?.delegate = nil
            capture?.stop(pauseARSession: false)
        }
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func resume() {
        guard started && suspended else { return }
        suspended = false
        if scanNeedsRestart { rescan(); return }
        trackingMessage = "Look around the scanned room again to restore tracking."
        configure(reset: false)
    }

    private func finishScan() {
        guard phase == .scanning else { return }
        game.finishScan()
        // Never pause/reset the AR session at the scanning-to-gameplay boundary.
        capture?.stop(pauseARSession: false)
    }

    private static func eligible(_ object: CapturedRoom.Object) -> Bool {
        switch object.category {
        case .storage, .refrigerator, .table, .sofa, .chair, .bed: break
        default: return false
        }
        return object.confidence != .low && object.dimensions.x > 0.15 && object.dimensions.z > 0.15
    }

    private func consume(_ room: CapturedRoom) {
        guard let frame = arView.session.currentFrame else { planningError = "Tracking stopped before the scan finished. Scan the room again."; return }
        let camera = position(frame.camera.transform)
        for object in room.objects.filter(Self.eligible).prefix(24) {
            let id = object.identifier.uuidString
            let transform = spawnTransform(for: object, fallbackCamera: camera)
            let point = position(transform)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { continue }
            let category = String(describing: object.category)
            candidates.append(RoomCandidate(id: id, category: category,
                dimensions: [object.dimensions.x, object.dimensions.y, object.dimensions.z],
                position: [point.x, point.y, point.z], distance: horizontalDistance(camera, point)))
            spawnTransforms[id] = transform
        }
        objectCount = candidates.count
        guard !candidates.isEmpty else {
            planningError = "No clear furniture locations yet. Scan again and spend a few seconds looking at a cabinet, table, chair, sofa, or bed."
            return
        }
        requestPlan()
    }

    /// Uses a side observed during the scan, outside the furniture box. Gemini never supplies coordinates.
    private func spawnTransform(for object: CapturedRoom.Object, fallbackCamera: SIMD3<Float>) -> simd_float4x4 {
        let center = position(object.transform)
        let observer = cameraPositions.min(by: { horizontalDistance($0, center) < horizontalDistance($1, center) }) ?? fallbackCamera
        let localCamera = simd_inverse(object.transform) * SIMD4<Float>(observer, 1)
        var direction = SIMD3<Float>(localCamera.x, 0, localCamera.z)
        if simd_length(direction) < 0.01 { direction = [0, 0, 1] }
        direction = simd_normalize(direction)
        let half = object.dimensions / 2
        let tx = half.x / max(abs(direction.x), 0.0001)
        let tz = half.z / max(abs(direction.z), 0.0001)
        var local = direction * min(tx, tz)
        let normal: SIMD3<Float> = tx < tz ? [direction.x >= 0 ? 1 : -1, 0, 0] : [0, 0, direction.z >= 0 ? 1 : -1]
        local += normal * 0.35
        // The spirit floats near the visible furniture face, at an approachable height.
        local.y = min(half.y - 0.1, max(-half.y + 0.15, localCamera.y - 0.65))
        let world = object.transform * SIMD4<Float>(local, 1)
        var facing = observer - SIMD3<Float>(world.x, world.y, world.z)
        facing.y = 0
        if simd_length(facing) < 0.01 { facing = [0, 0, 1] }
        facing = simd_normalize(facing)
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(simd_cross([0, 1, 0], facing), 0)
        transform.columns.2 = SIMD4<Float>(facing, 0)
        transform.columns.3 = world
        return transform
    }

    func requestPlan() {
        guard canRetryPlan, phase == .planning else { return }
        guard addressIsValid else { connectionPresented = true; return }
        requesting = true
        planningError = nil
        let token = generation
        let address = serverAddress
        let input = candidates
        let images = photos
        planTask = Task { [weak self] in
            do {
                let selected = try await AdventureClient.plan(address: address, candidates: input, photos: images)
                guard !Task.isCancelled, let self, self.generation == token, self.phase == .planning else { return }
                self.requesting = false
                self.install(selected)
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.requesting = false
                self.planningError = error.localizedDescription
            }
        }
    }

    private func install(_ selected: EncounterPlan) {
        guard let transform = spawnTransforms[selected.objectID] else { planningError = PlanError.invalidPlan.localizedDescription; return }
        let arAnchor = ARAnchor(name: selected.objectID, transform: transform)
        arView.session.add(anchor: arAnchor)
        let entity = AnchorEntity(anchor: arAnchor)
        // Empty anchor: no marker or animal gives away the location before proximity succeeds.
        arView.scene.addAnchor(entity)
        anchor = entity
        worldAnchor = arAnchor
        plan = selected
        selectedCategory = candidates.first(where: { $0.id == selected.objectID })?.category ?? "furniture"
        proximity = ProximityGate()
        game.acceptPlan()
        photos = []
    }

    private func reveal() {
        guard let anchor, game.reveal(trackingReady: trackingReady, proximitySatisfied: true) else { return }
        let spirit = CreatureFactory.make()
        spirit.scale = .one * 0.01
        anchor.addChild(spirit)
        creature = spirit
        revealTime = elapsed
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func talk() {
        guard game.talk(trackingReady: trackingReady, inReach: inReach) else { return }
        let line = AVSpeechUtterance(string: plan?.greeting ?? "You found me! I'm Pip.")
        line.rate = 0.47
        speech.speak(line)
    }

    func dismissIssue() { issue = nil }
    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> { [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z] }
    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length(SIMD2<Float>(a.x - b.x, a.z - b.z)) }

    private func tick(_ delta: Double) {
        elapsed += min(delta, 0.1)
        if let creature {
            let age = Float(elapsed - revealTime)
            let ease = 1 - pow(1 - min(1, age / 0.7), 3)
            creature.scale = .one * max(0.01, ease)
            creature.position.y = -0.08 * (1 - ease) + sin(age * 2.1) * 0.012
            creature.orientation = simd_quatf(angle: sin(age * 1.4) * 0.12, axis: [0, 1, 0])
        }
        guard elapsed - lastHUDUpdate > 0.15 else { return }
        lastHUDUpdate = elapsed
        guard !suspended, !interrupted, !failed, let frame = arView.session.currentFrame else {
            trackingReady = false
            _ = proximity.update(distance: .infinity, timestamp: elapsed, valid: false)
            return
        }
        switch frame.camera.trackingState {
        case .normal: trackingReady = true; trackingMessage = "Room tracking is ready"
        case .notAvailable: trackingReady = false; trackingMessage = "Camera tracking is unavailable."
        case .limited(let reason):
            trackingReady = false
            switch reason {
            case .excessiveMotion: trackingMessage = "Slow down your phone movement."
            case .insufficientFeatures: trackingMessage = "Aim at a textured, well-lit part of your room."
            case .relocalizing: trackingMessage = "Look around the scanned room to restore tracking."
            default: trackingMessage = "Move your phone slowly to find surfaces."
            }
        }
        if phase == .scanning, trackingReady {
            let forward = -frame.camera.transform.columns.2
            if simd_length(SIMD2<Float>(forward.x, forward.z)) > 0.4 {
                let yaw = atan2(Double(forward.x), Double(forward.z))
                let oldCount = coverage.bins.count
                coverage.observe(yaw: yaw, trackingReady: true)
                if coverage.bins.count > oldCount { cameraPositions.append(position(frame.camera.transform)) }
                capturePhoto(frame, yaw: yaw)
                if coverage.complete, objectCount > 0, elapsed - scanStarted >= 12 { finishScan() }
            }
        }
        if let anchor {
            distance = horizontalDistance(position(frame.camera.transform), anchor.position(relativeTo: nil))
            if phase == .exploring {
                let ready = proximity.update(distance: distance ?? .infinity, timestamp: frame.timestamp,
                    valid: trackingReady && anchor.isAnchored)
                if ready { reveal() }
            }
        }
    }

    private func capturePhoto(_ frame: ARFrame, yaw: Double) {
        let sector = min(5, Int((yaw + .pi) / (2 * .pi) * 6))
        guard !photoSectors.contains(sector) else { return }
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = 640 / max(image.extent.width, image.extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = imageContext.createCGImage(small, from: small.extent),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.65) else { return }
        photos.append(ScanPhoto(jpeg: jpeg.base64EncodedString(), yaw: yaw))
        photoSectors.insert(sector)
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            guard self.capture === session, self.phase == .scanning else { return }
            self.objectCount = room.objects.filter(Self.eligible).count
        }
    }
    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        Task { @MainActor in
            guard self.capture === session, self.phase == .scanning else { return }
            switch instruction {
            case .slowDown: self.scanInstruction = "Slow down so the room scan can catch up."
            case .turnOnLight: self.scanInstruction = "The room is dark. Turn on a light for a clearer scan."
            case .moveCloseToWall: self.scanInstruction = "Move closer and include the furniture along the wall."
            case .moveAwayFromWall: self.scanInstruction = "Take a step back to see more of the room."
            case .lowTexture: self.scanInstruction = "Include furniture and other textured surfaces."
            default: self.scanInstruction = "Slowly turn all the way around. Include walls, furniture, and the floor."
            }
        }
    }
    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        Task { @MainActor in
            guard self.capture === session else { return }
            let token = self.generation
            self.game.finishScan()
            if let error { self.planningError = "Scan interrupted: \(error.localizedDescription) Please scan again."; return }
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)
                guard self.generation == token else { return }
                self.consume(room)
            } catch {
                guard self.generation == token else { return }
                self.planningError = "Couldn't finish the room model. Please scan again."
            }
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.interrupted = true; self.trackingReady = false }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in self.interrupted = false }
    }
    nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.failed = true
            self.trackingReady = false
            self.issue = "AR stopped: \(message) Use Scan again to recover."
        }
    }
}
