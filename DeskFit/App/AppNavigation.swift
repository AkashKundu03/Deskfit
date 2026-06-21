import SwiftUI

/// The three primary tabs. Stable raw values so notification deep-links and
/// programmatic selection stay in sync.
enum AppTab: Int, Hashable {
    case today = 0
    case report = 1
    case profile = 2
}

/// App-wide navigation state — currently just the selected tab so a tapped local
/// notification can route to the relevant screen. Observable singleton so the
/// notification delegate (outside the SwiftUI environment) can drive it.
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var selectedTab: AppTab = .today
    private init() {}
}
