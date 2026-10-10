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
    @Published var serverAddress = ARExperience.initialServerAddress() {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "adventureServer") }
    }

    /// A build that ships a new default server replaces the address saved from an older build;
    /// otherwise the user's own saved address wins.
    private static func initialServerAddress() -> String {
        let defaults = UserDefaults.standard
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "AdventureServerDefault") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        if !bundled.isEmpty, !bundled.hasPrefix("$("), defaults.string(forKey: "adventureServerDefault") != bundled {
            defaults.set(bundled, forKey: "adventureServerDefault")
            defaults.set(bundled, forKey: "adventureServer")
        }
        return defaults.string(forKey: "adventureServer").flatMap { $0.isEmpty ? nil : $0 } ?? ""
    }
    @Published var connectionPresented = false
    @Published var themePresented = false
    @Published private(set) var theme = RealmTheme(rawValue: UserDefaults.standard.string(forKey: "realmTheme") ?? "") ?? .original
    @Published private(set) var themeMessage = "Choose a look for your room."
    @Published private(set) var friend: RealmFriend = .mosskip
    @Published private(set) var questCategory = ""
    @Published private(set) var questDistance: Float?
    @Published private(set) var dialogue: String?
    @Published private(set) var completedFriends: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "realmFriendships") ?? [])
    // Sketch quests: drawings become a sidekick, and helpers that clear traps.
    @Published private(set) var sidekickDrawing = DrawingProgress.none
    @Published private(set) var sidekickPhoto: UIImage?
    @Published private(set) var challengeDrawing = DrawingProgress.none
    @Published private(set) var challengePhoto: UIImage?
    @Published private(set) var inventory: [Creation] = Inventory.load()
    @Published private(set) var sidekick: Creation?
    @Published private(set) var challenge: Challenge?
    @Published private(set) var trapProgress: TrapProgress?
    @Published private(set) var helper: Creation?
    @Published private(set) var whimsy = 0
    @Published var drawingPresented = false
    @Published private(set) var drawingPurpose = DrawingPurpose.sidekick
    /// Dev shortcut: relocalizing against the last saved room instead of scanning.
    @Published private(set) var restoringRoom = false
    @Published private(set) var savedRoomDate = DevRoom.savedDate

    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let supported = RoomCaptureSession.isSupported
    private var capture: RoomCaptureSession?
    private var anchor: AnchorEntity?
    private var worldAnchor: ARAnchor?
    private var creature: Entity?
    private var creatureAnimator: CreatureAnimator?
    private var preparedCreature: Entity?
    private var questAnchor: AnchorEntity?
    private var questWorldAnchor: ARAnchor?
    private var keepsake: Entity?
    private var themeRoom: CapturedRoom?
    private var roomContext: RoomScanContext?
    private var themeObserver: SIMD3<Float> = .zero
    private var jungle: ThemeFactory.Result?
    private var updates: Cancellable?
    private var elapsed: Double = 0
    private var scanStarted: Double = 0
    private var lastHUDUpdate: Double = 0
    private var suspended = false
    private var failed = false
    private var scanNeedsRestart = false
    private var generation = UUID()
    private var planTask: Task<Void, Never>?
    private var drawingTasks: [DrawingPurpose: Task<Void, Never>] = [:]
    private let cameraAnchor = AnchorEntity(.camera)
    /// World-space parent for the sidekick pet, which walks around the room on its own.
    private let petAnchor = AnchorEntity(world: .zero)
    private var trapRig: TrapRig?
    private var helperRig: HelperRig?
    private var sidekickRig: HelperRig?
    private var helperIsFresh = false
    private var helperLine = 0
    private var sidekickLine = 0
    private var keepsakeLift: Float = 0
    private var lastWhimsy: Double = 0
    private var pendingRoom: DevRoom?
    private var candidates: [RoomCandidate] = []
    private var spawnTransforms: [String: simd_float4x4] = [:]
    private var cameraPositions: [SIMD3<Float>] = []
    private var photos: [ScanPhoto] = []
    private var photoSectors: Set<Int> = []
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let speech = AVSpeechSynthesizer()

    var phase: Adventure.Phase { game.phase }
    var inReach: Bool { anchor?.isAnchored == true && (distance ?? .infinity) <= 2 }
    var itemInReach: Bool { questAnchor?.isAnchored == true && (questDistance ?? .infinity) <= 1.3 }
    var objectiveDistance: Float? { phase == .questing ? questDistance : distance }
    var canRetryPlan: Bool { !candidates.isEmpty && roomContext != nil && !photos.isEmpty && !requesting }
    var addressIsValid: Bool { (try? AdventureClient.endpoint(serverAddress)) != nil }
    var questRequest: String {
        guard let challenge else { return friend.questRequest }
        return "\(challenge.cleared) Pick up the \(friend.itemName) and bring it back to \(friend.name)."
    }
    var helperName: String { helper?.card.displayName ?? "your drawing" }

    override init() {
        super.init()
        arView.session.delegate = self
        arView.scene.addAnchor(cameraAnchor)
        arView.scene.addAnchor(petAnchor)
        if let id = UserDefaults.standard.string(forKey: "sidekick") { sidekick = inventory.first { $0.id == id } }
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapFriend(_:))))
        applyTheme()
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

    private func configure(reset: Bool, worldMap: ARWorldMap? = nil) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.initialWorldMap = worldMap
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func rescan() {
        resetRoom()
        configure(reset: true)
        // RoomPlan and gameplay use this exact ARSession and therefore the same coordinate origin.
        let session = RoomCaptureSession(arSession: arView.session)
        capture = session
        session.delegate = self
        session.run(configuration: .init())
    }

    /// Dev shortcut: relocalize in the last scanned room and reuse its saved Gemini plan.
    func startFromSavedRoom() {
        guard supported else { issue = "Room scanning needs a LiDAR-equipped iPhone Pro or iPad Pro."; return }
        let saved: (room: DevRoom, worldMap: ARWorldMap)
        do { saved = try DevRoom.load() } catch {
            issue = "No saved room yet. Do one normal scan first; it's saved automatically."
            savedRoomDate = nil
            return
        }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                cameraDenied = true
                issue = "Allow camera access in Settings to scan your room."
                return
            }
            if let friend = RealmFriend(rawValue: saved.room.friend), !started { self.friend = friend }
            started = true
            resetRoom()
            restoringRoom = true
            pendingRoom = saved.room
            configure(reset: true, worldMap: saved.worldMap)
        }
    }

    private func applySavedRoom(_ saved: DevRoom) {
        pendingRoom = nil
        restoringRoom = false
        candidates = saved.candidates
        spawnTransforms = DevRoom.decode(saved.spawnTransforms)
        roomContext = saved.context
        themeRoom = saved.room
        themeObserver = saved.observer
        objectCount = candidates.count
        game.finishScan()
        install(saved.plan, save: false)
    }

    private func saveRoomForDev(_ plan: EncounterPlan) {
        guard let context = roomContext, let room = themeRoom else { return }
        let snapshot = DevRoom(plan: plan, candidates: candidates, spawnTransforms: DevRoom.encode(spawnTransforms),
                               context: context, room: room, observer: themeObserver, friend: friend.rawValue, saved: Date())
        arView.session.getCurrentWorldMap { [weak self] map, _ in
            guard let map else { return }
            Task { @MainActor in
                guard (try? DevRoom.save(snapshot, worldMap: map)) != nil else { return }
                self?.savedRoomDate = snapshot.saved
            }
        }
    }

    private func resetRoom() {
        generation = UUID()
        planTask?.cancel()
        planTask = nil
        capture?.delegate = nil
        capture?.stop(pauseARSession: false)
        capture = nil
        speech.stopSpeaking(at: .immediate)
        if let anchor { arView.scene.removeAnchor(anchor) }
        if let worldAnchor { arView.session.remove(anchor: worldAnchor) }
        clearQuest()
        clearTheme()
        preparedCreature = nil
        dialogue = nil
        creatureAnimator = nil
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
        restoringRoom = false
        pendingRoom = nil
        scanInstruction = "Slowly turn all the way around. Include walls, furniture, and the floor."
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
        if scanNeedsRestart, !restoringRoom { rescan(); return }
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
        themeRoom = room
        themeObserver = camera
        let context = ThemeFactory.context(for: room)
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
        guard context.surfaces.contains(where: { $0.kind == .floor || $0.kind == .wall }), !photos.isEmpty else {
            planningError = "The scan needs clearer room surfaces and snapshots. Scan again, including the floor and walls."
            return
        }
        roomContext = context
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
        guard canRetryPlan, phase == .planning, let context = roomContext else { return }
        guard addressIsValid else { connectionPresented = true; return }
        requesting = true
        planningError = nil
        let token = generation
        let address = serverAddress
        let input = candidates
        let images = photos
        let selectedFriend = friend
        planTask = Task { [weak self] in
            do {
                let selected = try await AdventureClient.plan(address: address, candidates: input, photos: images, friend: selectedFriend, context: context)
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

    private func install(_ selected: EncounterPlan, save: Bool = true) {
        guard spawnTransforms[selected.objectID] != nil, let room = selected.room,
              spawnTransforms[room.keepsakeObjectID] != nil else {
            planningError = PlanError.invalidPlan.localizedDescription
            return
        }
        plan = selected
        selectedCategory = candidates.first(where: { $0.id == selected.objectID })?.category ?? "furniture"
        applyTheme()
        game.acceptPlan()
        photos = []
        if save { saveRoomForDev(selected) }
    }

    func beginExploring() {
        guard phase == .ready, trackingReady, let plan, let room = plan.room,
              let transform = spawnTransforms[plan.objectID] else { return }
        do { preparedCreature = try CreatureFactory.make(friend) }
        catch { issue = "Couldn't load \(friend.name): \(error.localizedDescription)"; return }
        let arAnchor = ARAnchor(name: plan.objectID, transform: transform)
        arView.session.add(anchor: arAnchor)
        let entity = AnchorEntity(anchor: arAnchor)
        // Empty anchor: no marker or animal gives away the location before proximity succeeds.
        arView.scene.addAnchor(entity)
        anchor = entity
        worldAnchor = arAnchor
        prepareQuest(friendID: plan.objectID, keepsakeID: room.keepsakeObjectID)
        proximity = ProximityGate()
        game.beginExploring()
        showSidekick(announce: true)
    }

    private func reveal() {
        guard let anchor, let spirit = preparedCreature,
              game.reveal(trackingReady: trackingReady, proximitySatisfied: true) else { return }
        preparedCreature = nil
        spirit.scale = .one * 0.01
        anchor.addChild(spirit)
        creature = spirit
        creatureAnimator = CreatureAnimator(root: spirit, friend: friend)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func selectFriend(_ selected: RealmFriend) {
        guard !started else { return }
        friend = selected
    }

    func selectTheme(_ selected: RealmTheme) {
        theme = selected
        UserDefaults.standard.set(selected.rawValue, forKey: "realmTheme")
        applyTheme()
    }

    private func applyTheme() {
        if let jungle { arView.scene.removeAnchor(jungle.anchor) }
        arView.environment.sceneUnderstanding.options.remove(.occlusion)
        guard theme == .jungle else {
            themeMessage = "Your room, just as it is."
            return
        }
        guard let themeRoom, let understanding = plan?.room else {
            themeMessage = "Gemini will plan your Jungle after the 360° scan. Include the floor and walls."
            return
        }
        do {
            if jungle == nil {
                let questPositions = [plan?.objectID, understanding.keepsakeObjectID].compactMap { id -> SIMD3<Float>? in
                    guard let id, let transform = spawnTransforms[id] else { return nil }
                    return position(transform)
                }
                jungle = try ThemeFactory.jungle(in: themeRoom, observer: themeObserver,
                    plan: understanding.jungle, questPositions: questPositions)
            }
            if let jungle {
                if jungle.hasContent {
                    arView.environment.sceneUnderstanding.options.insert(.occlusion)
                    arView.scene.addAnchor(jungle.anchor)
                }
                themeMessage = jungle.message
            }
        } catch {
            themeMessage = "Couldn't grow the jungle. Select Jungle to try again, or scan the room again."
        }
    }

    private func clearTheme() {
        if let jungle { arView.scene.removeAnchor(jungle.anchor) }
        jungle = nil
        themeRoom = nil
        roomContext = nil
        arView.environment.sceneUnderstanding.options.remove(.occlusion)
        themeMessage = theme == .jungle ? "Gemini will plan your Jungle after the 360° scan. Include the floor and walls." : "Your room, just as it is."
    }

    private func prepareQuest(friendID: String, keepsakeID: String) {
        guard let location = candidates.first(where: { $0.id == keepsakeID }),
              var transform = spawnTransforms[location.id] else { return }
        // Reuse a scanned, observed furniture face, never a guessed point behind furniture.
        // In a one-location room the item floats just above the friend, reachable in place.
        transform.columns.3.y += location.id == friendID ? 0.6 : 0.25
        let arAnchor = ARAnchor(name: "keepsake", transform: transform)
        arView.session.add(anchor: arAnchor)
        let entity = AnchorEntity(anchor: arAnchor)
        arView.scene.addAnchor(entity)
        questWorldAnchor = arAnchor
        questAnchor = entity
        questCategory = location.category == "storage" ? "cabinet" : location.category
    }

    private func clearQuest() {
        helperRig?.root.removeFromParent()
        helperRig = nil
        trapRig = nil
        helper = nil
        trapProgress = nil
        challenge = nil
        keepsakeLift = 0
        drawingTasks[.challenge]?.cancel()
        challengeDrawing = .none
        challengePhoto = nil
        if let questAnchor { arView.scene.removeAnchor(questAnchor) }
        if let questWorldAnchor { arView.session.remove(anchor: questWorldAnchor) }
        questAnchor = nil
        questWorldAnchor = nil
        keepsake = nil
        questDistance = nil
        questCategory = ""
    }

    func talk() {
        guard let questAnchor, game.talk(trackingReady: trackingReady, inReach: inReach) else { return }
        let item = CreatureFactory.keepsake(friend)
        questAnchor.addChild(item)
        keepsake = item
        let trap = Challenge.pick(seed: Int.random(in: 0..<6_000), item: friend.itemName, place: questCategory)
        let rig = TrapRig(challenge: trap, accent: CreatureFactory.color(friend))
        questAnchor.addChild(rig.root)
        trapRig = rig
        challenge = trap
        keepsakeLift = rig.keepsakeLift
        item.isEnabled = !rig.hidesKeepsake
        speak((plan?.greeting ?? "Hi! I'm \(friend.name).") + " " + trap.plea)
        creatureAnimator?.react(.greeting)
    }

    // MARK: Sketch quests: paper drawing → Codex + Blender → something in the game

    func openDrawing(_ purpose: DrawingPurpose) {
        drawingPurpose = purpose
        drawingPresented = true
    }

    var drawingTitle: String {
        drawingPurpose == .challenge ? (challenge?.title ?? "Draw a solution") : "Draw a sidekick"
    }

    var drawingPrompt: String {
        drawingPurpose == .challenge ? (challenge?.prompt ?? "Draw something to help.")
            : "Draw anyone or anything to bring on your adventure with \(friend.name): a creature, a robot, a teapot, a cloud with opinions…"
    }

    func submitDrawing(_ image: UIImage) {
        let purpose = drawingPurpose
        drawingTasks[purpose]?.cancel()
        setDrawing(.uploading, photo: image, for: purpose)
        guard let jpeg = DrawingWorkshop.jpeg(from: image) else {
            setDrawing(.failed("Couldn't read that photo. Try again."), for: purpose)
            return
        }
        guard addressIsValid else { setDrawing(.failed(PlanError.invalidURL.localizedDescription), for: purpose); return }
        let address = serverAddress
        let friendName = friend.name
        let context = purpose == .challenge ? challenge?.codexContext : nil
        drawingTasks[purpose] = Task { [weak self] in
            do {
                var status = try await DrawingWorkshop.submit(address: address, jpeg: jpeg, purpose: purpose,
                                                              challenge: context, friend: friendName)
                var misses = 0
                let deadline = Date().addingTimeInterval(15 * 60)
                while !Task.isCancelled {
                    if status.status == "ready" {
                        let model = try await DrawingWorkshop.download(address: address, id: status.id)
                        guard !Task.isCancelled, let self else { return }
                        let card = status.card ?? DrawingCard(name: status.name ?? "drawing", kind: .object)
                        self.inventory = try Inventory.add(id: status.id, card: card, model: model, photo: image, to: self.inventory)
                        self.setDrawing(.ready(name: card.name), for: purpose)
                        if let creation = self.inventory.first { self.arrived(creation, for: purpose) }
                        return
                    }
                    self?.setDrawing(DrawingProgress(status), for: purpose)
                    if status.status == "failed" { return }
                    guard Date() < deadline else { throw PlanError.server("Your drawing took too long. Try again.") }
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    do {
                        status = try await DrawingWorkshop.status(address: address, id: status.id)
                        misses = 0
                    } catch is CancellationError {
                        return
                    } catch {
                        // Ride out brief network drops while walking around the room.
                        misses += 1
                        if misses >= 10 { throw error }
                    }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.setDrawing(.failed(error.localizedDescription), for: purpose)
            }
        }
    }

    private func setDrawing(_ progress: DrawingProgress, photo: UIImage? = nil, for purpose: DrawingPurpose) {
        switch purpose {
        case .sidekick:
            sidekickDrawing = progress
            if let photo { sidekickPhoto = photo }
        case .challenge:
            challengeDrawing = progress
            if let photo { challengePhoto = photo }
        }
    }

    private func arrived(_ creation: Creation, for purpose: DrawingPurpose) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        switch purpose {
        case .sidekick: chooseSidekick(creation)
        case .challenge: deployHelper(creation, fresh: true)
        }
    }

    /// Photographs paper held up to the AR camera without interrupting room tracking.
    /// `guide` is in the AR view's coordinates (the full screen).
    func captureDrawingFrame(guide: CGRect) -> UIImage? {
        guard let frame = arView.session.currentFrame else { return nil }
        let view = arView.bounds.size
        guard view.width > 0, view.height > 0 else { return nil }
        let padded = guide.insetBy(dx: -guide.width * 0.06, dy: -guide.height * 0.06)
        let normalizedView = CGRect(x: padded.minX / view.width, y: padded.minY / view.height,
                                    width: padded.width / view.width, height: padded.height / view.height)
        // displayTransform maps normalized camera-image coordinates (top-left origin) to the screen.
        let toImage = frame.displayTransform(for: .portrait, viewportSize: view).inverted()
        let region = normalizedView.applying(toImage).standardized
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let size = image.extent.size
        let crop = CGRect(x: region.minX * size.width, y: (1 - region.maxY) * size.height,
                          width: region.width * size.width, height: region.height * size.height)
            .intersection(image.extent)
        guard !crop.isEmpty, let cg = imageContext.createCGImage(image.cropped(to: crop).oriented(.right),
                                                                 from: image.cropped(to: crop).oriented(.right).extent) else { return nil }
        let upright = UIImage(cgImage: cg)
        return DrawingCamera.straighten(upright) ?? upright
    }

    func chooseSidekick(_ creation: Creation) {
        sidekick = creation
        UserDefaults.standard.set(creation.id, forKey: "sidekick")
        showSidekick(announce: started)
    }

    /// The sidekick floats beside the camera for the whole adventure.
    private func showSidekick(announce: Bool) {
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
        guard started, let sidekick, let rig = try? HelperRig(creation: sidekick, placement: .pet) else { return }
        rig.floorY = floorHeight
        petAnchor.addChild(rig.root)
        sidekickRig = rig
        if announce, !speech.isSpeaking { speak(Workshop.arrival(sidekick.card), voice: sidekick.card.voice) }
    }

    /// The scanned floor's height, so the pet stands on it.
    private var floorHeight: Float? {
        let floors = roomContext?.surfaces.filter { $0.kind == .floor }.flatMap { $0.corners.compactMap { $0.count == 3 ? $0[1] : nil } }
        return floors?.min()
    }

    func talkToSidekick() {
        guard let sidekick else { return }
        let lines = sidekick.card.lines.isEmpty ? [Workshop.arrival(sidekick.card)] : sidekick.card.lines
        speak(lines[sidekickLine % lines.count], voice: sidekick.card.voice)
        sidekickLine += 1
        sidekickRig?.perform()
    }

    /// Puts a drawing to work on the current trap. `fresh` means Codex made it for this trap.
    func deployHelper(_ creation: Creation, fresh: Bool = false) {
        guard phase == .challenge, let questAnchor else { return }
        let placement: HelperRig.Placement = creation.card.kind == .tool ? .hand : .beside
        guard let rig = try? HelperRig(creation: creation, placement: placement) else {
            challengeDrawing = .failed("Couldn't load that drawing's 3D model. Try another.")
            return
        }
        helperRig?.root.removeFromParent()
        (placement == .hand ? cameraAnchor : questAnchor).addChild(rig.root)
        helperRig = rig
        helper = creation
        helperIsFresh = fresh
        helperLine = 0
        trapProgress = TrapProgress(needed: creation.card.clampedUses)
        speak(Workshop.arrival(creation.card), voice: creation.card.voice)
    }

    /// One use of the helper on the trap: a swing, a lunge, or a pulse.
    func useHelper() {
        guard phase == .challenge, trackingReady, itemInReach, var progress = trapProgress,
              let helper, let helperRig, let trapRig, let challenge, progress.use() else { return }
        trapProgress = progress
        helperRig.perform()
        trapRig.hit()
        UIImpactFeedbackGenerator(style: progress.cleared ? .heavy : .medium).impactOccurred()
        guard progress.cleared else {
            if helper.card.kind == .character, !speech.isSpeaking { speak(helper.card.verbButton, voice: helper.card.voice) }
            return
        }
        trapRig.shatter()
        keepsake?.isEnabled = true
        keepsakeLift = 0
        let line = helperIsFresh && !helper.card.success.isEmpty ? helper.card.success
            : "\(helper.card.displayName.prefix(1).uppercased() + helper.card.displayName.dropFirst()) did it! \(challenge.cleared)"
        speak(line, voice: helper.card.voice)
        game.clearChallenge()
        creatureAnimator?.react(.celebrate)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if helperRig.placement == .hand {
            // Tools go back in the inventory once the job's done.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.helperRig === helperRig else { return }
                helperRig.root.removeFromParent()
                self.helperRig = nil
            }
        }
    }

    func talkToHelper() {
        guard let helper else { return }
        let lines = helper.card.lines.isEmpty ? [Workshop.arrival(helper.card)] : helper.card.lines
        speak(lines[helperLine % lines.count], voice: helper.card.voice)
        helperLine += 1
    }

    #if DEBUG
    func devSkipTrap() {
        guard phase == .challenge else { return }
        trapRig?.shatter()
        keepsake?.isEnabled = true
        keepsakeLift = 0
        game.clearChallenge()
    }
    #endif

    func collectKeepsake() {
        guard game.collect(trackingReady: trackingReady, inReach: itemInReach) else { return }
        clearQuest()
        dialogue = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func finishQuest() {
        guard game.finishQuest(trackingReady: trackingReady, inReach: inReach) else { return }
        completedFriends.insert(friend.rawValue)
        UserDefaults.standard.set(Array(completedFriends).sorted(), forKey: "realmFriendships")
        speak(friend.thanks)
        creatureAnimator?.react(.celebrate)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func chat() {
        guard phase == .complete, trackingReady, inReach else { return }
        speak(friend.chat)
        creatureAnimator?.react(.chat)
    }

    func pet() {
        guard [.revealed, .challenge, .questing, .returning, .complete].contains(phase), trackingReady, inReach else { return }
        guard creatureAnimator?.react(.pet) == true else { return }
        dialogue = friend.petReaction
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func play() {
        guard [.revealed, .challenge, .questing, .returning, .complete].contains(phase), trackingReady, inReach,
              creatureAnimator?.react(.play) == true else { return }
        dialogue = friend.playReaction
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Tap the friend to pet them, the trap to use your helper, or a drawn character to talk.
    @objc private func tapFriend(_ recognizer: UITapGestureRecognizer) {
        guard var hit = arView.entity(at: recognizer.location(in: arView)) else { return }
        while true {
            if hit === creature { pet(); return }
            if hit === trapRig?.root { useHelper(); return }
            if hit === helperRig?.root { helperRig?.kind == .tool ? useHelper() : talkToHelper(); return }
            if hit === sidekickRig?.root { talkToSidekick(); return }
            guard let parent = hit.parent else { return }
            hit = parent
        }
    }
    /// Friends use their own voice; drawings use the voice Codex picked for them.
    private func speak(_ text: String, voice: DrawingCard.Voice? = nil) {
        dialogue = text
        speech.stopSpeaking(at: .immediate)
        let line = AVSpeechUtterance(string: text)
        switch voice {
        case .high?: line.rate = 0.5; line.pitchMultiplier = 1.45
        case .low?: line.rate = 0.44; line.pitchMultiplier = 0.75
        case .normal?: line.rate = 0.48; line.pitchMultiplier = 1.0
        case nil:
            line.rate = friend == .pebblin ? 0.43 : 0.48
            line.pitchMultiplier = friend == .glimlo ? 1.18 : 1.05
        }
        speech.speak(line)
    }

    func chooseAnotherFriend() {
        generation = UUID()
        planTask?.cancel()
        planTask = nil
        capture?.delegate = nil
        capture?.stop(pauseARSession: false)
        capture = nil
        speech.stopSpeaking(at: .immediate)
        if let anchor { arView.scene.removeAnchor(anchor) }
        if let worldAnchor { arView.session.remove(anchor: worldAnchor) }
        clearQuest()
        clearTheme()
        anchor = nil
        worldAnchor = nil
        creature = nil
        creatureAnimator = nil
        preparedCreature = nil
        candidates = []
        spawnTransforms = [:]
        cameraPositions = []
        photos = []
        photoSectors = []
        plan = nil
        dialogue = nil
        requesting = false
        distance = nil
        restoringRoom = false
        pendingRoom = nil
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        started = false
        trackingReady = false
        game = Adventure()
    }

    func dismissIssue() { issue = nil }
    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> { [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z] }
    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length(SIMD2<Float>(a.x - b.x, a.z - b.z)) }

    private func tick(_ delta: Double) {
        elapsed += min(delta, 0.1)
        if !suspended && !interrupted && trackingReady {
            creatureAnimator?.update(delta: delta, speaking: speech.isSpeaking,
                                     reducedMotion: UIAccessibility.isReduceMotionEnabled)
        }
        let step = Float(min(delta, 0.1))
        if let keepsake {
            // A freed item drifts down from wherever the trap held it.
            let lift = keepsake.position.y - sin(Float(elapsed - delta) * 2) * 0.025
            let eased = lift + (keepsakeLift - lift) * min(1, step * 3)
            keepsake.position.y = sin(Float(elapsed) * 2) * 0.025 + eased
            keepsake.orientation = simd_quatf(angle: Float(elapsed) * 0.65, axis: [0, 1, 0])
        }
        trapRig?.update(delta: step)
        if trapRig?.finished == true {
            trapRig?.root.removeFromParent()
            trapRig = nil
        }
        if let camera = arView.session.currentFrame?.camera.transform, trackingReady {
            helperRig?.update(delta: step, camera: camera)
            sidekickRig?.update(delta: step, camera: camera)
        }
        if (sidekickDrawing.isWorking || challengeDrawing.isWorking), elapsed - lastWhimsy > 3.5 {
            lastWhimsy = elapsed
            whimsy += 1
        }
        guard elapsed - lastHUDUpdate > 0.15 else { return }
        lastHUDUpdate = elapsed
        guard !suspended, !interrupted, !failed, let frame = arView.session.currentFrame else {
            if interrupted { trackingMessage = "The camera was interrupted. Close other camera apps and come back." }
            if failed { trackingMessage = "AR stopped. Use Scan again from the menu." }
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
        if restoringRoom, trackingReady, let pendingRoom, elapsed - scanStarted > 1 {
            applySavedRoom(pendingRoom)
        }
        if phase == .scanning, trackingReady, !restoringRoom {
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
        if let questAnchor {
            questDistance = horizontalDistance(position(frame.camera.transform), questAnchor.position(relativeTo: nil))
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
        let camera = position(frame.camera.transform)
        let forward = -frame.camera.transform.columns.2
        photos.append(ScanPhoto(jpeg: jpeg.base64EncodedString(), yaw: yaw,
            position: [camera.x, camera.y, camera.z], forward: [forward.x, forward.y, forward.z]))
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
