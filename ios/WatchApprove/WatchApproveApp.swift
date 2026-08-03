import SwiftUI

@main
struct WatchApproveApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active,
               let manager = WebSocketManager.shared,
               manager.connectionStatus == .disconnected,
               manager.isPaired {
                print("App became active - reconnecting...")
                manager.connect()
            }
        }
    }
}
