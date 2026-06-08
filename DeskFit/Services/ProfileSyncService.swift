import Foundation

/// Pushes the local user profile to the backend (PUT /me/profile).
struct ProfileSyncService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func sync(_ profile: UserProfile) async throws {
        try await client.put("me/profile", body: ProfileSyncDTO(profile: profile))
    }
}
