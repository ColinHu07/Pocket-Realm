import RealityKit
import SwiftUI
import UIKit

private let ink = Color(red: 0.055, green: 0.095, blue: 0.10)
private let lime = Color(red: 0.80, green: 0.98, blue: 0.59)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.89)

struct ContentView: View {
    @ObservedObject var experience: ARExperience
    @State private var previewFriend: RealmFriend?
    @State private var drawerExpanded = true
    @State private var roomLocationsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if experience.started { adventure }
            else { welcome }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: experience.phase)
        .onChange(of: experience.phase) { _, phase in
            // Walking objectives stay small. Review and deliberate play open the controls.
            drawerExpanded = [.scanning, .planning, .restoring, .ready, .challenge, .playing, .complete].contains(phase)
            experience.setChallengePanelVisible(drawerExpanded)
            roomLocationsExpanded = false
        }
        .onChange(of: experience.started) { _, _ in
            drawerExpanded = true
            experience.setChallengePanelVisible(true)
        }
        .onChange(of: drawerExpanded) { _, expanded in experience.setChallengePanelVisible(expanded) }
        .sheet(isPresented: $experience.connectionPresented) { connection }
        .sheet(isPresented: $experience.themePresented) { themePicker }
        .sheet(item: $previewFriend) { FriendPreview(friend: $0) }
        .fullScreenCover(isPresented: Binding(get: { experience.drawingPresented && !experience.started },
                                              set: { experience.drawingPresented = $0 })) {
            DrawingCaptureView(title: experience.drawingTitle, prompt: experience.drawingPrompt, source: .camera,
                               onUse: experience.submitDrawing, onClose: { experience.drawingPresented = false })
        }
        .alert("A little help needed", isPresented: Binding(get: { experience.issue != nil }, set: { if !$0 { experience.dismissIssue() } })) {
            if experience.cameraDenied {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Button("OK", role: .cancel) { experience.dismissIssue() }
        } message: { Text(experience.issue ?? "") }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        brand
                        Spacer()
                        Button { experience.connectionPresented = true } label: {
                            Image(systemName: "gearshape").font(.body)
                                .frame(width: 44, height: 44).foregroundStyle(lime)
                        }.accessibilityLabel("Connection settings")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your room.\nA world of its own.")
                            .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.5).foregroundStyle(paper)
                        Text("A little adventure, right at home. Choose a friend and make some room for wonder.")
                            .font(.system(size: 16)).foregroundStyle(paper.opacity(0.65)).lineSpacing(3)
                    }
                    friendPicker
                    Button { previewFriend = experience.friend } label: {
                        Label("Meet \(experience.friend.name) · try playing", systemImage: "heart.circle.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(lime)
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("previewFriend")
                    Button { experience.themePresented = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: experience.theme.symbol)
                                .font(.system(size: 23)).foregroundStyle(lime)
                                .frame(width: 46, height: 46).background(lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Room theme · \(experience.theme.name)").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(paper)
                                Text("Turn your space into somewhere new.").font(.system(size: 12)).foregroundStyle(paper.opacity(0.6))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(lime).font(.system(size: 12, weight: .semibold))
                        }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain).accessibilityIdentifier("roomThemeButton")
                    HStack(spacing: 16) {
                        Image(experience.friend.rawValue).resizable().scaledToFill()
                            .frame(width: 104, height: 120).clipShape(RoundedRectangle(cornerRadius: 22))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Label(experience.friend.role, systemImage: experience.friend.symbol)
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(lime)
                            Text(experience.friend.personality)
                                .font(.system(size: 14)).foregroundStyle(paper.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                            Text("QUEST · " + experience.friend.questTitle)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(lime)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
                    drawingCard
                    VStack(spacing: 16) {
                        step("01", "Take a 360° look around", "A slow sweep captures visible walls and furniture.")
                        step("02", "Make a little magic", "Choose a world for your walls, with little surprises to find.")
                        step("03", "Draw your way through", "Meet \(experience.friend.name). When something's in the way, draw a solution and watch it come to life.")
                    }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 0)
                }.padding(24).frame(minHeight: geometry.size.height)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let date = experience.savedRoomDate {
                    action("Use saved room", icon: "house.fill", action: experience.useSavedRoom)
                        .accessibilityIdentifier("useSavedRoom")
                    HStack {
                        Text("Saved \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(paper.opacity(0.6))
                        Spacer()
                        Menu {
                            Button("Scan a new room", action: experience.start)
                            Button("Forget saved room", role: .destructive, action: experience.forgetSavedRoom)
                        } label: { Label("Room options", systemImage: "ellipsis.circle").font(.subheadline).foregroundStyle(lime).frame(minHeight: 44) }
                    }
                } else { action("Scan my room", icon: "viewfinder") { experience.start() } }
                if let notice = experience.savedRoomNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                Text(experience.savedRoomDate == nil
                    ? "New scans go to \(experience.provider.name). Your room and plan are then saved on this iPhone."
                    : "Reuse your room offline. Camera snapshots aren't saved.")
                    .font(.system(size: 10)).foregroundStyle(paper.opacity(0.55)).multilineTextAlignment(.center)
            }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12).background(ink)
        }
    }

    private var drawingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { experience.openDrawing(.sidekick) } label: {
                HStack(spacing: 14) {
                    thumbnail(experience.sidekickDrawing.isWorking ? experience.sidekickPhoto : experience.sidekick?.photo ?? experience.sidekickPhoto,
                              placeholder: "pencil.and.scribble", size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experience.sidekick.map { "Sidekick · \($0.card.title.isEmpty ? $0.card.name : $0.card.title)" } ?? "Draw a sidekick")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(paper)
                        Text(sidekickStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(failed(experience.sidekickDrawing) ? .orange : paper.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if experience.sidekickDrawing.isWorking { ProgressView().tint(lime) }
                    else {
                        Image(systemName: experience.sidekick == nil ? "chevron.right" : "pencil")
                            .foregroundStyle(lime).font(.system(size: 12, weight: .semibold))
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("drawingButton")
                .accessibilityHint("Opens the camera to photograph a paper drawing")
            if !experience.addressIsValid {
                Button("Connect drawing workshop", action: experience.openWorkshopSettings)
                    .font(.subheadline).foregroundStyle(lime).frame(minHeight: 44)
            }
            if !experience.inventory.isEmpty {
                Text("YOUR CREATIONS · TAP TO MAKE ONE YOUR SIDEKICK").tracking(1)
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(lime.opacity(0.8))
                creationStrip(selected: experience.sidekick?.id) { experience.chooseSidekick($0) }
            }
        }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }

    private var sidekickStatus: String {
        switch experience.sidekickDrawing {
        case .none, .ready:
            if let sidekick = experience.sidekick { return Workshop.arrival(sidekick.card) }
            return "Draw anything on paper and bring it along as a 3D companion."
        case .failed(let reason): return reason
        default: return Workshop.whimsy(experience.whimsy, friend: experience.friend.name)
        }
    }

    private func failed(_ progress: DrawingProgress) -> Bool {
        if case .failed = progress { return true }
        return false
    }

    private func thumbnail(_ image: UIImage?, placeholder: String, size: CGFloat) -> some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: placeholder).font(.system(size: size * 0.45)).foregroundStyle(lime) }
        }.frame(width: size, height: size).background(lime.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: size * 0.3))
    }

    private func creationStrip(selected: String?, choose: @escaping (Creation) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(experience.inventory) { creation in
                    Button { choose(creation) } label: {
                        VStack(spacing: 5) {
                            thumbnail(creation.photo, placeholder: "cube.fill", size: 54)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected == creation.id ? lime : .clear, lineWidth: 2))
                            Text(creation.card.title.isEmpty ? creation.card.name : creation.card.title)
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(paper.opacity(0.8)).lineLimit(1)
                            Text(creation.card.kind.rawValue.uppercased()).font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(lime.opacity(0.7))
                        }.frame(width: 66)
                    }.buttonStyle(.plain).accessibilityLabel("\(creation.card.name), \(creation.card.kind.rawValue)")
                }
            }
        }
    }

    /// The sidekick traveling with you; tap to hear from them.
    @ViewBuilder private var sidekickPill: some View {
        if let sidekick = experience.sidekick, !experience.sidekickDrawing.isWorking {
            Button(action: experience.talkToSidekick) {
                HStack(spacing: 7) {
                    thumbnail(sidekick.photo, placeholder: "face.smiling", size: 26)
                    Text("Talk")
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(lime)
                    .padding(.leading, 6).padding(.trailing, 14).frame(minHeight: 40)
                    .background(.ultraThinMaterial, in: Capsule())
            }.accessibilityLabel("Talk to your sidekick, \(sidekick.card.displayName)")
        } else if experience.sidekickDrawing.isWorking {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini).tint(lime)
                Text("Sidekick on the way…")
            }.font(.system(size: 12, weight: .semibold)).foregroundStyle(lime)
                .padding(.horizontal, 14).frame(minHeight: 40).background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder private var challengeControls: some View {
        if let helper = experience.helper, let progress = experience.trapProgress {
            HStack(spacing: 6) {
                ForEach(0..<progress.needed, id: \.self) { index in
                    Circle().fill(index < progress.done ? lime : .white.opacity(0.18)).frame(width: 9, height: 9)
                }
                Spacer()
                Text(helper.card.kind.rawValue.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(lime.opacity(0.7))
            }
            action(experience.itemInReach ? "\(helper.card.verbButton) (\(progress.remaining) to go)" : "Walk to the \(experience.questCategory)",
                   icon: helper.card.kind == .tool ? "hand.tap.fill" : "sparkles",
                   enabled: experience.trackingReady && experience.itemInReach, action: experience.useHelper)
            HStack(spacing: 18) {
                if helper.card.kind == .character {
                    Button(action: experience.talkToHelper) { Label("Talk to \(helper.card.displayName)", systemImage: "bubble.left.fill") }
                }
                Button { experience.openDrawing(.challenge) } label: { Label("Draw something else", systemImage: "pencil") }
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(lime)
            footnote("Move close to the obstacle near the \(experience.questCategory), then tap it or use the button.")
        } else if experience.challengeDrawing.isWorking {
            HStack(alignment: .top, spacing: 12) {
                if let photo = experience.challengePhoto { thumbnail(photo, placeholder: "pencil", size: 44) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { ProgressView().controlSize(.small).tint(lime); Text("In the workshop").font(.system(size: 13, weight: .semibold)) }
                        .foregroundStyle(lime)
                    Text(Workshop.whimsy(experience.whimsy, friend: experience.friend.name))
                        .font(.system(size: 14)).foregroundStyle(paper.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut, value: experience.whimsy)
                }
            }
            footnote("Head toward the \(experience.questCategory) while your drawing is being made.")
        } else {
            if case .failed(let reason) = experience.challengeDrawing {
                Text(reason).font(.subheadline).foregroundStyle(.orange)
            }
            action("Draw a solution", icon: "pencil.and.scribble") { experience.openDrawing(.challenge) }
            if !experience.inventory.isEmpty {
                Text("OR SEND IN SOMETHING YOU ALREADY DREW").tracking(1)
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(lime.opacity(0.8))
                creationStrip(selected: nil) { experience.deployHelper($0) }
            }
        }
        Button("Continue without a drawing", action: experience.skipDrawingChallenge)
            .font(.subheadline).foregroundStyle(lime).frame(minHeight: 44)
    }

    private var friendPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(RealmFriend.allCases) { friend in
                Button { experience.selectFriend(friend) } label: {
                    VStack(spacing: 0) {
                        Image(friend.rawValue).resizable().scaledToFit().accessibilityHidden(true)
                        HStack(spacing: 3) {
                            Text(friend.name).font(.system(size: 12, weight: .semibold, design: .rounded))
                            if experience.completedFriends.contains(friend.rawValue) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                            }
                        }.foregroundStyle(experience.friend == friend ? ink : paper).padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(experience.friend == friend ? lime : .white.opacity(0.06))
                    }.clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(experience.friend == friend ? lime : .clear, lineWidth: 2))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(friend.name), \(friend.role)")
                    .accessibilityAddTraits(experience.friend == friend ? [.isSelected] : [])
            }
        }
    }

    private var friendInteractions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { interactionButtons }
            VStack(spacing: 8) { interactionButtons }
        }.font(.subheadline.weight(.semibold)).foregroundStyle(lime).buttonStyle(.bordered)
            .disabled(!experience.trackingReady || !experience.inReach)
            .opacity(experience.trackingReady && experience.inReach ? 1 : 0.5)
    }

    @ViewBuilder private var interactionButtons: some View {
            Button(action: experience.pet) { Label("Pet", systemImage: "hand.draw").frame(minHeight: 32) }
            Button(action: experience.play) { Label("Play", systemImage: "sparkles").frame(minHeight: 32) }
            if experience.phase == .complete {
                Button(action: experience.chat) { Label("Chat", systemImage: "bubble.left.and.bubble.right").frame(minHeight: 32) }
            }
    }

    private var adventure: some View {
        GeometryReader { geometry in
            ZStack {
                ARSurface(experience: experience).ignoresSafeArea()
                if !experience.drawingPresented {
                    LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                    VStack(spacing: 10) {
                        adventureToolbar
                        HStack { Spacer(); sidekickPill }
                        if !experience.trackingReady {
                            Label(experience.trackingMessage, systemImage: "viewfinder")
                                .font(.subheadline).foregroundStyle(paper)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityIdentifier("trackingGuidance")
                        }
                        Spacer(minLength: 12)
                        QuestDrawer(isExpanded: $drawerExpanded, friend: experience.friend,
                                    label: objectiveLabel, title: drawerExpanded ? title : compactTitle,
                                    summary: compactSummary,
                                    maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.72 : 0.56)) {
                            questDetails
                        } footer: {
                            questFooter
                        }
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                }
                if experience.drawingPresented {
                    DrawingCaptureView(title: experience.drawingTitle, prompt: experience.drawingPrompt,
                        source: .ar { experience.captureDrawingFrame(guide: $0) },
                        onUse: experience.submitDrawing, onClose: { experience.drawingPresented = false })
                        .zIndex(2)
                }
            }
        }
    }

    private var adventureToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: experience.trackingReady ? "sparkle" : "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(experience.trackingReady ? lime : .orange)
                Text(experience.trackingReady ? (dynamicTypeSize.isAccessibilitySize ? "Your room" : "Your little realm") : "Finding your room")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.padding(.horizontal, 12).frame(minHeight: 44)
                .background(ink.opacity(0.8), in: Capsule())
            Spacer(minLength: 0)
            Button { experience.themePresented = true } label: {
                Image(systemName: experience.theme.symbol).font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).background(ink.opacity(0.8), in: Circle())
            }.accessibilityLabel("Change room theme. Current theme: \(experience.theme.name)")
                .accessibilityIdentifier("roomThemeButton")
            Menu {
                if experience.canReplayRoom {
                    Button("Replay this room") { experience.replayCurrentRoom() }
                    Menu("Try another friend in this room") {
                        ForEach(RealmFriend.allCases) { friend in
                            Button(friend.name) { experience.replayCurrentRoom(with: friend) }
                        }
                    }
                }
                Button("Choose another friend", action: experience.chooseAnotherFriend)
                Button("Scan again", action: experience.rescan)
                Button("Save room", action: experience.saveRoomAgain)
                    .disabled(experience.savingRoom || [.scanning, .planning, .restoring].contains(experience.phase))
                if experience.savedRoomDate != nil {
                    Button("Forget saved room", role: .destructive, action: experience.forgetSavedRoom)
                }
                Button("Connection settings") { experience.connectionPresented = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).background(ink.opacity(0.8), in: Circle())
            }.accessibilityLabel("Adventure options")
        }.foregroundStyle(paper)
    }

    private var objectiveLabel: String {
        if experience.phase == .scanning { return "LOOK AROUND · \(Int(experience.coverage.fraction * 100))%" }
        let label: String
        switch experience.phase {
        case .exploring, .revealed: label = "1 OF 3 · MEET \(experience.friend.name.uppercased())"
        case .challenge: label = "2 OF 3 · FREE THE KEEPSAKE"
        case .questing: label = "2 OF 3 · FIND THE KEEPSAKE"
        case .returning, .playing: label = "3 OF 3 · \(experience.game.challenge == nil ? "REUNITE" : "PLAY TOGETHER")"
        default: label = cardLabel
        }
        if experience.trackingReady, [.exploring, .challenge, .questing, .returning].contains(experience.phase),
           let distance = experience.objectiveDistance {
            return label + String(format: " · %.1f m", distance)
        }
        return label
    }

    private var compactTitle: String {
        switch experience.phase {
        case .exploring: return "Find \(experience.friend.name)"
        case .revealed: return "Hello, \(experience.friend.name)!"
        case .questing: return "Find the \(experience.friend.itemName)"
        case .returning: return "Back to \(experience.friend.name)"
        case .playing: return "Play with \(experience.friend.name)"
        case .complete: return "You and \(experience.friend.name), friends."
        default: return title
        }
    }

    private var compactSummary: String {
        switch experience.phase {
        case .scanning: return experience.scanInstruction
        case .planning: return experience.planningError == nil ? "Making a little magic. We'll let you know when it's ready." : "Your scan is safe. Open for retry options."
        case .restoring: return "Look at the same walls and furniture to settle back in."
        case .ready: return "Your room is ready. Open to take a look at the plan."
        case .exploring: return experience.proximity.armed ? detail : "Take a few steps back, then follow the clue. Tap for details."
        case .revealed: return experience.inReach ? "A new friend is ready to say hello." : "Move a little closer to say hello."
        case .challenge: return "Look near the \(experience.questCategory) for the blocked \(experience.friend.itemName). Tap for drawing options."
        case .questing: return "Look for a little glow by the \(experience.questCategory)."
        case .returning: return "Keepsake found! Your friend is waiting where you met."
        case .playing: return "Tap or swipe up to keep playing. Your progress stays."
        case .complete: return "\(experience.friend.reward) badge earned. Stay and play a while."
        }
    }

    private var questDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            if experience.phase != .playing {
                Text(detail).font(.body).foregroundStyle(paper.opacity(0.85)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch experience.phase {
            case .scanning:
                ProgressView(value: experience.coverage.fraction).tint(lime)
                    .accessibilityLabel("Room sweep").accessibilityValue("\(Int(experience.coverage.fraction * 100)) percent")
                Text("\(experience.objectCount) cozy spots found").font(.subheadline.weight(.medium)).foregroundStyle(lime)
                footnote(experience.coverage.complete && experience.objectCount == 0
                    ? "Look at a table, sofa, or cabinet so we can find a place for your friend."
                    : "Keep turning slowly. We'll finish the scan for you.")
            case .planning:
                if let error = experience.planningError {
                    Text(error).font(.subheadline).foregroundStyle(.orange)
                    Button("Connection settings") { experience.connectionPresented = true }
                        .frame(minHeight: 44).foregroundStyle(lime)
                } else {
                    HStack(spacing: 12) {
                        ProgressView().tint(lime)
                        Text(experience.requesting ? "Finding cozy spots and little surprises…" : "Putting the finishing touches on your scan…")
                    }.font(.subheadline).foregroundStyle(paper.opacity(0.75))
                }
            case .restoring:
                HStack(spacing: 12) {
                    ProgressView().tint(lime)
                    Text("Getting everything back in its place…").font(.subheadline).foregroundStyle(paper)
                }
                Button("Scan a new room", action: experience.start).frame(minHeight: 44).foregroundStyle(lime)
            case .ready:
                if let room = experience.plan?.room {
                    Label("Room accents", systemImage: "sparkles").foregroundStyle(lime)
                    Text(room.designNote).foregroundStyle(paper.opacity(0.8))
                    DisclosureGroup("Where the adventure happens", isExpanded: $roomLocationsExpanded) {
                        Text(room.questReason).foregroundStyle(paper.opacity(0.8)).padding(.top, 8)
                    }.tint(lime).foregroundStyle(lime).frame(minHeight: 44)
                }
                if let message = experience.roomSaveMessage {
                    Label(message, systemImage: experience.savingRoom ? "clock" : "internaldrive")
                        .font(.caption).foregroundStyle(lime)
                }
                if experience.theme != .original { footnote(experience.themeMessage) }
                else {
                    Button("Choose a room theme") { experience.themePresented = true }
                        .frame(minHeight: 44).font(.subheadline).foregroundStyle(lime)
                }
            case .exploring:
                Label(experience.proximity.armed ? "Walk closer. \(experience.friend.name) will pop out to meet you." : "Step back a little, then explore.", systemImage: "figure.walk")
                    .font(.subheadline).foregroundStyle(lime)
            case .revealed:
                friendInteractions
            case .challenge:
                challengeControls
                friendInteractions
            case .questing:
                Label("Look for a glowing \(experience.friend.itemName) by the \(experience.questCategory).", systemImage: experience.friend.symbol)
                    .font(.subheadline).foregroundStyle(lime)
                footnote("It floats beside the furniture. No need to open or move anything.")
                if experience.inReach { friendInteractions }
            case .returning:
                Label("\(experience.friend.itemName.capitalized) collected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(lime)
                if experience.inReach { friendInteractions }
            case .playing:
                if !experience.inReach { footnote("Come back to \(experience.friend.name) to continue. Your puzzle is saved.") }
                if let challenge = experience.game.challenge {
                    QuestPanel(game: challenge, enabled: experience.challengeAvailable, showsActions: false, perform: experience.playChallenge)
                }
            case .complete:
                if let challenge = experience.game.challenge {
                    Label(challenge.blueprint.rewardName, systemImage: "gift.fill")
                        .font(.subheadline.bold()).foregroundStyle(lime)
                }
                Label(experience.friend.reward + " · friendship badge", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime)
                friendInteractions
                footnote("\(experience.completedFriends.count) of \(RealmFriend.allCases.count) friendships made. Your badges are saved.")
            }
        }.foregroundStyle(paper)
    }

    private var questFooter: some View {
        VStack(spacing: 8) {
            switch experience.phase {
            case .ready:
                action("Start exploring", icon: "figure.walk", enabled: experience.trackingReady, action: experience.beginExploring)
            case .revealed where experience.inReach:
                action("Say hello", icon: "hand.wave.fill", enabled: experience.trackingReady, action: experience.talk)
            case .questing where experience.itemInReach:
                action("Collect keepsake", icon: "sparkles", enabled: experience.trackingReady, action: experience.collectKeepsake)
            case .returning where experience.inReach:
                action(experience.game.challenge == nil ? "Give the keepsake" : "Let's play together", icon: "gift", enabled: experience.trackingReady, action: experience.returnKeepsake)
            case .playing where drawerExpanded:
                if let challenge = experience.game.challenge {
                    QuestActions(game: challenge, enabled: experience.challengeAvailable, perform: experience.playChallenge)
                }
            case .complete where drawerExpanded:
                Button("Play again in this room") { experience.replayCurrentRoom() }
                    .frame(minHeight: 44).foregroundStyle(lime)
                action("Meet another friend", icon: "arrow.right", action: experience.chooseAnotherFriend)
            case .planning where experience.planningError != nil:
                if experience.canRetryPlan {
                    action("Try again", icon: "arrow.clockwise", action: experience.requestPlan)
                }
                Button("Scan again", action: experience.rescan).frame(minHeight: 44).foregroundStyle(lime)
            case .restoring where drawerExpanded:
                action("Try recognizing again", icon: "arrow.clockwise", action: experience.useSavedRoom)
                Button("Back to my friends", action: experience.chooseAnotherFriend).frame(minHeight: 44).foregroundStyle(lime)
            default: EmptyView()
            }
        }.padding(.horizontal, 16).padding(.bottom, hasFooter ? 16 : 0)
    }

    private var hasFooter: Bool {
        switch experience.phase {
        case .ready: return true
        case .revealed, .returning: return experience.inReach
        case .questing: return experience.itemInReach
        case .playing, .complete, .restoring: return drawerExpanded
        case .planning: return experience.planningError != nil
        default: return false
        }
    }

    private var cardLabel: String {
        switch experience.phase {
        case .restoring: return "WELCOME BACK"
        case .ready: return experience.usingSavedRoom ? "YOUR SAVED ROOM" : "YOUR ROOM COMES FIRST"
        case .scanning, .planning: return "YOUR ROOM COMES FIRST"
        case .challenge: return "DRAW YOUR WAY OUT"
        case .questing, .returning: return "A LITTLE FAVOR"
        case .playing: return "BETTER TOGETHER"
        case .complete: return "FRIENDSHIP EARNED"
        default: return "A NEW FRIEND"
        }
    }

    private var title: String {
        switch experience.phase {
        case .scanning: return "A little look around."
        case .planning: return "Making sense of your space."
        case .restoring: return "A familiar little place."
        case .ready: return experience.usingSavedRoom ? "Your room is back." : "Your room, understood."
        case .exploring: return "Someone's hiding."
        case .revealed: return "Meet \(experience.friend.name)."
        case .challenge: return experience.challenge?.title ?? "A tricky spot."
        case .questing: return experience.friend.questTitle
        case .returning: return "A little delivery."
        case .playing: return experience.game.challenge?.blueprint.title ?? "Let's play."
        case .complete: return "A new little friend."
        }
    }

    private var detail: String {
        switch experience.phase {
        case .scanning: return experience.scanInstruction
        case .planning: return "Finding a home for your friend and a few surprises for you. This may take a moment."
        case .restoring: return experience.restoreMessage
        case .ready: return experience.plan?.room?.summary ?? "Your room plan is ready."
        case .exploring: return experience.plan?.hint ?? "Explore the furniture around you."
        case .revealed: return experience.dialogue ?? experience.friend.personality
        case .challenge: return experience.helper == nil
            ? (experience.challenge?.prompt ?? "Draw something to help.")
            : (experience.dialogue ?? experience.challenge?.prompt ?? "")
        case .questing: return experience.questRequest
        case .returning: return "Bring the \(experience.friend.itemName) back to \(experience.friend.name). Your friend is waiting where you met."
        case .playing: return experience.game.challenge?.feedback ?? "Let's play together."
        case .complete: return experience.dialogue ?? experience.friend.thanks
        }
    }

    private var connection: some View { ConnectionSettings(experience: experience) }

    private var themePicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A new world.\nYour own room.")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1).foregroundStyle(paper)
                    Text("Pick a theme. \(experience.provider.name) reads your 360° scan and finds room for decorations on the visible walls.")
                        .font(.system(size: 15)).foregroundStyle(paper.opacity(0.65)).lineSpacing(3)
                    ForEach(RealmTheme.allCases) { theme in
                        Button { experience.selectTheme(theme) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ThemePreview(theme: theme).frame(height: 150).clipped().accessibilityHidden(true)
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(theme.name, systemImage: theme.symbol).font(.system(size: 17, weight: .semibold, design: .rounded))
                                        Text(theme.subtitle).font(.system(size: 12)).foregroundStyle(paper.opacity(0.65))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: experience.theme == theme ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22)).foregroundStyle(experience.theme == theme ? lime : paper.opacity(0.3))
                                }.foregroundStyle(paper).padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.05))
                            }.clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(experience.theme == theme ? lime : .white.opacity(0.12), lineWidth: 1.5))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(theme.name). \(theme.subtitle)")
                            .accessibilityAddTraits(experience.theme == theme ? [.isSelected] : [])
                            .accessibilityIdentifier("theme-\(theme.rawValue)")
                    }
                    Label(experience.theme != .original ? experience.themeMessage : "Switch anytime. Your friend and quest stay in place.", systemImage: "sparkles")
                        .font(.system(size: 12)).foregroundStyle(lime).lineSpacing(3)
                        .accessibilityIdentifier("themeStatus")
                }.padding(24)
            }.background(ink).navigationTitle("Room themes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { experience.themePresented = false }.tint(lime)
                } }
        }.preferredColorScheme(.dark)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle").foregroundStyle(lime)
            Text("pocket realm").font(.system(size: 18, weight: .semibold, design: .rounded)).tracking(-0.4).foregroundStyle(paper)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(paper.opacity(0.7)).frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private func step(_ number: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(lime).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(paper)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(paper.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    private func action(_ title: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            }.foregroundStyle(enabled ? ink : paper.opacity(0.45)).padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 50)
                .background(enabled ? lime : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
        }.disabled(!enabled)
    }
}

