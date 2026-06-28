import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3 — optional HealthKit. The app NEVER depends on these; they enrich the
// experience when the user opts in. Raw samples stay on-device; only this daily
// aggregate is ever uploaded, and only with explicit sync consent.
// ─────────────────────────────────────────────────────────────────────────────

/// One day's opt-in health aggregate. Field names match the backend
/// `HealthDailyDto`, so this doubles as the upload body. All optional — partial
/// coverage (e.g. no HRV on a given day) is normal and safe.
struct HealthDailyAggregate: Codable, Equatable {
    var date: String          // yyyy-MM-dd (user-local civil day)
    var timezone: String
    var steps: Int?
    var activeEnergyKcal: Int?
    var exerciseMinutes: Int?
    var sleepMinutes: Int?
    var restingHR: Int?
    var hrv: Double?
    var workoutCount: Int?
    var workoutMinutes: Int?
    var sourceCoverage: [String: String]?     // metric → contributing source/device
    var sampleTimestamps: [String: String]?   // metric → most-recent sample time (ISO)

    init(date: String, timezone: String) {
        self.date = date
        self.timezone = timezone
    }

    /// True if at least one metric was captured (so we don't upload empty days).
    var hasAnyData: Bool {
        steps != nil || activeEnergyKcal != nil || exerciseMinutes != nil ||
        sleepMinutes != nil || restingHR != nil || hrv != nil || workoutCount != nil
    }
}

/// High-level connection state for the Profile card.
enum HealthConnectionState: Equatable {
    case unavailable     // device has no HealthKit (e.g. iPad without it)
    case notConnected    // available but user hasn't connected
    case connected       // user connected (we've requested authorization)
}
