import SwiftUI

@main
struct WatchApproveWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                    }
            }
        }
    }
}
