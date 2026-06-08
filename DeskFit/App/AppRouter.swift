import SwiftUI

struct AppRouter: View {
    @State private var state = AppState()
    @State private var phase: OnboardingPhase = .splash

    // Flow: splash -> 3 value screens -> assessment -> sign-in -> report (tabs).
    private enum OnboardingPhase { case splash, value, assessment, auth }

    var body: some View {
        Group {
            if state.onboardingComplete, state.report != nil {
                MainTabView()
            } else {
                switch phase {
                case .splash:
                    SplashView(onFinish: { phase = .value })
                case .value:
                    ValueOnboardingView(onContinue: { phase = .assessment })
                case .assessment:
                    AssessmentFlowView(onFinish: { phase = .auth })
                case .auth:
                    AuthView(onFinish: finish)
                }
            }
        }
        .environment(state)
        .animation(.easeInOut(duration: 0.35), value: state.onboardingComplete)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onChange(of: state.onboardingComplete) { _, complete in
            if !complete { phase = .splash }
        }
    }

    /// Sign-in is optional: whether the user authenticated or tapped "Not now",
    /// we generate and show the report. If signed in, push everything to backend.
    private func finish() {
        state.generateReport()
        if state.isAuthenticated {
            Task { await state.syncAll() }
        }
    }
}