/// Blender renders preview the bundled models; their live placement follows the captured room.
private struct ThemePreview: View {
    let theme: RealmTheme

    var body: some View {
        if let preview = theme.previewImage {
            GeometryReader { geometry in
                Image(preview).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        } else {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors: theme == .jungle
                        ? [Color(red: 0.06, green: 0.19, blue: 0.14), Color(red: 0.20, green: 0.37, blue: 0.20)]
                        : [Color(red: 0.17, green: 0.23, blue: 0.24), Color(red: 0.30, green: 0.36, blue: 0.32)],
                        startPoint: .top, endPoint: .bottom)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 92))
                        path.addLine(to: CGPoint(x: geometry.size.width * 0.5, y: 68))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: 92))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: 125))
                        path.addLine(to: CGPoint(x: 0, y: 125))
                        path.closeSubpath()
                    }.fill(Color.white.opacity(0.1))
                    Image(systemName: "sofa.fill").font(.system(size: 58)).foregroundStyle(paper.opacity(0.4))
                        .position(x: geometry.size.width * 0.52, y: 74)
                    if theme == .jungle {
                        ForEach(0..<7) { i in
                            let x = geometry.size.width * (CGFloat(i) + 0.5) / 7
                            Path { path in
                                path.move(to: CGPoint(x: x, y: -5))
                                path.addQuadCurve(to: CGPoint(x: x - 9, y: CGFloat(30 + (i % 3) * 12)), control: CGPoint(x: x + 15, y: 22))
                            }.stroke(lime.opacity(0.45), lineWidth: 2)
                            Image(systemName: "leaf.fill").font(.system(size: 17)).rotationEffect(.degrees(Double(i % 2 == 0 ? 30 : -30)))
                                .foregroundStyle(lime.opacity(0.75)).position(x: x - 5, y: CGFloat(27 + (i % 3) * 12))
                        }
                        ForEach(0..<9) { i in
                            Image(systemName: i % 3 == 0 ? "camera.macro" : "leaf.fill")
                                .font(.system(size: i % 3 == 0 ? 22 : 17))
                                .foregroundStyle(i % 3 == 0 ? Color(red: 1, green: 0.61, blue: 0.73) : lime.opacity(0.8))
                                .position(x: geometry.size.width * (CGFloat(i) + 0.5) / 9, y: CGFloat(38 + (i % 2) * 12))
                        }
                    }
                }
            }
        }
    }
}

