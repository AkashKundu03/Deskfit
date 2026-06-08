import Foundation

/// Pushes the local gut answers to the backend (PUT /me/gut-answers).
struct GutAnswersSyncService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func sync(_ answers: GutAnswers) async throws {
        try await client.put("me/gut-answers", body: GutAnswersSyncDTO(gut: answers))
    }
}
