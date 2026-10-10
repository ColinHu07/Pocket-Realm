import RealityKit
import SwiftUI
import UIKit

private let ink = Color(red: 0.055, green: 0.095, blue: 0.10)
private let lime = Color(red: 0.80, green: 0.98, blue: 0.59)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.89)

struct ContentView: View {
    @ObservedObject var experience: ARExperience
    @State private var previewFriend: RealmFriend?

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if experience.started { adventure }
            else { welcome }
        }
        .animation(.easeInOut(duration: 0.3), value: experience.phase)
        .sheet(isPresented: $experience.connectionPresented) { connection }
        .sheet(isPresented: $experience.themePresented) { themePicker }
        .sheet(item: $previewFriend) { FriendPreview(friend: $0) }
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
                    brand
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your room.\nA world of its own.")
                            .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1.5).foregroundStyle(paper)
                        Text("Scan your space. Let Gemini plan its transformation, then explore with a little friend.")
                            .font(.system(size: 16)).foregroundStyle(paper.opacity(0.65)).lineSpacing(3)
                    }
                    friendPicker
                    Button { previewFriend = experience.friend } label: {
                        Label("Meet \(experience.friend.name) · try their reactions", systemImage: "heart.circle.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(lime)
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
                    VStack(spacing: 16) {
                        step("01", "Take a 360° look around", "A slow sweep captures your floor, walls, and furniture.")
                        step("02", "Understand, then transform", "Gemini plans your Jungle and quest locations from the scan.")
                        step("03", "Explore when you're ready", "Review your room plan, then meet \(experience.friend.name).")
                    }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 0)
                }.padding(24).frame(minHeight: geometry.size.height)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                action("Scan my room", icon: "viewfinder") { experience.start() }
                Text("Room layout and up to 6 snapshots are sent to your server and Gemini.")
                    .font(.system(size: 10)).foregroundStyle(paper.opacity(0.55)).multilineTextAlignment(.center)
                Button("Connection settings") { experience.connectionPresented = true }
                    .font(.system(size: 12)).foregroundStyle(lime)
            }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12).background(ink)
        }
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
        HStack(spacing: 18) {
            Button(action: experience.pet) { Label("Pet", systemImage: "hand.draw") }
            Button(action: experience.play) { Label("Play", systemImage: "sparkles") }
            if experience.phase == .complete {
                Button(action: experience.chat) { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            }
        }.font(.system(size: 13, weight: .semibold)).foregroundStyle(lime)
            .disabled(!experience.trackingReady || !experience.inReach)
            .opacity(experience.trackingReady && experience.inReach ? 1 : 0.45)
            .frame(minHeight: 36)
    }

    private var adventure: some View {
        ZStack {
            ARSurface(experience: experience).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 16) {
                HStack {
                    brand
                    Spacer()
                    Menu {
                        Button("Scan again", action: experience.rescan)
                        Button("Choose another friend", action: experience.chooseAnotherFriend)
                        Button("Connection settings") { experience.connectionPresented = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                    }.accessibilityLabel("Experience options")
                }
                HStack(spacing: 7) {
                    Circle().fill(experience.trackingReady ? lime : .orange).frame(width: 6, height: 6)
                    Text(experience.trackingReady ? "LIVE IN YOUR ROOM" : "FINDING YOUR ROOM").tracking(1.2)
                    Spacer()
                    if let distance = experience.objectiveDistance { Text(String(format: "%.1f m", distance)).monospacedDigit() }
                }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(paper)
                HStack {
                    Button { experience.themePresented = true } label: {
                        HStack(spacing: 7) {
                            Image(systemName: experience.theme.symbol)
                            Text("Theme · \(experience.theme.name)")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }.font(.system(size: 12, weight: .semibold)).foregroundStyle(paper)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(.ultraThinMaterial, in: Capsule())
                    }.accessibilityLabel("Change room theme. Current theme: \(experience.theme.name)")
                        .accessibilityIdentifier("roomThemeButton")
                    Spacer()
                }
                Spacer()
                if !experience.trackingReady {
                    Text(experience.trackingMessage).font(.subheadline).multilineTextAlignment(.center)
                        .padding(12).frame(maxWidth: .infinity).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                questCard
            }.padding(20)
        }
    }

    private var questCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(cardLabel).tracking(2)
                Spacer()
                Image(systemName: experience.phase == .complete ? "checkmark.seal.fill" : "sparkle")
            }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(lime)
            Text(title).font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(paper)
            if experience.phase != .ready {
                Text(detail).font(.system(size: 15)).foregroundStyle(paper.opacity(0.72)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            switch experience.phase {
            case .scanning:
                ProgressView(value: experience.coverage.fraction).tint(lime)
                HStack {
                    Text("\(Int(experience.coverage.fraction * 100))% of the sweep")
                    Spacer()
                    Text("\(experience.objectCount) locations found")
                }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(lime)
                footnote(experience.coverage.complete && experience.objectCount == 0
                    ? "Keep looking at furniture until a clear location is detected."
                    : "The scan finishes automatically after a full sweep and a clear furniture detection.")
            case .planning:
                if let error = experience.planningError {
                    Text(error).font(.subheadline).foregroundStyle(.orange)
                    if experience.canRetryPlan {
                        action("Ask Gemini again", icon: "arrow.clockwise", action: experience.requestPlan)
                    }
                    Button("Scan again", action: experience.rescan).foregroundStyle(lime)
                    Button("Connection settings") { experience.connectionPresented = true }
                        .foregroundStyle(lime)
                } else {
                    HStack(spacing: 12) { ProgressView().tint(lime); Text(experience.requesting ? "Gemini is understanding your room…" : "Finishing the room model…") }
                        .font(.subheadline).foregroundStyle(paper.opacity(0.7))
                }
            case .ready:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail).foregroundStyle(paper.opacity(0.8))
                        if let room = experience.plan?.room {
                            Label("Jungle plan", systemImage: "leaf.fill").foregroundStyle(lime)
                            Text(room.designNote).foregroundStyle(paper.opacity(0.7))
                            DisclosureGroup("Quest locations") {
                                Text(room.questReason).foregroundStyle(paper.opacity(0.7)).padding(.top, 8)
                            }.tint(lime).foregroundStyle(lime)
                        }
                    }.font(.system(size: 14)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 210).accessibilityIdentifier("roomPlanReview")
                if experience.theme == .jungle { footnote(experience.themeMessage) }
                else {
                    Button("Preview the Jungle") { experience.selectTheme(.jungle) }
                        .font(.subheadline).foregroundStyle(lime)
                }
                action("Start exploring", icon: "figure.walk", enabled: experience.trackingReady, action: experience.beginExploring)
            case .exploring:
                Label(experience.proximity.armed ? "Walk closer. \(experience.friend.name) appears automatically." : "Step back a little, then explore.", systemImage: "figure.walk")
                    .font(.subheadline).foregroundStyle(lime)
                footnote("Follow the clue. There's no reveal button.")
            case .revealed:
                action(experience.inReach ? "Say hello to \(experience.friend.name)" : "Move a little closer", icon: "bubble.left", enabled: experience.trackingReady && experience.inReach, action: experience.talk)
                friendInteractions
            case .questing:
                Label("Look for a glowing \(experience.friend.itemName) by the \(experience.questCategory).", systemImage: experience.friend.symbol)
                    .font(.subheadline).foregroundStyle(lime)
                action(experience.itemInReach ? "Collect \(experience.friend.itemName)" : "Move closer to the keepsake", icon: "sparkles", enabled: experience.trackingReady && experience.itemInReach, action: experience.collectKeepsake)
                footnote("It's floating outside the furniture. You don't need to open or move anything.")
                friendInteractions
            case .returning:
                Label("\(experience.friend.itemName.capitalized) collected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(lime)
                action(experience.inReach ? "Give it to \(experience.friend.name)" : "Return to \(experience.friend.name)", icon: "gift", enabled: experience.trackingReady && experience.inReach, action: experience.finishQuest)
                friendInteractions
            case .complete:
                Label(experience.friend.reward + " · friendship badge", systemImage: experience.friend.symbol)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(lime)
                friendInteractions
                action("Meet another friend", icon: "arrow.right", action: experience.chooseAnotherFriend)
                footnote("\(experience.completedFriends.count) of \(RealmFriend.allCases.count) friendships made. Your badges are saved.")
            }
        }.padding(22).background(ink.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var cardLabel: String {
        switch experience.phase {
        case .scanning, .planning, .ready: return "YOUR ROOM COMES FIRST"
        case .questing, .returning: return "A LITTLE FAVOR"
        case .complete: return "FRIENDSHIP EARNED"
        default: return "A NEW FRIEND"
        }
    }

    private var title: String {
        switch experience.phase {
        case .scanning: return "A little look around."
        case .planning: return "Making sense of your space."
        case .ready: return "Your room, understood."
        case .exploring: return "Someone's hiding."
        case .revealed: return "Meet \(experience.friend.name)."
        case .questing: return experience.friend.questTitle
        case .returning: return "A little delivery."
        case .complete: return "A new little friend."
        }
    }

    private var detail: String {
        switch experience.phase {
        case .scanning: return experience.scanInstruction
        case .planning: return "Gemini uses the room layout and snapshots to plan the Jungle and both quest locations."
        case .ready: return experience.plan?.room?.summary ?? "Your room plan is ready."
        case .exploring: return experience.plan?.hint ?? "Explore the furniture around you."
        case .revealed: return experience.dialogue ?? experience.friend.personality
        case .questing: return experience.friend.questRequest
        case .returning: return "Bring the \(experience.friend.itemName) back to \(experience.friend.name). Your friend is waiting where you met."
        case .complete: return experience.dialogue ?? experience.friend.thanks
        }
    }

    private var connection: some View {
        NavigationStack {
            Form {
                Section("Adventure server") {
                    TextField("http://your-mac.local:8787", text: $experience.serverAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Use your Mac's local server address or an HTTPS backend. Your phone and Mac must be on the same Wi-Fi for a local server.")
                        .font(.footnote)
                }
                Section("What gets sent") {
                    Text("After your scan, we send measured floors, walls, openings, furniture, and up to six room snapshots to this server. Gemini interprets the space and plans your Jungle, friend location, and keepsake location. The Gemini key stays on the server.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Connection")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { experience.connectionPresented = false }.disabled(!experience.addressIsValid) } }
        }
    }

    private var themePicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A new world.\nYour own room.")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1).foregroundStyle(paper)
                    Text("Pick a theme. Gemini reads your 360° scan and plans how it fits your room's floor and walls.")
                        .font(.system(size: 15)).foregroundStyle(paper.opacity(0.65)).lineSpacing(3)
                    ForEach(RealmTheme.allCases) { theme in
                        Button { experience.selectTheme(theme) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ThemePreview(theme: theme).frame(height: 125).clipped().accessibilityHidden(true)
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
                    Label(experience.theme == .jungle ? experience.themeMessage : "Switch anytime. Your friend and quest stay in place.", systemImage: "sparkles")
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
        Text(text).font(.system(size: 11)).foregroundStyle(paper.opacity(0.45)).frame(maxWidth: .infinity).multilineTextAlignment(.center)
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
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            }.foregroundStyle(enabled ? ink : paper.opacity(0.45)).padding(.horizontal, 20).frame(minHeight: 56)
                .background(enabled ? lime : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
        }.disabled(!enabled)
    }
}

/// A stylized illustration of each preset; actual decoration follows the captured room.
private struct ThemePreview: View {
    let theme: RealmTheme

    var body: some View {
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
                }.fill(theme == .jungle ? Color(red: 0.25, green: 0.42, blue: 0.22) : Color.white.opacity(0.1))
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
                            .position(x: geometry.size.width * (CGFloat(i) + 0.5) / 9, y: CGFloat(103 + (i % 2) * 10))
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
