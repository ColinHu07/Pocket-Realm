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
    @Published private(set) var scanInstruction = "Slowly turn all the way around. Include visible walls and furniture."
    @Published private(set) var planningError: String?
    @Published private(set) var plan: EncounterPlan?
    @Published private(set) var proximity = ProximityGate()
    @Published private(set) var selectedCategory = ""
    @Published private(set) var requesting = false
    @Published private(set) var provider = PlanningProvider.saved(UserDefaults.standard.string(forKey: "planningProvider"))
    @Published private(set) var museModel = MuseModel(rawValue: UserDefaults.standard.string(forKey: "museModel") ?? "") ?? .spark13
    @Published private(set) var hasAPIKey = false
    @Published private(set) var geminiModel = GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash38
    @Published private(set) var connectionState: PlanningConnectionState = .needsKey
    @Published var serverAddress = ARExperience.initialServerAddress() {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "adventureServer") }
    }
    @Published var sketchQuestsEnabled = UserDefaults.standard.object(forKey: "sketchQuestsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sketchQuestsEnabled, forKey: "sketchQuestsEnabled") }
    }

    /// Update the bundled default without replacing a workshop the user configured themselves.
    private static func initialServerAddress() -> String {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "adventureServer")
        let previousDefault = defaults.string(forKey: "adventureServerDefault")
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "AdventureServerDefault") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        if !bundled.isEmpty, !bundled.hasPrefix("$("), defaults.string(forKey: "adventureServerDefault") != bundled {
            defaults.set(bundled, forKey: "adventureServerDefault")
            if saved == nil || saved == previousDefault {
                defaults.set(bundled, forKey: "adventureServer")
            }
        }
        return defaults.string(forKey: "adventureServer").flatMap { $0.isEmpty ? nil : $0 } ?? ""
    }
    @Published var connectionPresented = false
    @Published var workshopSettingsRequested = false
    @Published var themePresented = false
    @Published private(set) var challengePanelVisible = true
    @Published private(set) var theme = RealmTheme(rawValue: UserDefaults.standard.string(forKey: "realmTheme") ?? "") ?? .original
    @Published private(set) var themeMessage = "Choose a look for your room."
    @Published private(set) var friend: RealmFriend = .mosskip
    @Published private(set) var questCategory = ""
    @Published private(set) var questDistance: Float?
    @Published private(set) var dialogue: String?
    @Published private(set) var completedFriends: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "realmFriendships") ?? [])
    @Published private(set) var savedRoomDate: Date?
    @Published private(set) var savedRoomNotice: String?
    @Published private(set) var roomSaveMessage: String?
    @Published private(set) var savingRoom = false
    @Published private(set) var usingSavedRoom = false
    @Published private(set) var restoreMessage = "Point the camera around the same room to line everything up."
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
    private var questReward: Entity?
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
    private var connectionTask: Task<Void, Never>?
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
    private var candidates: [RoomCandidate] = []
    private var spawnTransforms: [String: simd_float4x4] = [:]
    private var cameraPositions: [SIMD3<Float>] = []
    private var photos: [ScanPhoto] = []
    private var wallObservations: [WallObservation] = []
    private var wallObservationIndices: [Int: Int] = [:]
    private var lastWallObservation: Double = -.infinity
    private var photoSectors: Set<Int> = []
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let speech = AVSpeechSynthesizer()
    private let roomStore = SavedRoomStore.local
    private var storedRoom: SavedRoom?
    private var replayRoom: RoomPlanReplay?
    private var restoringRoom: SavedRoom?
    private var restoreGate = RoomRelocalizationGate()
    private var restoreStarted: Double = 0
    private var restoreAfterFrame: TimeInterval = -.infinity
    private var roomNeedsSaving = false
    private var lastSaveAttempt: Double = -.infinity
    private var roomSaveToken = UUID()

    var phase: Adventure.Phase { game.phase }
    var testingConnection: Bool { connectionState.isChecking }
    var planningClient: PlanningClient {
        PlanningClient(provider: provider, muse: MuseClient(model: museModel), gemini: GeminiClient(model: geminiModel))
    }
    var modelName: String { planningClient.modelName }
    var inReach: Bool { anchor?.isAnchored == true && (distance ?? .infinity) <= 2 }
    var itemInReach: Bool { questAnchor?.isAnchored == true && (questDistance ?? .infinity) <= 1.3 }
    var objectiveDistance: Float? { [.challenge, .questing].contains(phase) ? questDistance : distance }
    var canRetryPlan: Bool { !candidates.isEmpty && roomContext != nil && !photos.isEmpty && !requesting }
    var canReplayRoom: Bool {
        started && replayRoom != nil && roomContext != nil && themeRoom != nil &&
            ![.scanning, .planning, .restoring].contains(phase) && !requesting && !failed
    }
    var challengeAvailable: Bool { trackingReady && inReach && challengePanelVisible && !suspended && !interrupted && !themePresented && !connectionPresented && !drawingPresented }

    func setChallengePanelVisible(_ visible: Bool) {
        guard challengePanelVisible != visible else { return }
        challengePanelVisible = visible
        // Don't let Bloopi demonstrate moves behind a tucked-away drawer.
        if !visible { game.advanceChallenge(delta: 0, available: false) }
    }
    var addressIsValid: Bool { (try? AdventureClient.endpoint(serverAddress)) != nil }
    var canPlaySketchQuests: Bool { sketchQuestsEnabled && (addressIsValid || !inventory.isEmpty) }
    var questRequest: String {
        guard let challenge else { return friend.questRequest }
        return "\(challenge.cleared) Pick up the \(friend.itemName) and bring it back to \(friend.name)."
    }

    override init() {
        super.init()
        do {
            hasAPIKey = try PlannerKeyStore.read(for: provider) != nil
            connectionState = hasAPIKey ? .saved : .needsKey
        } catch { connectionState = .failed(error.localizedDescription) }
        if ProcessInfo.processInfo.arguments.contains("--gemini-setup") {
            selectProvider(.gemini); connectionPresented = true
        } else if ProcessInfo.processInfo.arguments.contains("--muse-setup") {
            selectProvider(.muse); connectionPresented = true
        }
        arView.session.delegate = self
        arView.scene.addAnchor(cameraAnchor)
        arView.scene.addAnchor(petAnchor)
        if let id = UserDefaults.standard.string(forKey: "sidekick") { sidekick = inventory.first { $0.id == id } }
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapFriend(_:))))
        do {
            storedRoom = try roomStore.load()
            savedRoomDate = storedRoom?.savedAt
        } catch { savedRoomNotice = error.localizedDescription }
        applyTheme()
        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            Task { @MainActor [weak self] in self?.tick(event.deltaTime) }
        }
    }

    func start() {
        guard supported else { issue = "Room scanning needs a LiDAR-equipped iPhone Pro or iPad Pro. Run on your iPhone instead of the simulator."; return }
        guard hasAPIKey else { connectionPresented = true; return }
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
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func rescan() {
        guard hasAPIKey else { connectionPresented = true; return }
        generation = UUID()
        resetRoomPersistenceState()
        planTask?.cancel()
        planTask = nil
        capture?.delegate = nil
        capture?.stop(pauseARSession: false)
        capture = nil
        speech.stopSpeaking(at: .immediate)
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
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
        questReward = nil
        candidates = []
        spawnTransforms = [:]
        cameraPositions = []
        photos = []
        photoSectors = []
        plan = nil
        planningError = nil
        issue = nil
        failed = false
        suspended = false
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
        scanInstruction = "Slowly turn all the way around. Include visible walls and furniture."
        configure(reset: true)
        // RoomPlan and gameplay use this exact ARSession and therefore the same coordinate origin.
        let session = RoomCaptureSession(arSession: arView.session)
        capture = session
        session.delegate = self
        session.run(configuration: .init())
    }

    /// Reuse geometry and the spatial plan. This path never calls the server.
    func useSavedRoom() {
        guard supported else { issue = "Open the saved room on your LiDAR-equipped iPhone."; return }
        guard let snapshot = storedRoom else { return }
        let token = generation
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                cameraDenied = true; issue = "Allow camera access in Settings to recognize your saved room."; return
            }
            guard generation == token, storedRoom?.referenceAnchorID == snapshot.referenceAnchorID else { return }
            do {
                try snapshot.validate()
                let room = try JSONDecoder().decode(CapturedRoom.self, from: snapshot.capturedRoom)
                guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: snapshot.worldMap),
                      map.anchors.contains(where: { $0.identifier == snapshot.referenceAnchorID }) else { throw SavedRoomError.invalidData }
                let context = ThemeFactory.context(for: room)
                let observer = SIMD3(snapshot.observer[0], snapshot.observer[1], snapshot.observer[2])
                // Rebuild support points from saved geometry, including rooms saved
                // by versions that intentionally placed friends beside furniture in midair.
                var transforms: [String: simd_float4x4] = [:]
                var restoredCandidates: [RoomCandidate] = []
                for candidate in snapshot.candidates {
                    let previous = try SavedRoom.matrix(snapshot.transforms[candidate.id]!)
                    // Retain the previously observed side of this furniture, even
                    // when the scan finished facing the opposite side of the room.
                    let facing = SIMD3(previous.columns.2.x, previous.columns.2.y, previous.columns.2.z)
                    var placementObserver = position(previous) + facing * 2
                    placementObserver.y = observer.y
                    guard let object = room.objects.first(where: { $0.identifier.uuidString == candidate.id }),
                          let transform = placement(for: object, in: room, observer: placementObserver, context: context) else { continue }
                    transforms[candidate.id] = transform
                    let point = position(transform)
                    restoredCandidates.append(RoomCandidate(id: candidate.id, category: candidate.category,
                        dimensions: candidate.dimensions, position: [point.x, point.y, point.z],
                        distance: horizontalDistance(observer, point)))
                }
                let observations = try snapshot.observations.map { try $0.restore() }
                let selected = snapshot.encounter(for: friend)
                guard transforms[selected.objectID] != nil,
                      let keepsakeID = selected.room?.keepsakeObjectID, transforms[keepsakeID] != nil else {
                    throw PlanError.server("This saved room needs a clearer supporting surface. Scan again, including a tabletop and the floor beside furniture.")
                }
                try selected.validateRoom(against: restoredCandidates, surfaces: context.surfaces)
                chooseAnotherFriend()
                cameraDenied = false; started = true; usingSavedRoom = true
                restoringRoom = snapshot
                replayRoom = RoomPlanReplay(friend: snapshot.friend, plan: snapshot.plan, candidates: restoredCandidates)
                themeRoom = room; roomContext = context
                themeObserver = SIMD3(snapshot.observer[0], snapshot.observer[1], snapshot.observer[2])
                candidates = restoredCandidates; spawnTransforms = transforms; wallObservations = observations
                objectCount = candidates.count; plan = selected
                selectedCategory = candidates.first { $0.id == selected.objectID }?.category ?? "furniture"
                restoreGate = RoomRelocalizationGate(); restoreStarted = elapsed
                restoreAfterFrame = arView.session.currentFrame?.timestamp ?? -.infinity
                restoreMessage = "Look at the furniture and walls from roughly where you scanned before. No new AI request is needed."
                game.beginRestoring()
                configure(reset: true, worldMap: map)
            } catch {
                issue = "Couldn't open the saved room. \(error.localizedDescription) You can make a fresh scan."
            }
        }
    }

    func forgetSavedRoom() {
        // Invalidate an outstanding world-map callback so Forget cannot be undone by a late save.
        roomSaveToken = UUID(); roomNeedsSaving = false; savingRoom = false
        do {
            try roomStore.delete()
            storedRoom = nil; savedRoomDate = nil; savedRoomNotice = nil
            roomSaveMessage = "Saved room removed from this iPhone."
        } catch { issue = "Couldn't remove the saved room: \(error.localizedDescription)" }
    }

    func saveRoomAgain() {
        guard !savingRoom, ![.scanning, .planning, .restoring].contains(phase), plan != nil else { return }
        roomNeedsSaving = true; lastSaveAttempt = -.infinity
        saveRoomIfReady()
    }

    private func resetRoomPersistenceState() {
        roomSaveToken = UUID(); roomNeedsSaving = false; savingRoom = false
        roomSaveMessage = nil; usingSavedRoom = false; restoringRoom = nil
        replayRoom = nil
        restoreGate = RoomRelocalizationGate(); lastSaveAttempt = -.infinity
    }

    private func saveRoomIfReady() {
        guard roomNeedsSaving, !savingRoom, elapsed - lastSaveAttempt >= 3,
              let plan, let themeRoom, let roomContext, ![.scanning, .planning, .restoring].contains(phase) else { return }
        lastSaveAttempt = elapsed
        guard trackingReady, let frame = arView.session.currentFrame,
              frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending else {
            roomSaveMessage = "Look around a little more so your room can be saved for next time."
            return
        }
        savingRoom = true; roomSaveMessage = "Saving your room on this iPhone…"
        let token = roomSaveToken
        // Replaying another friend during this callback must not relabel the original generated puzzle.
        let sourcePlan = replayRoom?.plan ?? plan
        let sourceFriend = replayRoom?.friend ?? friend
        arView.session.getCurrentWorldMap { [weak self] map, error in
            Task { @MainActor [weak self] in
                guard let self, self.roomSaveToken == token else { return }
                self.savingRoom = false
                self.roomNeedsSaving = false
                do {
                    if let error { throw error }
                    guard let map else { throw SavedRoomError.invalidData }
                    // Save a stable origin marker, not ephemeral quest/mesh anchors.
                    let reference = ARAnchor(name: "PocketRealmSavedOrigin", transform: matrix_identity_float4x4)
                    map.anchors = [reference]
                    let snapshot = SavedRoom(savedAt: Date(), friend: sourceFriend, plan: sourcePlan,
                        candidates: self.candidates, transforms: self.spawnTransforms.mapValues(SavedRoom.values),
                        context: roomContext, observer: [self.themeObserver.x, self.themeObserver.y, self.themeObserver.z],
                        observations: self.wallObservations.map(SavedWallObservation.init),
                        capturedRoom: try JSONEncoder().encode(themeRoom),
                        worldMap: try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true),
                        referenceAnchorID: reference.identifier)
                    try self.roomStore.save(snapshot)
                    self.storedRoom = snapshot; self.savedRoomDate = snapshot.savedAt; self.savedRoomNotice = nil
                    self.roomSaveMessage = "Room saved on this iPhone. Reuse it next time without an AI request."
                } catch {
                    self.roomSaveMessage = "Room wasn't saved. Tap Save room to retry. Your current adventure can continue."
                }
            }
        }
    }

    func suspend() {
        guard started else { return }
        suspended = true
        trackingReady = false
        game.advanceChallenge(delta: 0, available: false)
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
        themeRoom = room
        themeObserver = camera
        let context = ThemeFactory.context(for: room)
        candidates = []
        spawnTransforms = [:]
        for object in room.objects.filter(Self.eligible).prefix(24) {
            let id = object.identifier.uuidString
            let center = position(object.transform)
            let observer = cameraPositions.min(by: { horizontalDistance($0, center) < horizontalDistance($1, center) }) ?? camera
            guard let transform = placement(for: object, in: room, observer: observer, context: context) else { continue }
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
            planningError = "No clear supporting surfaces yet. Scan again and include a tabletop or the floor beside furniture."
            return
        }
        guard context.surfaces.contains(where: { $0.kind == .floor || $0.kind == .wall }), !photos.isEmpty else {
            planningError = "The scan needs clearer room surfaces and snapshots. Scan again, including visible walls and furniture."
            return
        }
        roomContext = context
        requestPlan()
    }

    private func placement(for object: CapturedRoom.Object, in room: CapturedRoom, observer: SIMD3<Float>,
                           context: RoomScanContext) -> simd_float4x4? {
        let obstacles = room.objects.filter { $0.identifier != object.identifier }.map {
            DecorationVolume(inverse: simd_inverse($0.transform), half: $0.dimensions / 2)
        }
        return SurfacePlacement.transform(category: String(describing: object.category),
            dimensions: object.dimensions, object: object.transform, observer: observer,
            surfaces: context.surfaces, obstacles: obstacles)
    }

    private func refineSupport(_ transform: simd_float4x4) -> simd_float4x4 {
        let query = ARRaycastQuery(origin: position(transform) + SIMD3<Float>(0, SurfacePlacement.refinementLimit + 0.02, 0),
            direction: [0, -1, 0], allowing: .existingPlaneGeometry, alignment: .horizontal)
        let hits = arView.session.raycast(query).map { position($0.worldTransform) }
        let refined = SurfacePlacement.refined(transform, hits: hits)
        guard let roomContext, let themeRoom else { return transform }
        let obstacles = themeRoom.objects.map {
            DecorationVolume(inverse: simd_inverse($0.transform), half: $0.dimensions / 2)
        }
        return SurfacePlacement.hasRoom(at: position(refined), surfaces: roomContext.surfaces, obstacles: obstacles)
            ? refined : transform
    }

    func requestPlan() {
        guard canRetryPlan, phase == .planning, let context = roomContext else { return }
        let key: String
        do {
            guard let saved = try PlannerKeyStore.read(for: provider) else { hasAPIKey = false; connectionPresented = true; return }
            key = saved
        } catch { planningError = error.localizedDescription; return }
        requesting = true
        planningError = nil
        let token = generation
        let input = candidates
        let images = photos
        let selectedFriend = friend
        let client = planningClient
        planTask = Task { [weak self] in
            do {
                let selected = try await client.plan(key: key, candidates: input, photos: images, friend: selectedFriend, context: context)
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

    func saveAPIKey(_ key: String) -> Bool {
        guard !testingConnection, !requesting else { return false }
        do {
            try PlannerKeyStore.save(key, for: provider)
            hasAPIKey = true
            connectionState = .saved
            return true
        } catch { connectionState = .failed(error.localizedDescription); return false }
    }

    func selectProvider(_ selected: PlanningProvider) {
        guard !testingConnection, !requesting, selected != provider else { return }
        provider = selected
        UserDefaults.standard.set(selected.rawValue, forKey: "planningProvider")
        hasAPIKey = false
        do {
            hasAPIKey = try PlannerKeyStore.read(for: selected) != nil
            connectionState = hasAPIKey ? .saved : .needsKey
        } catch { connectionState = .failed(error.localizedDescription) }
    }

    func selectMuseModel(_ model: MuseModel) {
        guard !testingConnection, !requesting, model != museModel else { return }
        museModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "museModel")
        connectionState = hasAPIKey ? .saved : .needsKey
    }

    func selectGeminiModel(_ model: GeminiModel) {
        guard !testingConnection, !requesting, model != geminiModel else { return }
        geminiModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "geminiModel")
        connectionState = hasAPIKey ? .saved : .needsKey
    }

    func testAPIKey() {
        guard !testingConnection, !requesting else { return }
        connectionState = .checking(Date())
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let key = try PlannerKeyStore.read(for: provider) else {
                    self.hasAPIKey = false
                    throw PlanError.server("Paste your \(self.provider.name) API key first.")
                }
                try await self.planningClient.test(key: key)
                guard !Task.isCancelled else { return }
                self.connectionState = .connected(Date())
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                guard !Task.isCancelled else { return }
                self.connectionState = .failed(error.localizedDescription)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            self.connectionTask = nil
        }
    }

    func cancelConnectionTest() {
        guard testingConnection else { return }
        connectionTask?.cancel()
        connectionTask = nil
        connectionState = hasAPIKey ? .saved : .needsKey
    }

    func removeAPIKey() {
        guard !testingConnection, !requesting else { return }
        do {
            try PlannerKeyStore.remove(for: provider)
            hasAPIKey = false
            connectionState = .needsKey
        } catch { connectionState = .failed(error.localizedDescription) }
    }

    private func install(_ selected: EncounterPlan) {
        guard spawnTransforms[selected.objectID] != nil, let room = selected.room,
              spawnTransforms[room.keepsakeObjectID] != nil else {
            planningError = PlanError.invalidPlan.localizedDescription
            return
        }
        plan = selected
        replayRoom = RoomPlanReplay(friend: friend, plan: selected, candidates: candidates)
        selectedCategory = candidates.first(where: { $0.id == selected.objectID })?.category ?? "furniture"
        applyTheme()
        let blueprint = selected.challenge.flatMap { QuestBlueprint(rawValue: $0.blueprintID) } ?? QuestBlueprint.first(for: friend)
        game.acceptPlan(challenge: blueprint.map { QuestGame(blueprint: $0, introduction: selected.challenge?.introduction) })
        photos = []
        roomNeedsSaving = true
        saveRoomIfReady()
    }

    /// Keep the live AR coordinate frame and measured room. Restart only the encounter, with zero API calls.
    func replayCurrentRoom(with selectedFriend: RealmFriend? = nil) {
        guard canReplayRoom, let replayRoom, let context = roomContext else { return }
        let selectedFriend = selectedFriend ?? friend
        let selected = replayRoom.encounter(for: selectedFriend)
        do { try selected.validateRoom(against: candidates, surfaces: context.surfaces) }
        catch { issue = error.localizedDescription; return }
        let blueprint = selected.challenge.flatMap { QuestBlueprint(rawValue: $0.blueprintID) } ?? QuestBlueprint.first(for: selectedFriend)
        guard game.replayRoom(challenge: blueprint.map { QuestGame(blueprint: $0, introduction: selected.challenge?.introduction) }) else { return }
        speech.stopSpeaking(at: .immediate)
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
        if let anchor { arView.scene.removeAnchor(anchor) }
        if let worldAnchor { arView.session.remove(anchor: worldAnchor) }
        clearQuest()
        anchor = nil; worldAnchor = nil; creature = nil; creatureAnimator = nil
        preparedCreature = nil; questReward = nil; dialogue = nil; distance = nil
        proximity = ProximityGate()
        friend = selectedFriend; plan = selected; usingSavedRoom = true
        selectedCategory = candidates.first { $0.id == selected.objectID }?.category ?? "furniture"
        planningError = nil
        if !savingRoom { roomSaveMessage = "Reusing this scan and room plan. No AI request made." }
        applyTheme()
    }

    func beginExploring() {
        guard phase == .ready, trackingReady, let plan, let room = plan.room,
              let support = spawnTransforms[plan.objectID] else { return }
        let transform = refineSupport(support)
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
        creatureAnimator = CreatureAnimator(root: spirit, friend: friend, grounded: true)
        creatureAnimator?.update(delta: 0, reducedMotion: UIAccessibility.isReduceMotionEnabled)
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
        // Rebuild when switching presets, while keeping the validated room plan.
        if jungle?.theme != theme { jungle = nil }
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        guard theme != .original else {
            themeMessage = "Your room, just as it is."
            return
        }
        guard phase != .restoring else { themeMessage = "Your \(theme.name) returns once the room is recognized."; return }
        guard let themeRoom, let understanding = plan?.room else {
            themeMessage = "Your selected AI will plan your wall decorations after the 360° scan. Include visible walls and furniture."
            return
        }
        do {
            if jungle == nil {
                let questPositions = [plan?.objectID, understanding.keepsakeObjectID].compactMap { id -> SIMD3<Float>? in
                    guard let id, let transform = spawnTransforms[id] else { return nil }
                    return position(transform)
                }
                jungle = try ThemeFactory.make(theme, in: themeRoom, observer: themeObserver,
                    plan: understanding.jungle, questPositions: questPositions, observations: wallObservations)
            }
            if let jungle {
                if jungle.hasContent {
                    jungle.anchor.isEnabled = trackingReady
                    arView.environment.sceneUnderstanding.options.insert(.occlusion)
                    arView.scene.addAnchor(jungle.anchor)
                }
                themeMessage = jungle.message
            }
        } catch {
            themeMessage = "Couldn't load \(theme.name). Select it to try again, or scan the room again."
        }
    }

    private func clearTheme() {
        if let jungle { arView.scene.removeAnchor(jungle.anchor) }
        jungle = nil
        themeRoom = nil
        roomContext = nil
        wallObservations = []
        wallObservationIndices = [:]
        lastWallObservation = -.infinity
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        themeMessage = theme != .original ? "Your selected AI will plan your wall decorations after the 360° scan. Include visible walls and furniture." : "Your room, just as it is."
    }

    private func prepareQuest(friendID: String, keepsakeID: String) {
        guard let location = candidates.first(where: { $0.id == keepsakeID }),
              var transform = spawnTransforms[location.id] else { return }
        // Refine in the recognized coordinate frame, then deliberately float this magical pickup.
        transform = refineSupport(transform)
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
        drawingPresented = false
        helperRig?.root.removeFromParent()
        helperRig = nil
        trapRig = nil
        helper = nil
        trapProgress = nil
        challenge = nil
        keepsakeLift = 0
        drawingTasks[.challenge]?.cancel()
        drawingTasks[.challenge] = nil
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
        guard let questAnchor, game.talk(trackingReady: trackingReady, inReach: inReach,
                                        withDrawingChallenge: canPlaySketchQuests) else { return }
        let item = CreatureFactory.keepsake(friend)
        questAnchor.addChild(item)
        keepsake = item
        guard phase == .challenge else {
            speak((plan?.greeting ?? "Hi! I'm \(friend.name).") + " " + friend.questRequest)
            creatureAnimator?.react(.greeting)
            return
        }
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

    func openWorkshopSettings() {
        workshopSettingsRequested = true
        connectionPresented = true
    }

    func openDrawing(_ purpose: DrawingPurpose) {
        guard addressIsValid else { openWorkshopSettings(); return }
        guard purpose != .challenge || phase == .challenge else { return }
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

    /// The sidekick follows the player on the recognized floor during gameplay.
    private func showSidekick(announce: Bool) {
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
        guard started, ![.scanning, .planning, .restoring, .ready].contains(phase),
              let sidekick, let rig = try? HelperRig(creation: sidekick, placement: .pet) else { return }
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
        guard phase == .challenge, trackingReady, itemInReach, !suspended, !interrupted,
              !drawingPresented, !themePresented, !connectionPresented, var progress = trapProgress,
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

    /// A workshop outage must not prevent the existing pickup and character puzzle from continuing.
    func skipDrawingChallenge() {
        guard phase == .challenge else { return }
        drawingTasks[.challenge]?.cancel()
        drawingTasks[.challenge] = nil
        challengeDrawing = .none
        drawingPresented = false
        helperRig?.root.removeFromParent()
        helperRig = nil
        helper = nil
        trapProgress = nil
        trapRig?.shatter()
        keepsake?.isEnabled = true
        keepsakeLift = 0
        game.clearChallenge()
    }

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
        speak(game.challenge?.blueprint.success ?? friend.thanks)
        creatureAnimator?.react(.celebrate)
        if game.challenge != nil, let anchor {
            let reward = CreatureFactory.questReward(friend)
            reward.position = [0.24, 0.25, 0.12]
            anchor.addChild(reward)
            questReward = reward
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func returnKeepsake() {
        guard game.challenge != nil else { finishQuest(); return }
        guard game.beginChallenge(trackingReady: trackingReady, inReach: inReach) else { return }
        speak(game.challenge?.feedback ?? "Let's play!")
        creatureAnimator?.react(.greeting)
    }

    func playChallenge(_ action: QuestAction) {
        let result = game.playChallenge(action, trackingReady: challengeAvailable, inReach: inReach)
        guard result != .ignored else { return }
        if result == .won { finishQuest(); return }
        if result == .retry { creatureAnimator?.react(.puzzled) }
        else if result == .roundWon { creatureAnimator?.react(.play) }
        else if case .replay = action, let cue = game.challenge?.highlightedID {
            speech.stopSpeaking(at: .immediate)
            creatureAnimator?.react(FriendReaction.bloopMove(cue))
            UIAccessibility.post(notification: .announcement, argument: cue.capitalized)
        } else if case .select(let id) = action, game.challenge?.blueprint.kind == .memory {
            creatureAnimator?.react(FriendReaction.bloopMove(id))
        } else { creatureAnimator?.react(.chat) }
        switch action {
        case .select: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .replay: break // Keep the demonstration clear of long spoken instructions.
        case .submit, .hint:
            if let feedback = game.challenge?.feedback { speak(feedback) }
        }
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
        guard trackingReady, !suspended, !interrupted, !drawingPresented, !themePresented, !connectionPresented else { return }
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
        resetRoomPersistenceState()
        planTask?.cancel()
        planTask = nil
        capture?.delegate = nil
        capture?.stop(pauseARSession: false)
        capture = nil
        speech.stopSpeaking(at: .immediate)
        sidekickRig?.root.removeFromParent()
        sidekickRig = nil
        if let anchor { arView.scene.removeAnchor(anchor) }
        if let worldAnchor { arView.session.remove(anchor: worldAnchor) }
        clearQuest()
        clearTheme()
        anchor = nil
        worldAnchor = nil
        creature = nil
        questReward = nil
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
        suspended = false; failed = false; interrupted = false; scanNeedsRestart = false
        planningError = nil; issue = nil
        distance = nil
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        started = false
        trackingReady = false
        game = Adventure()
    }

    func dismissIssue() { issue = nil }
    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> { [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z] }
    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length(SIMD2<Float>(a.x - b.x, a.z - b.z)) }

    private func friendViewer() -> FriendAttention.View? {
        guard let anchor, anchor.isAnchored, let frame = arView.session.currentFrame,
              case .normal = frame.camera.trackingState,
              !themePresented, !connectionPresented, !drawingPresented else { return nil }
        // A stable point inside the body avoids attention flickering as ears,
        // particles and reaction poses change the visual bounds.
        let target = anchor.convert(position: [0, 0.25, 0], to: nil)
        let cameraLocal = simd_inverse(frame.camera.transform) * SIMD4(target, 1)
        let screenPoint = arView.project(target)
        let viewport = arView.bounds.insetBy(dx: arView.bounds.width * 0.04, dy: arView.bounds.height * 0.04)
        let looking = cameraLocal.z < -0.05 && screenPoint.map { viewport.contains($0) } == true
        return FriendAttention.View(
            cameraPosition: anchor.convert(position: position(frame.camera.transform), from: nil),
            isLooking: looking)
    }

    private func tick(_ delta: Double) {
        elapsed += min(delta, 0.1)
        let previousCue = game.challenge?.highlightedID
        if game.challenge?.memoryStage == .showing {
            game.advanceChallenge(delta: delta, available: challengeAvailable)
            if let cue = game.challenge?.highlightedID, cue != previousCue {
                creatureAnimator?.react(FriendReaction.bloopMove(cue))
                UIAccessibility.post(notification: .announcement, argument: cue.capitalized)
            }
        }
        if !suspended && !interrupted && trackingReady {
            creatureAnimator?.update(delta: delta, speaking: speech.isSpeaking,
                                     reducedMotion: UIAccessibility.isReduceMotionEnabled, viewer: friendViewer())
        }
        let step = Float(min(delta, 0.1))
        if let keepsake {
            // A freed item drifts down from wherever the trap held it.
            let lift = keepsake.position.y - sin(Float(elapsed - delta) * 2) * 0.025
            let eased = lift + (keepsakeLift - lift) * min(1, step * 3)
            keepsake.position.y = sin(Float(elapsed) * 2) * 0.025 + eased
            keepsake.orientation = simd_quatf(angle: Float(elapsed) * 0.65, axis: [0, 1, 0])
        }
        if let questReward {
            questReward.position.y = 0.25 + (UIAccessibility.isReduceMotionEnabled ? 0 : sin(Float(elapsed) * 1.6) * 0.012)
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
            jungle?.anchor.isEnabled = false
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
        if phase == .restoring, let snapshot = restoringRoom {
            let recognized = restoreGate.update(timestamp: frame.timestamp, trackingNormal: trackingReady,
                referencePresent: frame.timestamp > restoreAfterFrame && frame.anchors.contains { $0.identifier == snapshot.referenceAnchorID })
            if recognized, let plan {
                let blueprint = plan.challenge.flatMap { QuestBlueprint(rawValue: $0.blueprintID) } ?? QuestBlueprint.first(for: friend)
                if game.restorePlan(aligned: true, challenge: blueprint.map { QuestGame(blueprint: $0, introduction: plan.challenge?.introduction) }) {
                    restoringRoom = nil
                    roomSaveMessage = "Using your saved room. No scan or AI request needed."
                    applyTheme()
                }
            } else {
                trackingReady = false
                trackingMessage = "Recognizing your saved room…"
                if elapsed - restoreStarted > 25 {
                    restoreMessage = "Still looking for the saved room. Try the original viewpoint and similar lighting. If you moved furniture or changed rooms, make a fresh scan."
                }
            }
        }
        jungle?.anchor.isEnabled = trackingReady
        saveRoomIfReady()
        if phase == .scanning, trackingReady {
            recordWallObservation(frame)
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

    private func recordWallObservation(_ frame: ARFrame) {
        guard frame.timestamp - lastWallObservation >= 0.4 else { return }
        // Bound memory by direction, not elapsed time: a slow sweep must still include its final walls.
        let forward = -frame.camera.transform.columns.2
        let yaw = atan2(Double(forward.x), Double(forward.z))
        let sector = min(23, max(0, Int((yaw + .pi) / (2 * .pi) * 24)))
        let pitch = forward.y < -0.3 ? 0 : (forward.y > 0.3 ? 2 : 1)
        let key = sector * 3 + pitch
        var view = WallObservation(cameraTransform: frame.camera.transform, intrinsics: frame.camera.intrinsics,
            imageSize: SIMD2(Float(frame.camera.imageResolution.width), Float(frame.camera.imageResolution.height)))
        if let depth = frame.sceneDepth {
            let buffer = depth.depthMap
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let confidence = depth.confidenceMap
            if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
            defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                view.depthWidth = 64; view.depthHeight = 48
                for y in 0..<view.depthHeight {
                    for x in 0..<view.depthWidth {
                        let px = min(width - 1, Int((Float(x) + 0.5) / Float(view.depthWidth) * Float(width)))
                        let py = min(height - 1, Int((Float(y) + 0.5) / Float(view.depthHeight) * Float(height)))
                        var value = base.advanced(by: py * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)[px]
                        if let confidence, let values = CVPixelBufferGetBaseAddress(confidence),
                           CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height {
                            let quality = values.advanced(by: py * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[px]
                            if quality == 0 { value = 0 }
                        }
                        view.depth.append(value)
                    }
                }
            }
        }
        if let index = wallObservationIndices[key] {
            wallObservations[index] = view
        } else {
            wallObservationIndices[key] = wallObservations.count
            wallObservations.append(view)
        }
        lastWallObservation = frame.timestamp
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
            default: self.scanInstruction = "Slowly turn all the way around. Include visible walls and furniture."
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
