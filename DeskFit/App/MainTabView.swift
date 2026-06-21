import SwiftUI

struct MainTabView: View {
    @State private var nav = AppNavigation.shared

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            ReportView()
                .tabItem { Label("Report", systemImage: "chart.bar.fill") }
                .tag(AppTab.report)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
    }
}
