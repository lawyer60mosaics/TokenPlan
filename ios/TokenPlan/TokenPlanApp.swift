import SwiftUI

@main
struct TokenPlanApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        BackgroundRefreshManager.schedule()
                    }
                }
        }
    }
}
