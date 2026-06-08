import SwiftUI
import AuthenticationServices

/// Premium full-screen social sign-in step. Shown after the assessment and
/// before the report. Email/password is hidden from normal users and only
/// reachable via a long-press debug gesture on the footer.
struct AuthView: View {
    @Environment(AppState.self) private var state

    /// Called after a successful sign-in OR when the user taps "Not now".
    /// The caller proceeds to generate and show the report either way.
    var onFinish: () -> Void

    private enum Provider { case apple, google }

    @State private var working: Provider?
    @State private var errorMessage: String?
    @State private var appear = false
    @State private var showDevLogin = false

    @State private var appleCoordinator = AppleSignInCoordinator()
    private let auth = AuthService()

    var body: some View {
        ZStack {
            AppBackground()
            glow

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                wellnessVisual
                    .scaleEffect(appear ? 1 : 0.9)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 12) {
                    Text("Save your health journey.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Your report, progress, and daily wellness journey stay synced securely across devices.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.top, 28)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                }

                Spacer()

                VStack(spacing: 12) {
                    socialButton(title: "Continue with Apple", systemImage: "apple.logo",
                                 isBusy: working == .apple, action: handleApple)
                    socialButton(title: "Continue with Google", systemImage: "globe",
                                 isBusy: working == .google, action: handleGoogle)
                }
                .disabled(working != nil)
                .padding(.horizontal, 24)

                Button("Not now") { onFinish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 16)
                    .disabled(working != nil)

                termsFooter
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appear = true } }
        .sheet(isPresented: $showDevLogin) { devLoginSheet }
    }

    // MARK: - Pieces

    private var glow: some View {
        Circle()
            .fill(Theme.accent.opacity(0.25))
            .frame(width: 320, height: 320)
            .blur(radius: 90)
            .offset(y: -200)
    }

    private var wellnessVisual: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), .clear],
                                     center: .center, startRadius: 4, endRadius: 130))
                .frame(width: 240, height: 240)
                .blur(radius: 18)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 190, height: 190)
            Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 145, height: 145)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 115, height: 115)
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.5), radius: 12)
            Image(systemName: "leaf.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
        }
        .frame(height: 240)
    }

    private func socialButton(title: String, systemImage: String, isBusy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .medium))
                }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(.white))
            .foregroundStyle(.black)
        }
    }

    private var termsFooter: some View {
        (
            Text("By continuing, you agree to ").foregroundStyle(.white.opacity(0.5))
            + Text("Terms").underline().foregroundStyle(.white.opacity(0.8))
            + Text(" and ").foregroundStyle(.white.opacity(0.5))
            + Text("Privacy").underline().foregroundStyle(.white.opacity(0.8))
            + Text(".").foregroundStyle(.white.opacity(0.5))
        )
        .font(.caption)
        .multilineTextAlignment(.center)
        // Hidden developer fallback: long-press the footer to reveal email/password.
        .onLongPressGesture(minimumDuration: 1.2) { showDevLogin = true }
    }

    // MARK: - Actions

    private func handleApple() {
        errorMessage = nil
        working = .apple
        Task {
            do {
                let result = try await appleCoordinator.signIn()
                try await auth.signInWithApple(
                    identityToken: result.identityToken,
                    email: result.email,
                    fullName: result.fullName)
                await state.registerSocialLogin()
                working = nil
                onFinish()
            } catch {
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    working = nil
                    return
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Apple sign-in failed."
                working = nil
            }
        }
    }

    private func handleGoogle() {
        errorMessage = nil
        working = .google
        Task {
            do {
                let idToken = try await GoogleSignInHelper.signIn()
                try await auth.signInWithGoogle(idToken: idToken)
                await state.registerSocialLogin()
                working = nil
                onFinish()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Google sign-in failed."
                working = nil
            }
        }
    }

    // MARK: - Hidden dev email/password sheet

    private var devLoginSheet: some View {
        DevEmailLoginView(auth: auth) {
            await state.registerSocialLogin()
            showDevLogin = false
            onFinish()
        }
        .environment(state)
    }
}

/// Development-only email/password form (hidden behind the long-press gesture).
private struct DevEmailLoginView: View {
    let auth: AuthService
    var onSuccess: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isValid: Bool { email.contains("@") && password.count >= 8 }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 16) {
                Text("Developer Login")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Hidden email/password fallback for local testing only.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(spacing: 14) {
                        field("Email", text: $email, secure: false)
                        field("Password (min 8 characters)", text: $password, secure: true)
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button { run(signUp: true) } label: { busyLabel("Sign Up") }
                        .buttonStyle(PillButtonStyle(filled: true))
                    Button { run(signUp: false) } label: { busyLabel("Login") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
                .disabled(isWorking || !isValid)
                .opacity(isValid ? 1 : 0.6)

                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
                    .keyboardType(.emailAddress)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(.white)
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func busyLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if isWorking { ProgressView() }
            Text(title)
        }
    }

    private func run(signUp: Bool) {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                if signUp {
                    try await auth.devEmailSignup(email: email, password: password)
                } else {
                    try await auth.devEmailLogin(email: email, password: password)
                }
                await onSuccess()
                isWorking = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
                isWorking = false
            }
        }
    }
}
