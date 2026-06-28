import AuthenticationServices
import UIKit

struct AppleSignInResult {
    let identityToken: String
    let email: String?
    let fullName: String?
    /// Authorization code — sent to the backend so it can capture a refresh token
    /// for proper credential revocation at account deletion.
    let authorizationCode: String?
}

/// Drives a native Sign in with Apple flow and returns the identity token.
/// Note: requires the "Sign in with Apple" capability to be enabled in the
/// target's Signing & Capabilities to succeed at runtime (see README/setup).
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    // ASAuthorizationController's delegate/presentationContextProvider are WEAK,
    // and nothing else retains the controller — so we must hold it strongly here
    // until the callback fires, or it deallocates mid-flow and the callback never
    // arrives (symptom: the Apple sheet completes but sign-in hangs on loading).
    private var controller: ASAuthorizationController?

    func signIn() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleSignInResult, Error>) {
        controller = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AuthFlowError.message("Apple did not return an identity token.")))
            return
        }

        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
        let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

        finish(.success(AppleSignInResult(
            identityToken: token,
            email: credential.email,
            fullName: fullName,
            authorizationCode: authCode
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
