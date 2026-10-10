import RealityKit
import SwiftUI
import UIKit

private let ink = Color(red: 0.055, green: 0.095, blue: 0.10)
private let lime = Color(red: 0.80, green: 0.98, blue: 0.59)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.89)

struct ContentView: View {
    @ObservedObject var experience: ARExperience

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if experience.started { adventure }
            else { welcome }
        }
        .animation(.easeInOut(duration: 0.3), value: experience.phase)
        .sheet(isPresented: $experience.connectionPresented) { connection }
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
                    Spacer(minLength: 12)
                    ZStack {
                        Circle().fill(lime.opacity(0.07)).frame(width: 245, height: 245)
                        Circle().stroke(lime.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 8])).frame(width: 210, height: 210)
                        Image(systemName: "cabinet.fill").font(.system(size: 96, weight: .ultraLight)).foregroundStyle(paper)
                        Image(systemName: "sparkles").font(.system(size: 42)).foregroundStyle(lime).offset(x: 70, y: -59)
                        Text("A LITTLE MAGIC, HIDING IN PLAIN SIGHT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.2)
                            .foregroundStyle(lime).offset(y: 104)
                    }.frame(maxWidth: .infinity).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your room.\nA hidden realm.")
                            .font(.system(size: 43, weight: .semibold, design: .rounded)).tracking(-1.7).foregroundStyle(paper)
                        Text("Scan your room. Gemini will find a hiding spot for a tiny creature. Walk over and discover it.")
                            .font(.system(size: 17)).foregroundStyle(paper.opacity(0.65)).lineSpacing(4)
                    }
                    VStack(spacing: 16) {
                        step("01", "Take a 360° look around", "A slow sweep maps your real furniture.")
                        step("02", "Follow a little curiosity", "Gemini chooses the spot. Approach to meet Pip.")
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
                        Button("Connection settings") { experience.connectionPresented = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                    }.accessibilityLabel("Experience options")
                }
                HStack(spacing: 7) {
                    Circle().fill(experience.trackingReady ? lime : .orange).frame(width: 6, height: 6)
                    Text(experience.trackingReady ? "LIVE IN YOUR ROOM" : "FINDING YOUR ROOM").tracking(1.2)
                    Spacer()
                    if let distance = experience.distance { Text(String(format: "%.1f m", distance)).monospacedDigit() }
                }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(paper)
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
                Text(experience.phase == .complete ? "FIRST DISCOVERY" : "ENCOUNTER 01").tracking(2)
                Spacer()
                Image(systemName: experience.phase == .complete ? "checkmark.seal.fill" : "sparkle")
            }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(lime)
            Text(title).font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(paper)
            Text(detail).font(.system(size: 15)).foregroundStyle(paper.opacity(0.72)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
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
                    HStack(spacing: 12) { ProgressView().tint(lime); Text(experience.requesting ? "Gemini is choosing a hiding spot…" : "Finishing the room model…") }
                        .font(.subheadline).foregroundStyle(paper.opacity(0.7))
                }
            case .exploring:
                Label(experience.proximity.armed ? "Walk closer. Pip appears automatically." : "Step back a little, then explore.", systemImage: "figure.walk")
                    .font(.subheadline).foregroundStyle(lime)
                footnote("Follow the clue. There's no reveal button.")
            case .revealed:
                action(experience.inReach ? "Say hello to Pip" : "Move a little closer", icon: "bubble.left", enabled: experience.trackingReady && experience.inReach, action: experience.talk)
                footnote("Look away and back. Pip is waiting right here.")
            case .complete:
                action("Explore a new room", icon: "arrow.clockwise", action: experience.rescan)
                footnote("Pip stays here until you begin another scan.")
            }
        }.padding(22).background(ink.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var title: String {
        switch experience.phase {
        case .scanning: return "A little look around."
        case .planning: return "Finding the magic."
        case .exploring: return "Someone's hiding."
        case .revealed: return "Meet Pip."
        case .complete: return "A new little friend."
        }
    }

    private var detail: String {
        switch experience.phase {
        case .scanning: return experience.scanInstruction
        case .planning: return "Your room becomes the map. Gemini picks one real location for your first encounter."
        case .exploring: return experience.plan?.hint ?? "Explore the furniture around you."
        case .revealed: return "A tiny forest spirit has made a home in your room. Go on, introduce yourself."
        case .complete: return experience.plan?.greeting ?? "You found me!"
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
                    Text("After your scan, we send detected furniture and up to six room snapshots to this server, which asks Gemini where Pip should hide. The Gemini key stays on the server.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Connection")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { experience.connectionPresented = false }.disabled(!experience.addressIsValid) } }
        }
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

private struct ARSurface: UIViewRepresentable {
    let experience: ARExperience
    func makeUIView(context: Context) -> ARView { experience.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
