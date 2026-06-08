import Foundation

/// Pushes the locally generated report to the backend (PUT /me/report).
struct ReportSyncService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func sync(_ report: HealthReport) async throws {
        try await client.put("me/report", body: ReportSyncDTO(report: report))
    }
}
