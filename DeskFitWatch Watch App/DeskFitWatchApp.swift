import SwiftUI

@main
struct DeskFitWatchApp: App {
    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