private struct ARSurface: UIViewRepresentable {
    let experience: ARExperience
    func makeUIView(context: Context) -> ARView { experience.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}


/// The presented screen observes connection changes itself, including while the parent is covered.
private struct ConnectionSettings: View {
    @ObservedObject var experience: ARExperience
    @State private var apiKeyEntry = ""
    @State private var showResult = false
    @FocusState private var keyFocused: Bool

    private var connected: Bool {
        if case .connected = experience.connectionState { return true }
        return false
    }
    private var resultMessage: String {
        if case .failed(let message) = experience.connectionState { return message }
        return "\(experience.modelName) answered a real request from your iPhone. Use a saved room for offline testing, or scan a new room."
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section {
                        status
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("planningConnectionStatus")
                    }.id("connection-status")
                    Section("AI provider") {
                        Picker("Provider", selection: Binding(get: { experience.provider }, set: experience.selectProvider)) {
                            ForEach(PlanningProvider.allCases) { provider in Text(provider.name).tag(provider) }
                        }
                        .disabled(experience.testingConnection || experience.requesting)
                        .accessibilityIdentifier("planningProviderPicker")
                        if experience.provider == .server {
                            Text("Your Pocket Realm server plans rooms with Meta's Muse Spark, with Gemini as a backup. The keys stay on the server; nothing is stored on this iPhone.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if experience.provider == .muse {
                            Picker("Model", selection: Binding(get: { experience.museModel }, set: experience.selectMuseModel)) {
                                ForEach(MuseModel.allCases) { model in Text(model.name).tag(model) }
                            }.accessibilityIdentifier("museModelPicker")
                            Text("Use your Meta Model API key. Muse handles room understanding, theme layouts, clues, greetings, and puzzles.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Picker("Model", selection: Binding(get: { experience.geminiModel }, set: experience.selectGeminiModel)) {
                                ForEach(GeminiModel.allCases) { model in Text(model.name).tag(model) }
                            }.accessibilityIdentifier("geminiModelPicker")
                        }
                    }.disabled(experience.testingConnection || experience.requesting)
                    if experience.provider == .server {
                        Section("Server") {
                            Button {
                                experience.testAPIKey()
                            } label: {
                                Label(experience.testingConnection ? "Checking server…" : "Check server", systemImage: "network")
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(experience.testingConnection || experience.requesting || !experience.addressIsValid)
                            .accessibilityIdentifier("testAIConnection")
                            Text("Uses the server address under Drawing workshop below.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                    Section("\(experience.provider.name) API key") {
                        SecureField(experience.hasAPIKey ? "Paste a replacement API key" : "Paste \(experience.provider.name) API key", text: $apiKeyEntry)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                            .accessibilityLabel("\(experience.provider.name) API key").focused($keyFocused)
                            .disabled(experience.testingConnection || experience.requesting)
                        if !apiKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Save key without testing") {
                                keyFocused = false
                                if experience.saveAPIKey(apiKeyEntry) { apiKeyEntry = "" }
                            }
                            .disabled(experience.testingConnection || experience.requesting)
                            .accessibilityIdentifier("saveAPIKeyOnly")
                        }
                        Button {
                            keyFocused = false
                            if !apiKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                guard experience.saveAPIKey(apiKeyEntry) else { return }
                                apiKeyEntry = ""
                            }
                            experience.testAPIKey()
                        } label: {
                            Label(experience.testingConnection ? "Testing connection…" : apiKeyEntry.isEmpty ? "Test connection" : "Save & Test",
                                  systemImage: "network")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(experience.testingConnection || experience.requesting || (!experience.hasAPIKey && apiKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("testAIConnection")
                        if experience.testingConnection {
                            Button("Cancel test", role: .cancel) { experience.cancelConnectionTest() }
                        }
                        if experience.requesting {
                            Text("Wait for your room plan before testing the connection.").font(.footnote)
                        }
                        if experience.hasAPIKey {
                            Label("Key saved in iPhone Keychain", systemImage: "lock.fill").font(.footnote)
                            Button("Remove API key", role: .destructive) { experience.removeAPIKey(); apiKeyEntry = "" }
                                .disabled(experience.testingConnection || experience.requesting)
                        }
                        Text("Testing is optional. Each test makes one request to \(experience.modelName). Saving a key or changing models makes no request.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    }
                    Section("What gets sent") {
                        Text(experience.provider == .server
                             ? "After your scan, this iPhone sends measured walls, openings, furniture, and up to six room snapshots to your Pocket Realm server, which asks Meta's Muse (or Google's Gemini as a backup) to plan your room and adventure."
                             : "After your scan, this iPhone sends measured walls, openings, furniture, and up to six room snapshots directly to \(experience.provider.company) to plan your room and adventure.")
                        Text("Use saved room works without another AI call. During play, Adventure options → Replay this room reuses the current scan, even when you try another friend. Your saved room and key stay on this iPhone.")
                    }.font(.footnote)
                    Section("Drawing workshop") {
                        TextField("https://your-workshop.example", text: $experience.serverAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityLabel("Drawing workshop address")
                            .accessibilityIdentifier("drawingWorkshopAddress")
                        Toggle("Drawing challenges", isOn: $experience.sketchQuestsEnabled)
                            .accessibilityIdentifier("sketchQuestsToggle")
                        if !experience.serverAddress.isEmpty && !experience.addressIsValid {
                            Text("Enter the full workshop address, starting with https:// or http://.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        Text("Connect a workshop to bring paper drawings to life. Drawing challenges start when a workshop address or saved creation is available. You can always continue without a drawing.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Drawing photos go to this workshop to create 3D models. Your finished creations stay on this iPhone and can be reused offline.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.id("drawing-workshop")
                }
                .onAppear {
                    if experience.workshopSettingsRequested {
                        scroll.scrollTo("drawing-workshop", anchor: .top)
                    }
                }
                .onChange(of: experience.provider) { _, _ in
                    apiKeyEntry = ""; showResult = false; keyFocused = false
                }
                .onChange(of: experience.connectionState) { _, state in
                    scroll.scrollTo("connection-status", anchor: .top)
                    switch state {
                    case .connected, .failed: showResult = true
                    default: showResult = false
                    }
                }
            }
            .navigationTitle("Connection")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { experience.connectionPresented = false } } }
            .onDisappear { apiKeyEntry = ""; experience.workshopSettingsRequested = false }
            .alert(connected ? "\(experience.provider.name) is connected" : "Connection failed", isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: { Text(resultMessage) }
        }
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch experience.connectionState {
            case .needsKey:
                Label("Not connected yet", systemImage: "key.fill").font(.headline)
                Text("Paste your \(experience.provider.name) API key below. You can save it without making a test request.").font(.subheadline)
            case .saved where experience.provider == .server:
                Label("Using your server", systemImage: "server.rack").font(.headline)
                Text("Room planning goes through your Pocket Realm server. No key needed on this iPhone. You can scan now.").font(.subheadline)
            case .saved:
                Label("Key saved", systemImage: "key.fill").font(.headline)
                Text("Selected: \(experience.modelName). You can scan now, or optionally test the connection. Saved rooms need no connection.").font(.subheadline)
            case .checking(let started):
                ProgressView("Checking \(experience.provider.name)…").font(.headline)
                TimelineView(.periodic(from: started, by: 1)) { timeline in
                    Text("Contacting \(experience.provider.company) · \(max(0, Int(timeline.date.timeIntervalSince(started)))) seconds")
                        .font(.subheadline).monospacedDigit()
                }
                Text("Waiting up to \(Int(experience.planningClient.connectionTimeout)) seconds for one reply. You can cancel below.").font(.footnote)
            case .connected(let checked):
                Label("Connected", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                Text("\(experience.modelName) answered successfully.").font(.subheadline)
                Text("Checked \(checked.formatted(date: .omitted, time: .shortened)) · You're ready to scan.").font(.footnote)
            case .failed(let message):
                Label("Connection failed", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                Text(message).font(.subheadline)
            }
        }.padding(.vertical, 6)
    }
}
