import SwiftUI

@main
struct SteamGuardMacApp: App {
    init() {
        // Sync clock with Steam servers at launch
        Task { await SteamTOTP.syncTime() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 450)
    }
}
