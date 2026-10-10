import SwiftUI

/// Shared controls for the real AR quest and the explicitly labeled practice mode.
struct QuestPanel: View {
    let game: QuestGame
    var enabled = true
    var showsActions = true
    let perform: (QuestAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let accent = Color(red: 0.80, green: 0.98, blue: 0.59)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(game.blueprint.instructions).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if game.blueprint.kind == .warmth {
                HStack {
                    Image(systemName: "flame.fill")
                    Text("\(game.warmth) / \(game.blueprint.targetWarmth) warmth").monospacedDigit()
                    Spacer()
                    Text(game.warmth > game.blueprint.targetWarmth ? "Too toasty!" : "Oven meter")
                        .font(.caption)
                }.font(.headline).foregroundStyle(game.warmth > game.blueprint.targetWarmth ? .orange : accent)
                ProgressView(value: Double(min(game.warmth, game.blueprint.targetWarmth)), total: Double(game.blueprint.targetWarmth)).tint(accent)
            } else if game.blueprint.kind == .recipe {
                Text("Mixing bowl · \(game.selected.count) of 3 ingredients").font(.caption.bold()).foregroundStyle(accent)
            } else {
                HStack {
                    Text("Verse \(min(3, game.round + 1)) of 3")
                    Spacer()
                    Text(game.memoryStage == .showing ? "Watch Bloopi" : game.memoryStage == .recalling ? "Your turn · \(game.inputIndex)/\(game.roundPattern.count)" : "Ready to listen")
                }.font(.caption.bold()).foregroundStyle(accent)
                if let coaching = game.coaching { Text(coaching).font(.subheadline.bold()).foregroundStyle(accent) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : game.blueprint.kind == .memory ? 3 : 2), spacing: 8) {
                ForEach(game.blueprint.options) { option in
                    optionButton(option)
                }
            }
            Text(game.feedback).font(.subheadline).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("questFeedback")
            if showsActions { QuestActions(game: game, enabled: enabled, perform: perform) }
            Label("Take your time. You can always try again.", systemImage: "heart")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }.foregroundStyle(.white.opacity(0.9)).disabled(!enabled || game.solved)
    }

    private func optionButton(_ option: QuestOption) -> some View {
        let selected = game.selected.contains(option.id)
        let highlighted = game.highlightedID == option.id
        let active = selected || highlighted
        return Button { perform(.select(option.id)) } label: {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: option.symbol)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.caption) }
                }.font(.title3)
                Text(option.name).font(game.blueprint.kind == .warmth ? .title2.bold() : .subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !option.caption.isEmpty { Text(option.caption).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, minHeight: 62).padding(8)
                .foregroundStyle(active ? Color.black : .white)
                .background(active ? accent : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? accent : .white.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain)
            .disabled(game.blueprint.kind == .memory && game.memoryStage != .recalling)
            .accessibilityLabel(option.name + (option.caption.isEmpty ? "" : ", " + option.caption))
            .accessibilityValue(highlighted ? "Bloopi's move" : selected ? "Selected" : "")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("quest_" + option.id)
    }
}

/// Kept outside the scrolling puzzle so help and the next action stay within reach.
struct QuestActions: View {
    let game: QuestGame
    var enabled = true
    let perform: (QuestAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let accent = Color(red: 0.80, green: 0.98, blue: 0.59)

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button { perform(game.blueprint.kind == .memory ? .replay : .submit) } label: {
                Label(primaryTitle, systemImage: game.blueprint.kind == .memory ? "play.fill" : "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 12)
                    .foregroundStyle(primaryDisabled ? .white.opacity(0.7) : Color(red: 0.055, green: 0.095, blue: 0.10))
                    .background(primaryDisabled ? .white.opacity(0.08) : accent, in: RoundedRectangle(cornerRadius: 14))
            }.disabled(primaryDisabled)
                .accessibilityIdentifier("questSubmit")
            Button { perform(.hint) } label: {
                Label("Hint", systemImage: "lightbulb")
                    .frame(minWidth: 68, minHeight: 44).padding(.horizontal, 12)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("questHint")
        }.font(.subheadline.bold()).foregroundStyle(accent).buttonStyle(.plain)
            .disabled(!enabled || game.solved).opacity(enabled ? 1 : 0.5)
    }

    private var primaryDisabled: Bool {
        game.blueprint.kind == .memory ? game.memoryStage == .showing : !game.canSubmit
    }
    private var primaryTitle: String {
        if game.blueprint.kind == .memory {
            return game.memoryStage == .showing ? "Watching…" : game.memoryStage == .ready && game.attempts == 0 ? "Watch verse" : "Watch again"
        }
        return game.blueprint.kind == .recipe ? "Taste test" : "Try the oven"
    }
}

/// An in-place drawer leaves the camera interactive above it. Only its header owns
/// the drag gesture, so scrolling ingredients never accidentally hides a puzzle.
struct QuestDrawer<Content: View, Footer: View>: View {
    @Binding var isExpanded: Bool
    let friend: RealmFriend
    let label: String
    let title: String
    let summary: String
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var drag: CGFloat = 0
    private let accent = Color(red: 0.80, green: 0.98, blue: 0.59)

    var body: some View {
        VStack(spacing: 0) {
            Button { isExpanded.toggle() } label: {
                VStack(spacing: 8) {
                    Capsule().fill(.white.opacity(0.3)).frame(width: 34, height: 4)
                    HStack(spacing: 12) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(friend.rawValue).resizable().scaledToFill()
                                .frame(width: 44, height: 48).clipShape(RoundedRectangle(cornerRadius: 13))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label).font(.caption2.weight(.bold)).foregroundStyle(accent)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                                .multilineTextAlignment(.leading).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                            .frame(width: 32, height: 44)
                    }
                    if !isExpanded {
                        Text(summary).font(.subheadline).foregroundStyle(.white.opacity(0.76))
                            .multilineTextAlignment(.leading).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !dynamicTypeSize.isAccessibilitySize {
                        Text("Swipe down to see more of your room")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 14)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(label). \(title). \(isExpanded ? "Hide details" : summary)")
                .accessibilityValue(isExpanded ? "Expanded" : "Tucked away")
                .accessibilityHint(isExpanded ? "Double tap to tuck away. Your progress stays." : "Double tap to show details and controls.")
                .accessibilityIdentifier("questDrawerToggle")
                .accessibilityAction(named: isExpanded ? "Tuck away quest" : "Expand quest") { isExpanded.toggle() }
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .updating($drag) { value, state, _ in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        state = isExpanded ? min(80, max(0, value.translation.height)) : max(-35, min(0, value.translation.height))
                    }
                    .onEnded { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        let distance = value.translation.height
                        if distance > 35 || (distance > 12 && value.predictedEndTranslation.height > 90) { isExpanded = false }
                        if distance < -35 || (distance < -12 && value.predictedEndTranslation.height < -90) { isExpanded = true }
                    })
            if isExpanded {
                ScrollView {
                    content().frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                }.scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("questDrawerContent")
                    .transition(.opacity)
            }
            footer()
        }
        .frame(maxHeight: isExpanded ? maxHeight : nil)
        .fixedSize(horizontal: false, vertical: !isExpanded)
        .background(Color(red: 0.055, green: 0.095, blue: 0.10).opacity(0.97), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .offset(y: reduceMotion ? 0 : drag)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
        .animation(.easeOut(duration: 0.2), value: drag)
    }
}
