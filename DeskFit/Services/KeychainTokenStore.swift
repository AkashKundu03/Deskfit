import Foundation
import Security

/// Securely stores the backend JWT access token in the iOS Keychain.
/// The JWT is deliberately NOT stored in UserDefaults.
final class KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let service = "com.deskfit.auth"
    private let account = "accessToken"

    func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    var isAuthenticated: Bool { getToken() != nil }
}
