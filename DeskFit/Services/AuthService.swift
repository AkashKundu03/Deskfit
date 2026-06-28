import Foundation

/// Generic auth-flow error with a user-facing message.
enum AuthFlowError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Authentication against the backend. On success the returned DeskFit JWT is
/// stored in the Keychain via KeychainTokenStore.
struct AuthService {
    private let client: APIClient
    private let tokenStore: KeychainTokenStore

    init(client: APIClient = APIClient(), tokenStore: KeychainTokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
    }

    // MARK: - Social sign-in (primary user flow)

    func signInWithApple(identityToken: String, email: String?, fullName: String?,
                         authorizationCode: String?) async throws {
        let res = try await client.post(
            "auth/apple",
            body: AppleAuthRequest(identityToken: identityToken, email: email, fullName: fullName,
                                   authorizationCode: authorizationCode),
            authorized: false,
            as: AuthResponse.self
        )
        tokenStore.saveToken(res.accessToken)
    }

    // Google sign-in has been removed from the iOS app. The backend route still
    // exists for safety/compatibility, but the app never calls it.

    func logout() {
        tokenStore.clearToken()
    }

    // MARK: - Hidden development email/password fallback
    // Not shown in the normal user flow — only reachable via the debug gesture
    // on AuthView. Kept for local testing against /auth/signup and /auth/login.

    func devEmailSignup(email: String, password: String) async throws {
        let res = try await client.post(
            "auth/signup",
            body: AuthRequest(email: email, password: password),
            authorized: false,
            as: AuthResponse.self
        )
        tokenStore.saveToken(res.accessToken)
    }

    func devEmailLogin(email: String, password: String) async throws {
        let res = try await client.post(
            "auth/login",
            body: AuthRequest(email: email, password: password),
            authorized: false,
            as: AuthResponse.self
        )
        tokenStore.saveToken(res.accessToken)
    }
}
