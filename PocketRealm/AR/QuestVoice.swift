import AVFoundation
import Combine
import ElevenLabs
import SwiftUI
import Security

@MainActor
final class QuestVoice: ObservableObject {
    @Published var conversation: Conversation?
    @Published var hasDeviceKey = false
    @Published var poem = PoetryQuest()
    @Published var poemFeedback = ""
    @Published var poemMode = false
    @Published var voices: [VoiceOption] = []
    @Published var voiceListError: String?
    private var heardLine = ""
    private var handledTools = Set<String>()
    private var toolSubscription: AnyCancellable?
    @Published var agentID: String { didSet { UserDefaults.standard.set(agentID, forKey: "questVoiceAgentID") } }
    @Published var connecting = false
    @Published var progress = ""
    @Published var checkingConnection = false
    @Published var connectionResult: String?
    private var timeoutTask: Task<Void, Never>?
    @Published var error: String?
    @Published var address: String { didSet { save() } }
    @Published var pairingCode: String { didSet { save() } }
    private var attempt = UUID()
    private var startTask: Task<Void, Never>?
    var busy: Bool { connecting || conversation != nil }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "nibbiPoem"), let saved = try? JSONDecoder().decode(PoetryQuest.self, from: data), saved.lines.count <= 2 { poem = saved }
        agentID = defaults.string(forKey: "questVoiceAgentID") ?? ""
        hasDeviceKey = VoiceKeyStore.read() != nil
        address = defaults.string(forKey: "questVoiceAddress") ?? ""
        pairingCode = defaults.string(forKey: "questVoicePairing") ?? ""
        // Development pairing can be installed alongside the app without bundling service credentials.
        let url = URL.documentsDirectory.appending(path: "voice-connection.json")
        if let data = try? Data(contentsOf: url),
           let setup = try? JSONDecoder().decode(Connection.self, from: data) {
            address = setup.address
            pairingCode = setup.pairingCode
            save()
            try? FileManager.default.removeItem(at: url)
        }
        let directURL = URL.documentsDirectory.appending(path: "voice-direct-setup.json")
        if let data = try? Data(contentsOf: directURL),
           let setup = try? JSONDecoder().decode(DirectSetup.self, from: data) {
            do {
                try VoiceKeyStore.save(setup.apiKey)
                agentID = setup.agentID
                defaults.set(agentID, forKey: "questVoiceAgentID")
                hasDeviceKey = true
                try FileManager.default.removeItem(at: directURL)
            } catch { self.error = "Unlock your phone to finish saving the voice key." }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--check-quest-voice") {
            Task { await checkConnection() }
        }
        #endif
    }

    struct VoiceOption: Decodable, Identifiable {
        let voiceId: String
        let name: String
        var id: String { voiceId }
    }
    func loadVoices() async {
        guard let key = VoiceKeyStore.read() else { voiceListError = "Save your ElevenLabs key first."; return }
        do {
            var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v2/voices?page_size=100")!)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            struct Response: Decodable { let voices: [VoiceOption] }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            voices = try decoder.decode(Response.self, from: data).voices.sorted { $0.name < $1.name }
            voiceListError = nil
        } catch { voiceListError = "Couldn't load voices. Check Voices Read access and try again." }
    }
    func resetPoem() {
        guard !busy else { return }
        poem = PoetryQuest(); poemFeedback = ""
        UserDefaults.standard.removeObject(forKey: "nibbiPoem")
    }
    private func handle(_ tool: ClientToolCallEvent, on call: Conversation) async {
        guard handledTools.insert(tool.toolCallId).inserted else { return }
        struct Line: Decodable { let line: String; let pair_index: Int }
        var result = "Open the Rhyme quest before submitting a poem line."
        if poemMode, tool.toolName == "submit_poem_line", let line = try? JSONDecoder().decode(Line.self, from: tool.parametersData) {
            let before = poem.lines.count
            let transcript = call.messages.last(where: { $0.role == .user })?.content ?? heardLine
            result = poem.submit(line.line, pairIndex: line.pair_index, heard: transcript)
            poemFeedback = poem.complete ? "Your AABB poem is saved. Nicely done!" : poem.lines.count > before ? "First rhyme saved! Now make a line that rhymes with day." : "Let’s try that line again. " + poem.hint
            if let data = try? JSONEncoder().encode(poem) { UserDefaults.standard.set(data, forKey: "nibbiPoem") }
            if poem.complete { UserDefaults.standard.set(true, forKey: "nibbiPoetBadge") }
        }
        do { try await call.sendToolResult(for: tool.toolCallId, result: result) }
        catch { self.error = "The rhyme was saved, but Nibbi lost the connection. Reconnect to continue." }
    }

    private struct DirectSetup: Decodable { let apiKey: String; let agentID: String }
    private struct Connection: Codable { let address: String; let pairingCode: String }
    private struct Session: Decodable { let token: String }
    private struct Failure: Decodable { let error: String }
    private func save() {
        UserDefaults.standard.set(address, forKey: "questVoiceAddress")
        UserDefaults.standard.set(pairingCode, forKey: "questVoicePairing")
    }

    private func report(_ message: String) {
        progress = message
        #if DEBUG
        // Stage names only: no tokens, URLs, audio, or transcripts.
        try? message.write(to: URL.documentsDirectory.appending(path: "voice-diagnostics.txt"), atomically: true, encoding: .utf8)
        #endif
    }

    func checkConnection() async {
        guard !checkingConnection, !busy else { return }
        checkingConnection = true
        defer { checkingConnection = false }
        connectionResult = nil
        report(hasDeviceKey ? "Checking ElevenLabs" : "Checking voice server")
        do {
            _ = try await sessionToken()
            connectionResult = "Connected. Nibbi is ready to call."
        } catch {
            connectionResult = error.localizedDescription
        }
        report(connectionResult ?? "Connection check finished")
    }

    private func sessionToken() async throws -> String {
        if hasDeviceKey { return try await directSessionToken() }
        guard let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(base.scheme ?? ""), base.host != nil, !pairingCode.isEmpty else {
            throw VoiceFailure("Open Character voices in Connection settings to connect Nibbi.")
        }
        var request = URLRequest(url: base.appending(path: "voice/session"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(pairingCode)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw VoiceFailure((try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "The voice server couldn't start a call.")
            }
            return try JSONDecoder().decode(Session.self, from: data).token
        } catch let failure as VoiceFailure { throw failure }
        catch let failure as URLError {
            if failure.code == .cancelled { throw CancellationError() }
            throw VoiceFailure("Your iPhone couldn't reach the voice server. Keep your Mac running on the same Wi-Fi and enable Local Network in iPhone Settings → PocketRealm. (Network \(failure.code.rawValue))")
        }
    }

    func saveDeviceKey(_ key: String) {
        do {
            try VoiceKeyStore.save(key)
            hasDeviceKey = true
            error = nil
            connectionResult = "Key saved securely on this iPhone. Check connection to verify it."
        } catch {
            connectionResult = "Couldn't save the key. Unlock your phone and try again."
        }
    }

    func removeDeviceKey() {
        do {
            try VoiceKeyStore.remove()
            hasDeviceKey = false
            connectionResult = "Voice key removed from this iPhone."
        } catch { connectionResult = "Couldn't remove the key. Try again." }
    }

    private func directSessionToken() async throws -> String {
        guard let key = VoiceKeyStore.read(), !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceFailure("Add your ElevenLabs key and Nibbi agent ID in Character voices.")
        }
        var url = URLComponents(string: "https://api.elevenlabs.io/v1/convai/conversation/token")!
        url.queryItems = [URLQueryItem(name: "agent_id", value: agentID.trimmingCharacters(in: .whitespacesAndNewlines)),
                         URLQueryItem(name: "source", value: "swift_sdk"), URLQueryItem(name: "version", value: ElevenLabs.version)]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 12
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let message: String
                switch status {
                case 401, 403: message = "ElevenLabs rejected the key. Check that it has ElevenAgents access."
                case 404: message = "Nibbi's agent wasn't found. Check the agent ID."
                case 429: message = "ElevenLabs is busy or your account has reached its limit. Try again shortly."
                default: message = "ElevenLabs couldn't start the call (HTTP \(status)). Try again shortly."
                }
                throw VoiceFailure(message)
            }
            return try JSONDecoder().decode(Session.self, from: data).token
        } catch let failure as VoiceFailure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch {
            throw VoiceFailure("Your iPhone couldn't reach ElevenLabs. Check your internet connection and try again.")
        }
    }

    private struct VoiceFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    func start(context: String) {
        guard !busy else { return }
        error = nil
        heardLine = ""; handledTools.removeAll()
        let id = UUID()
        attempt = id
        connecting = true
        report("Waiting for microphone permission…")
        startTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.attempt == id { self.connecting = false; self.startTask = nil; self.timeoutTask?.cancel(); self.timeoutTask = nil } }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard self.attempt == id, !Task.isCancelled else { return }
            guard allowed else {
                self.error = "Allow Microphone in iPhone Settings → PocketRealm to talk to Nibbi."
                return
            }
            do {
                self.timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(35)) } catch { return }
                    guard let self, self.attempt == id, self.connecting else { return }
                    let stage = self.progress
                    self.stop()
                    self.error = "The call timed out while \(stage.lowercased()). Please try again."
                    self.report("Call timed out: \(stage)")
                }
                self.report(self.hasDeviceKey ? "Connecting to ElevenLabs…" : "Connecting to your voice server…")
                let token = try await self.sessionToken()
                try Task.checkCancellation()
                self.report("Connecting Nibbi's audio…")
                let call = try await ElevenLabs.startConversation(conversationToken: token,
                    config: ConversationConfig(
                        agentOverrides: AgentOverrides(firstMessage: self.poemMode ? self.poem.opening : nil),
                        ttsOverrides: TTSOverrides(voiceId: CharacterVoices.voiceID(for: .nibbi)),
                        dynamicVariables: ["quest_context": context, "quest_mode": self.poemMode ? "poem" : "chat", "poem_state": self.poem.context],
                        onStartupStateChange: { [weak self] state in
                            Task { @MainActor in
                                guard let self, self.attempt == id else { return }
                                switch state {
                                case .resolvingToken: self.report("Opening voice session…")
                                case .connectingRoom: self.report("Connecting Nibbi's audio…")
                                case .waitingForAgent: self.report("Waiting for Nibbi…")
                                case .sendingConversationInit, .agentReady: self.report("Getting Nibbi ready…")
                                default: break
                                }
                            }
                        }, startupConfiguration: .init(agentReadyTimeout: 10),
                        onUserTranscript: { [weak self] text, _ in
                            Task { @MainActor in guard let self, self.attempt == id else { return }; self.heardLine = text }
                        }))
                guard self.attempt == id, !Task.isCancelled else {
                    await call.endConversation()
                    return
                }
                self.conversation = call
                self.toolSubscription = call.$pendingToolCalls.sink { [weak self, weak call] pending in
                    guard let self, let call else { return }
                    for tool in pending { Task { @MainActor in
                        guard self.attempt == id else { return }
                        await self.handle(tool, on: call)
                    } }
                }
                self.report("Call connected")
            } catch {
                guard self.attempt == id, !Task.isCancelled else { return }
                self.error = (error as? VoiceFailure)?.message ?? "Nibbi’s audio connection failed. Try again, or try a different Wi-Fi network."
                self.report(self.error ?? "Call failed")
            }
        }
    }

    func stop() {
        attempt = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        startTask?.cancel()
        startTask = nil
        connecting = false
        toolSubscription = nil
        let call = conversation
        conversation = nil
        Task { await call?.endConversation() }
    }
}

