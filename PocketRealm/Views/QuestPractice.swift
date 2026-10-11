import Combine
import SwiftUI

/// Practice never touches Adventure or the stored friendship badges.
struct QuestPractice: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var narrator = QuestNarrator()
    @State private var game: QuestGame
    @State private var reaction: FriendReaction = .greeting
    @State private var command = 0
    @State private var error: String?
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(blueprint: QuestBlueprint) { _game = State(initialValue: QuestGame(blueprint: blueprint)) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FriendPreviewSurface(friend: game.blueprint.friend, reaction: reaction, command: command, error: $error)
                            .frame(height: min(210, geometry.size.height * 0.3)).clipShape(RoundedRectangle(cornerRadius: 24))
                        if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button { readObjective() } label: { Label("Hear the objective", systemImage: "speaker.wave.2.fill").frame(minHeight: 44) }
                        if let notice = narrator.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        Label("Just for fun · practice together", systemImage: "heart.fill").font(.caption).foregroundStyle(.white.opacity(0.75))
                        if game.solved {
                            Label(game.blueprint.rewardName, systemImage: "gift.fill").font(.title2.bold())
                            Text(game.feedback)
                            Text("Play this quest in your room to earn \(game.blueprint.friend.reward).").font(.subheadline).foregroundStyle(.secondary)
                            Button("Play again") { restart(next: false) }.buttonStyle(.borderedProminent)
                        } else { QuestPanel(game: game, showsActions: false, perform: perform) }
                        Button("Try another variation") { restart(next: true) }.font(.subheadline).buttonStyle(.bordered).frame(minHeight: 44)
                    }.padding(20)
                }.safeAreaInset(edge: .bottom, spacing: 0) {
                    if !game.solved {
                        QuestActions(game: game, perform: perform).padding(16)
                            .background(Color(red: 0.055, green: 0.095, blue: 0.10))
                    }
                }
            }.background(Color(red: 0.055, green: 0.095, blue: 0.10)).foregroundStyle(.white)
                .navigationTitle(game.blueprint.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .preferredColorScheme(.dark)
        }
        .onAppear { readObjective() }
        .onDisappear { narrator.stop() }
        .onReceive(timer) { _ in
            let before = game.highlightedID
            game.advancePlayback(delta: 0.05, available: scenePhase == .active)
            if let cue = game.highlightedID, before != cue { react(.bloopMove(cue)) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { narrator.stop(); game.advancePlayback(delta: 0, available: false) }
        }
    }

    private func perform(_ action: QuestAction) {
        if case .replay = action { narrator.stop() }
        let result = game.perform(action)
        guard result != .ignored else { return }
        if case .hint = action { narrator.speak(game.feedback, friend: game.blueprint.friend) }
        if case .submit = action { narrator.speak(game.feedback, friend: game.blueprint.friend) }
        switch result {
        case .won: react(.celebrate)
        case .retry: react(.puzzled)
        case .roundWon: react(.play)
        default:
            if case .replay = action, let cue = game.highlightedID { react(.bloopMove(cue)) }
            else if case .select(let cue) = action, game.blueprint.kind == .memory { react(.bloopMove(cue)) }
            else { react(.chat) }
        }
    }
    private func readObjective() { narrator.speak(game.blueprint.introduction + " " + game.blueprint.instructions, friend: game.blueprint.friend) }
    private func react(_ value: FriendReaction) { reaction = value; command += 1 }
    private func restart(next: Bool) {
        let choices = QuestBlueprint.allCases.filter { $0.friend == game.blueprint.friend }
        let index = choices.firstIndex(of: game.blueprint) ?? 0
        game = QuestGame(blueprint: next ? choices[(index + 1) % choices.count] : game.blueprint)
        react(.greeting)
        readObjective()
    }
}
