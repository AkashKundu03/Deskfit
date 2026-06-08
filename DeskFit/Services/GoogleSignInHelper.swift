import Foundation
#if canImport(GoogleSignIn)
import GoogleSignIn
import UIKit
#endif

/// Retrieves a Google ID token for the backend.
///
/// The real implementation is gated behind `canImport(GoogleSignIn)` so the app
/// compiles whether or not the GoogleSignIn-iOS Swift Package is installed. Once
/// the package, client id, and reversed-client-id URL scheme are configured (see
/// README / setup notes), this lights up automatically; until then the button
/// surfaces a friendly setup message.
enum GoogleSignInHelper {
    // TODO: Paste your iOS OAuth client id from Google Cloud Console here, e.g.
    //       "1234567890-abcdef.apps.googleusercontent.com".
    //       You ALSO must add the matching reversed client id as a URL scheme in
    //       Info.plist (URL Types) for the OAuth redirect to return to the app.
    static let clientID: String? = nil

    /// True only when the package is linked AND a client id has been provided.
    static var isConfigured: Bool {
        #if canImport(GoogleSignIn)
        return clientID != nil
        #else
        return false
        #endif
    }

    static func signIn() async throws -> String {
        #if canImport(GoogleSignIn)
        guard let clientID else {
            throw AuthFlowError.message("Google Sign-In needs a client id (see GoogleSignInHelper.clientID).")
        }
        guard let rootVC = await rootViewController() else {
            throw AuthFlowError.message("No active window to present Google Sign-In.")
        }
        // Configure programmatically so no Info.plist GIDClientID entry is required.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthFlowError.message("Google did not return an ID token.")
        }
        return idToken
        #else
        throw AuthFlowError.message(
            "Google Sign-In isn’t set up yet. Add the GoogleSignIn-iOS package (see README).")
        #endif
    }

    #if canImport(GoogleSignIn)
    @MainActor
    private static func rootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.rootViewController
    }
    #endif
}
