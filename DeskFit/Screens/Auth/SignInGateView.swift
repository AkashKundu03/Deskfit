import SwiftUI
import AuthenticationServices

/// Sign-in gate shown when a guest tries a premium action (generating a weekly
/// workout plan or a meal plan). Guests can explore, but cloud-synced plans
/// require an Apple account. Handles the guest→account upgrade, including the
/// "save your local assessment" offer and any backend conflict.
struct SignInGateView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// What the user was trying to do, e.g. "save your plan".
    var featureCopy: String = "save your plan, sync across devices, and continue"
    /// Called once the user is signed in and any conflict is resolved.
    var onAuthenticated: () -> Void

    @State private var working = false
    @State private var errorMessage: String?
    @State private var showConflict = false
    @State private var showSaveOffer = false

    @State private var appleCoordinator = AppleSignInCoordinator()
    private let auth = AuthService()

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Spacer(minLength: 16)

                Image(systemName: "lock.icloud.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 10) {
                    Text("Sign in to save your plan")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Sign in with Apple to \(featureCopy).")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Text(EntitlementService.subscriptionPlaceholderCopy)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 2)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote).foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center).padding(.horizontal, 28)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: handleApple) {
                        HStack(spacing: 10) {
                            if working { ProgressView().tint(.black) }
                            else { Image(systemName: "apple.logo").font(.system(size: 18, weight: .medium)) }
                            Text("Continue with Apple").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(.black)
                    }
                    .disabled(working)

                    Button("Not now / Back") { dismiss() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .disabled(working)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showConflict) {
            ConflictResolutionView(
                onResolved: { finish() },
                onCancel: { /* stay signed in, just close gate */ finish() }
            )
            .environment(state)
        }
        .confirmationDialog("Save this assessment to your Apple account?",
                            isPresented: $showSaveOffer, titleVisibility: .visible) {
            Button("Save to my account") {
                Task { await state.uploadLocalAssessment(); finish() }
            }
            Button("Not now") { finish() }
        } message: {
            Text("Your current answers and report will be saved to your DeskFit account.")
        }
    }

    private func finish() {
        Haptics.success()
        onAuthenticated()
        dismiss()
    }

    private func handleApple() {
        errorMessage = nil
        working = true
        Task {
            do {
                let result = try await appleCoordinator.signIn()
                try await auth.signInWithApple(
                    identityToken: result.identityToken,
                    email: result.email,
                    fullName: result.fullName,
                    authorizationCode: result.authorizationCode)
                let outcome = await state.handleAppleSignIn()
                working = false
                switch outcome {
                case .conflict:
                    showConflict = true
                case .offerSaveLocal:
                    showSaveOffer = true
                case .loadedBackend, .noBackendNeedsAssessment:
                    finish()
                case .error(let msg):
                    errorMessage = msg
                }
            } catch {
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    working = false
                    return
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Apple sign-in failed."
                working = false
            }
        }
    }
}
