import Foundation

/// Recovery-signal insight from the backend (deterministic, baseline-based).
/// Educational guidance — never a diagnosis.
struct HealthInsight: Codable, Equatable {
    let status: String       // learning | onTrack | recoveryLower
    let coverageDays: Int
    let title: String
    let message: String
    let factors: [String]
    let action: String
    let baseline: HealthBaseline
}

struct HealthBaseline: Codable, Equatable {
    let restingHR: Double?
    let hrv: Double?
    let sleepMinutes: Double?
}

struct HealthCheckInRequest: Encodable {
    let date: String
    let energy: Int?
    let soreness: Int?
    let mood: Int?
    let stress: Int?
}
