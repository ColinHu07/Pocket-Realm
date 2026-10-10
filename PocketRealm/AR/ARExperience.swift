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
    @Published var connectionPresented = false
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
    var objectiveDistance: Float? { phase == .questing ? questDistance : distance }
    var canRetryPlan: Bool { !candidates.isEmpty && roomContext != nil && !photos.isEmpty && !requesting }
    var canReplayRoom: Bool {
        started && replayRoom != nil && roomContext != nil && themeRoom != nil &&
            ![.scanning, .planning, .restoring].contains(phase) && !requesting && !failed
    }
    var challengeAvailable: Bool { trackingReady && inReach && challengePanelVisible && !suspended && !interrupted && !themePresented && !connectionPresented }

    func setChallengePanelVisible(_ visible: Bool) {
        guard challengePanelVisible != visible else { return }
        challengePanelVisible = visible
        // Don't let Bloopi demonstrate moves behind a tucked-away drawer.
        if !visible { game.advanceChallenge(delta: 0, available: false) }
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
                    let placementObserver = position(previous) + facing * 2
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
        guard let transform = SurfacePlacement.transform(category: String(describing: object.category),
            dimensions: object.dimensions, object: object.transform, observer: observer,
            surfaces: context.surfaces) else { return nil }
        // Reject a floor/table point occupied by other scanned furniture.
        let point = position(transform) + SIMD3<Float>(0, 0.12, 0)
        guard !room.objects.contains(where: { other in
            other.identifier != object.identifier && DecorationVolume(inverse: simd_inverse(other.transform),
                half: other.dimensions / 2).contains(point, padding: SurfacePlacement.footprintRadius)
        }) else { return nil }
        return transform
    }

    private func refineSupport(_ transform: simd_float4x4) -> simd_float4x4 {
        let query = ARRaycastQuery(origin: position(transform) + SIMD3<Float>(0, SurfacePlacement.refinementLimit + 0.02, 0),
            direction: [0, -1, 0], allowing: .existingPlaneGeometry, alignment: .horizontal)
        let hits = arView.session.raycast(query).map { position($0.worldTransform) }
        return SurfacePlacement.refined(transform, hits: hits)
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
        speak((plan?.greeting ?? "Hi! I'm \(friend.name).") + " " + friend.questRequest)
        creatureAnimator?.react(.greeting)
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
        guard [.revealed, .questing, .returning, .complete].contains(phase), trackingReady, inReach else { return }
        guard creatureAnimator?.react(.pet) == true else { return }
        dialogue = friend.petReaction
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func play() {
        guard [.revealed, .questing, .returning, .complete].contains(phase), trackingReady, inReach,
              creatureAnimator?.react(.play) == true else { return }
        dialogue = friend.playReaction
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func tapFriend(_ recognizer: UITapGestureRecognizer) {
        guard let creature, var hit = arView.entity(at: recognizer.location(in: arView)) else { return }
        while hit !== creature {
            guard let parent = hit.parent else { return }
            hit = parent
        }
        pet()
    }
    private func speak(_ text: String) {
        dialogue = text
        speech.stopSpeaking(at: .immediate)
        let line = AVSpeechUtterance(string: text)
        line.rate = friend == .pebblin ? 0.43 : 0.48
        line.pitchMultiplier = friend == .glimlo ? 1.18 : 1.05
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
                                     reducedMotion: UIAccessibility.isReduceMotionEnabled)
        }
        if let keepsake {
            keepsake.position.y = sin(Float(elapsed) * 2) * 0.025
            keepsake.orientation = simd_quatf(angle: Float(elapsed) * 0.65, axis: [0, 1, 0])
        }
        if let questReward {
            questReward.position.y = 0.25 + (UIAccessibility.isReduceMotionEnabled ? 0 : sin(Float(elapsed) * 1.6) * 0.012)
        }
        guard elapsed - lastHUDUpdate > 0.15 else { return }
        lastHUDUpdate = elapsed
        guard !suspended, !interrupted, !failed, let frame = arView.session.currentFrame else {
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
