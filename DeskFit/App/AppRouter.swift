import SwiftUI

struct AppRouter: View {
    @State private var state = AppState()
    @State private var isOnboarding = false

    var body: some View {
        Group {
            if state.onboardingComplete, state.report != nil {
                MainTabView()
            } else if isOnboarding {
                OnboardingView(onFinish: {
                    state.generateReport()
                })
            } else {
                WelcomeView(onStart: { isOnboarding = true })
            }
        }
        .environment(state)
        .animation(.easeInOut(duration: 0.35), value: state.onboardingComplete)
        .animation(.easeInOut(duration: 0.35), value: isOnboarding)
        .onChange(of: state.onboardingComplete) { _, complete in
            if !complete { isOnboarding = false }
        }
    }
}
