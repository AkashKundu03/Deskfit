import Foundation

private struct DeleteAccountRequest: Encodable { let reason: String? }

/// Account deletion / scheduling against the backend.
struct AccountService {
    private let client = APIClient()

    /// Delete immediately (revokes Apple credentials + removes all backend data).
    func deleteNow(reason: String?) async -> Bool {
        do { try await client.post("me/account/delete", body: DeleteAccountRequest(reason: reason), authorized: true); return true }
        catch { return false }
    }

    /// Schedule deletion in 7 days (recoverable until then).
    func schedule(reason: String?) async -> Bool {
        do { try await client.post("me/account/schedule-deletion", body: DeleteAccountRequest(reason: reason), authorized: true); return true }
        catch { return false }
    }

    /// Recover an account during the window.
    func cancel() async -> Bool {
        do { try await client.post("me/account/cancel-deletion", body: EmptyBody(), authorized: true); return true }
        catch { return false }
    }
}
