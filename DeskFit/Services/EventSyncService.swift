import Foundation

/// Records an analytics event on the backend (POST /me/events). Best-effort.
struct EventSyncService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func track(_ eventName: String, metadata: [String: String]? = nil) async throws {
        try await client.post("me/events", body: EventSyncDTO(eventName: eventName, metadata: metadata))
    }
}
