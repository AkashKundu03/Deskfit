import Foundation
import HealthKit

/// Coordinates the optional HealthKit integration. The app never depends on it —
/// when not connected, everything still works. Connection + sync opt-in are
/// separate, explicit choices, persisted on-device.
@Observable
final class HealthService {
    static let shared = HealthService()

    private let provider: HealthDataProviding
    private let upload = HealthUploadService()
    private let defaults = UserDefaults.standard

    private enum K {
        static let connected = "health.connected"
        static let sync = "health.syncEnabled"
        static let lastUpdated = "health.lastUpdated"
        static let nudges = "health.recoveryNudges"
    }

    /// Opt-in for discreet recovery nudges (local notifications).
    private(set) var recoveryNudgesEnabled: Bool = UserDefaults.standard.bool(forKey: K.nudges)

    /// Whether HealthKit exists on this device.
    private(set) var available: Bool
    /// Whether the user has connected (we've requested authorization).
    private(set) var connected: Bool
    /// Separate opt-in for uploading daily aggregates to DeskFit.
    private(set) var syncEnabled: Bool
    private(set) var lastUpdated: Date?
    private(set) var todayAggregate: HealthDailyAggregate?

    private init() {
        #if targetEnvironment(simulator)
        // Simulator has no real Health data — use the mock so the flow is testable.
        provider = MockHealthProvider()
        available = true
        #else
        let hk = HealthKitProvider()
        provider = hk
        available = hk.isAvailable
        #endif
        connected = defaults.bool(forKey: K.connected)
        syncEnabled = defaults.bool(forKey: K.sync)
        let ts = defaults.double(forKey: K.lastUpdated)
        lastUpdated = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    var connectionState: HealthConnectionState {
        if !available { return .unavailable }
        return connected ? .connected : .notConnected
    }

    /// Connect: request authorization, then pull today's aggregate.
    @discardableResult
    func connect() async -> Bool {
        guard available else { return false }
        let granted = await provider.requestAuthorization()
        guard granted else { return false }
        connected = true
        defaults.set(true, forKey: K.connected)
        await refresh()
        return true
    }

    /// Stop using Health locally. (Full read-permission revocation happens in
    /// iOS Settings › Privacy › Health — we surface that to the user.)
    func disconnect() {
        connected = false
        syncEnabled = false
        todayAggregate = nil
        defaults.set(false, forKey: K.connected)
        defaults.set(false, forKey: K.sync)
    }

    /// Toggle the separate "sync daily insights" opt-in. Enabling triggers an
    /// immediate upload of today's aggregate.
    func setSync(_ on: Bool) {
        syncEnabled = on
        defaults.set(on, forKey: K.sync)
        if on { Task { await refresh() } }
    }

    // MARK: - Insights & check-ins

    /// Fetch the recovery-signal insight (requires sign-in + synced data).
    func currentInsight() async -> HealthInsight? {
        guard KeychainTokenStore.shared.isAuthenticated else { return nil }
        return try? await APIClient().get("me/health/insight?date=\(HealthDates.isoDay(Date()))",
                                          authorized: true, as: HealthInsight.self)
    }

    /// Submit today's subjective check-in, then return the refreshed insight.
    func submitCheckIn(energy: Int?, soreness: Int?, mood: Int?, stress: Int?) async -> HealthInsight? {
        guard KeychainTokenStore.shared.isAuthenticated else { return nil }
        let body = HealthCheckInRequest(date: HealthDates.isoDay(Date()),
                                        energy: energy, soreness: soreness, mood: mood, stress: stress)
        try? await APIClient().put("me/health/checkin", body: body, authorized: true)
        return await currentInsight()
    }

    func setRecoveryNudges(_ on: Bool) {
        recoveryNudgesEnabled = on
        defaults.set(on, forKey: K.nudges)
        if !on { NotificationService.shared.cancelRecoveryNudge() }
    }

    /// Schedule a discreet nudge ONLY when recovery is lower and the user opted in.
    func maybeScheduleNudge(for insight: HealthInsight) async {
        guard recoveryNudgesEnabled, insight.status == "recoveryLower" else { return }
        await NotificationService.shared.scheduleRecoveryNudge()
    }

    /// Refresh today's aggregate from Health; upload only if sync is enabled and
    /// the user is signed in. Safe to call on every foreground.
    func refresh() async {
        guard connected else { return }
        let agg = await provider.todayAggregate()
        await MainActor.run {
            self.todayAggregate = agg
            self.lastUpdated = Date()
            self.defaults.set(Date().timeIntervalSince1970, forKey: K.lastUpdated)
        }
        if syncEnabled, let agg, agg.hasAnyData, KeychainTokenStore.shared.isAuthenticated {
            await upload.upload(agg)
        }
    }
}

/// Uploads opt-in daily aggregates to the backend.
struct HealthUploadService {
    private let client = APIClient()

    func upload(_ agg: HealthDailyAggregate) async {
        try? await client.put("me/health/daily", body: agg, authorized: true)
    }

    func uploadRecent(_ aggregates: [HealthDailyAggregate]) async {
        guard !aggregates.isEmpty else { return }
        try? await client.post("me/health/daily/batch",
                               body: ["days": aggregates], authorized: true)
    }
}
