import SwiftUI

@main
struct PocketRealmApp: App {
    @StateObject private var experience = ARExperience()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(experience: experience)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { experience.resume() }
                    else if phase == .background { experience.suspend() }
                }
        }
    }
}