struct QuestVoiceSheet: View {
    @ObservedObject var voice: QuestVoice
    let context: String
    var poetry = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let conversation = voice.conversation {
                    if poetry { ScrollView { poemCard }.frame(maxHeight: 250) }
                    QuestVoiceCall(conversation: conversation, onEnd: voice.stop)
                } else {
                    ScrollView { VStack(spacing: 20) {
                    if poetry { poemCard }
                    Image(systemName: poetry ? "text.quote" : "waveform.circle.fill").font(.system(size: poetry ? 28 : 64)).foregroundStyle(.green)
                    Text(voice.connecting ? voice.progress : poetry ? "A poem for two" : "A little baking company")
                        .font(.title2.weight(.semibold))
                    Text(poetry ? "Nibbi gives two starter lines. Say a rhyming line after each one to earn Sugar-star Poet." : "Ask for a quest hint or dream up a cookie together. Nibbi listens while the call is on.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if let error = voice.error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("questVoiceError") }
                    Button { voice.connecting ? voice.stop() : voice.start(context: context) } label: {
                        Label(voice.connecting ? "Cancel" : "Talk to Nibbi", systemImage: voice.connecting ? "xmark" : "mic.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).tint(.green)
                    Text("Your voice and quest step are sent to ElevenLabs. Camera images and room scans aren't shared. Calls last up to 5 minutes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity) }
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(poetry ? "Nibbi’s rhyme quest" : "Talk with Nibbi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { voice.stop(); dismiss() } } }
        }
        .presentationDetents(poetry ? [.large] : [.medium, .large]).presentationDragIndicator(.visible)
        .onAppear { voice.poemMode = poetry }
        .onDisappear { voice.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { voice.stop() } }
    }
    private var poemCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A  " + PoetryQuest.first)
            Text("A  " + (voice.poem.lines.first ?? "Your rhyming line…")).foregroundStyle(.secondary)
            Text("B  " + PoetryQuest.third)
            Text("B  " + (voice.poem.lines.count > 1 ? voice.poem.lines[1] : "Your rhyming line…")).foregroundStyle(.secondary)
            if voice.poem.complete {
                Label("Sugar-star Poet · earned", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                if !voice.busy { Button("Make a new poem") { voice.resetPoem() } }
            } else {
                Text(voice.poem.hint).font(.caption)
            }
            if !voice.poemFeedback.isEmpty { Text(voice.poemFeedback).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

}

private struct QuestVoiceCall: View {
    @ObservedObject var conversation: Conversation
    let onEnd: () -> Void
    private var status: String {
        switch conversation.state {
        case .idle, .connecting: return "Connecting…"
        case .ended: return "Chat finished"
        case .error: return "Connection interrupted"
        case .active:
            if conversation.isMuted { return "Microphone muted" }
            switch conversation.agentState {
            case .listening: return "Nibbi is listening"
            case .speaking: return "Nibbi is speaking"
            case .thinking: return "Nibbi is thinking"
            }
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            Label(status, systemImage: conversation.isMuted ? "mic.slash.fill" : "waveform")
                .font(.headline).accessibilityAddTraits(.updatesFrequently)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .user ? "You" : "Nibbi").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(message.content)
                            }.id(message.id).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.onChange(of: conversation.messages.count) { _, _ in
                    if let last = conversation.messages.last { scroll.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack {
                Button {
                    Task {
                        do { try await conversation.setMuted(!conversation.isMuted) }
                        catch { onEnd() }
                    }
                } label: { Label(conversation.isMuted ? "Unmute" : "Mute", systemImage: conversation.isMuted ? "mic.slash" : "mic") }
                    .buttonStyle(.bordered).disabled(!conversation.state.isActive)
                Button("End chat", role: .destructive, action: onEnd).buttonStyle(.borderedProminent)
            }.frame(minHeight: 44)
        }
    }
}

struct QuestVoiceSettings: View {
    @ObservedObject var voice: QuestVoice
    @State private var keyEntry = ""
    @State private var selectedFriend = RealmFriend.nibbi
    @State private var selectedVoice = CharacterVoices.voiceID(for: .nibbi)
    @StateObject private var previewNarrator = QuestNarrator()
    var body: some View {
        Form {
            Section("Character voices") {
                Picker("Character", selection: $selectedFriend) { ForEach(RealmFriend.allCases) { Text($0.name).tag($0) } }
                if !voice.voices.isEmpty {
                    Picker("Voice", selection: $selectedVoice) {
                        if !voice.voices.contains(where: { $0.id == selectedVoice }) { Text("Saved voice").tag(selectedVoice) }
                        ForEach(voice.voices) { Text($0.name).tag($0.id) }
                    }
                }
                Button("Preview this voice") { previewNarrator.speak("Hey, I’m \(selectedFriend.name). Let’s make a little adventure together.", friend: selectedFriend) }.disabled(voice.busy)
                Button("Refresh my voices") { Task { await voice.loadVoices() } }
                Link("Explore ElevenLabs Voice Library", destination: URL(string: "https://elevenlabs.io/app/voice-library")!)
                Text("Add a favorite to My Voices in ElevenLabs, then refresh here. Nibbi uses your selection on the next call.").font(.footnote)
                if let message = voice.voiceListError { Text(message).font(.footnote) }
                if let message = previewNarrator.notice { Text(message).font(.footnote) }
            }
            Section("Direct ElevenLabs connection") {
                Text(voice.hasDeviceKey ? "Key saved on this iPhone" : "Use your own ElevenLabs key")
                SecureField("ElevenLabs API key", text: $keyEntry).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Nibbi agent ID", text: $voice.agentID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save key on iPhone") { voice.saveDeviceKey(keyEntry); keyEntry = "" }.disabled(keyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voice.busy)
                if voice.hasDeviceKey { Button("Remove saved key", role: .destructive) { voice.removeDeviceKey() }.disabled(voice.busy) }
                Text("Stored in the iPhone Keychain. Calls connect directly to ElevenLabs; your Mac can be offline.").font(.footnote)
            }
            if !voice.hasDeviceKey { Section("Mac voice server") {
                TextField("Server address", text: $voice.address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Pairing code", text: $voice.pairingCode).textInputAutocapitalization(.never).autocorrectionDisabled()
            } }
            Section("Voice connection") {
                Button(voice.checkingConnection ? "Checking…" : "Check connection") { Task { await voice.checkConnection() } }
                    .disabled(voice.checkingConnection || voice.busy)
                if let result = voice.connectionResult { Text(result).font(.footnote) }
            }
            Section {
                if !voice.hasDeviceKey { Text("Keep the voice server running on your Mac and connect your iPhone to the same network.") }
                NavigationLink("Try Nibbi’s rhyme quest") {
                    QuestVoiceSheet(voice: voice, context: "Playing the AABB rhyme quest.", poetry: true)
                }
                NavigationLink("Try talking to Nibbi") {
                    QuestVoiceSheet(voice: voice, context: "Meeting Nibbi before the quest. No sugar star collected yet.")
                }
            }
        }.navigationTitle("Character voices")
            .task { await voice.loadVoices() }
            .onChange(of: selectedFriend) { _, friend in previewNarrator.stop(); selectedVoice = CharacterVoices.voiceID(for: friend) }
            .onChange(of: selectedVoice) { _, id in UserDefaults.standard.set(id, forKey: "characterVoice.\(selectedFriend.rawValue)"); previewNarrator.stop() }
            .onDisappear { previewNarrator.stop() }
    }
}

private enum VoiceKeyStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hacklanta.PocketRealm.elevenlabs",
        kSecAttrAccount as String: "api-key"
    ]
    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw StorageFailure() }
        let attributes: [String: Any] = [kSecValueData as String: Data(clean.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageFailure() }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageFailure() }
    }
    private struct StorageFailure: Error {}
}

@MainActor
enum CharacterVoices {
    static func voiceID(for friend: RealmFriend) -> String {
        if let saved = UserDefaults.standard.string(forKey: "characterVoice.\(friend.rawValue)"), !saved.isEmpty { return saved }
        switch friend {
        case .nibbi, .pufflo: return "cgSgspJ2msm6clMCkdW9" // Jessica
        case .bloopi, .glimlo: return "FGY2WhTYpPnrIDTdsKH5" // Laura
        case .pebblin: return "JBFqnCBsd6RMkjVDRZzb" // George
        case .mosskip: return "XrExE9yKIg1WjnnlVkGX" // Matilda
        case .dottli: return "pFZP5JQG7iQjIQuC4Bku" // Lily
        case .cindlet, .trufflet: return "bIHbv24MWmeRgasZH58o" // Will
        }
    }
}

/// Narration never opens the microphone. A stale request cannot play after stop/replay.
@MainActor
final class QuestNarrator: ObservableObject {
    @Published private(set) var loading = false
    @Published private(set) var notice: String?
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private let fallback = AVSpeechSynthesizer()
    private var generation = UUID()
    var isSpeaking: Bool { player?.isPlaying == true || fallback.isSpeaking }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        player?.stop(); player = nil
        fallback.stopSpeaking(at: .immediate)
        loading = false
    }
    func speak(_ text: String, friend: RealmFriend) {
        stop()
        notice = nil
        let id = generation
        guard let key = VoiceKeyStore.read() else { systemSpeak(text); return }
        let voiceID = CharacterVoices.voiceID(for: friend)
        loading = true
        task = Task {
            defer { if generation == id { loading = false; task = nil } }
            do {
                var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!)
                request.httpMethod = "POST"
                request.timeoutInterval = 12
                request.setValue(key, forHTTPHeaderField: "xi-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "text": text, "model_id": "eleven_flash_v2_5",
                    "voice_settings": ["stability": 0.65, "similarity_boost": 0.75, "style": 0.0]])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard generation == id, !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(data: data)
                player?.play()
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                notice = "Using the iPhone voice while ElevenLabs narration is unavailable."
                systemSpeak(text)
            }
        }
    }
    private func systemSpeak(_ text: String) {
        let line = AVSpeechUtterance(string: text)
        line.rate = 0.46
        fallback.speak(line)
    }
}
