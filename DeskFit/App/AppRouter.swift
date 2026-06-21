import SwiftUI

struct AppRouter: View {
    @State private var state = AppState()
    @State private var phase: OnboardingPhase = .intro
    @State private var showConflict = false
    @State private var showSaveOffer = false

    // Flow: splash (while bootstrapping) -> intro -> account choice ->
    //        questionnaire -> Today (tabs).
    // An Apple user whose account already has an assessment skips straight to Today.
    private enum OnboardingPhase { case intro, account, assessment }

    var body: some View {
        Group {
            if state.isBootstrapping {
                // Resolving backend state (and showing the brand splash).
                SplashView(onFinish: {})
            } else if state.requiresAuth {
                // Logged out from Profile: re-login gate. Backend data is reloaded
                // on success; "Not now" just resumes with the on-device report.
                AuthView(
                    title: "Welcome back.",
                    subtitle: "Sign in with Apple to reload your synced profile and plans.",
                    guestTitle: "Not now",
                    guestNote: nil,
                    onAppleOutcome: handleReloginOutcome,
                    onGuest: resumeAfterLogin
                )
            } else if state.onboardingComplete, state.report != nil {
                MainTabView()
            } else {
                switch phase {
                case .intro:
                    ValueOnboardingView(onContinue: { phase = .account })
                case .account:
                    AuthView(
                        title: "How would you like to start?",
                        subtitle: "Continue with Apple to save and sync your plan, or explore on this device first.",
                        onAppleOutcome: handleAccountChoiceOutcome,
                        onGuest: startAsGuest
                    )
                case .assessment:
                    AssessmentFlowView(onFinish: finishAssessment)
                }
            }
        }
        .environment(state)
        .animation(.easeInOut(duration: 0.35), value: state.onboardingComplete)
        .animation(.easeInOut(duration: 0.35), value: state.requiresAuth)
        .animation(.easeInOut(duration: 0.35), value: state.isBootstrapping)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .task {
            await state.bootstrap()
            // An authenticated user without an assessment resumes at the
            // questionnaire (they already chose Apple on a previous session).
            if state.isAuthenticated, !state.hasLocalAssessment {
                phase = .assessment
            }
        }
        .onChange(of: state.onboardingComplete) { _, complete in
            if !complete { phase = .intro }
        }
        .sheet(isPresented: $showConflict) {
            ConflictResolutionView(
                onResolved: {},                 // hydrate/replace already applied
                onCancel: { phase = .assessment } // keep local; let them continue
            )
            .environment(state)
        }
        .confirmationDialog("Save this assessment to your Apple account?",
                            isPresented: $showSaveOffer, titleVisibility: .visible) {
            Button("Save to my account") { Task { await state.uploadLocalAssessment() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your answers and report will be saved to your DeskFit account.")
        }
    }

    // MARK: - Account-choice routing (launch flow)

    private func startAsGuest() {
        state.continueAsGuest()
        phase = .assessment
    }

    private func handleAccountChoiceOutcome(_ outcome: AppState.AppleSignInOutcome) {
        switch outcome {
        case .loadedBackend:
            break                          // onboardingComplete → MainTabView shows
        case .noBackendNeedsAssessment:
            phase = .assessment
        case .offerSaveLocal:
            showSaveOffer = true
            phase = .assessment
        case .conflict:
            showConflict = true
        case .error:
            phase = .assessment            // proceed locally; sync can retry later
        }
    }

    // MARK: - Re-login gate routing

    private func handleReloginOutcome(_ outcome: AppState.AppleSignInOutcome) {
        switch outcome {
        case .conflict:
            // Same account signing back in — backend wins by default.
            state.useBackendProfile()
        case .loadedBackend, .noBackendNeedsAssessment, .offerSaveLocal:
            break
        case .error:
            break
        }
        state.requiresAuth = false
        if state.isAuthenticated { Task { await state.syncAll() } }
    }

    /// "Not now" from the logout gate: resume with the on-device report.
    private func resumeAfterLogin() {
        state.requiresAuth = false
        if state.isAuthenticated { Task { await state.syncAll() } }
    }

    // MARK: - Questionnaire completion

    /// After the questionnaire: generate the report and (if signed in) sync it.
    private func finishAssessment() {
        state.generateReport()
        Haptics.success()
        if state.isAuthenticated { Task { await state.syncAll() } }
    }
}
