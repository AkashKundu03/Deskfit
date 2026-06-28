import Foundation

/// Abstraction over the health data source so the app can run with the real
/// HealthKit provider, a mock (previews/simulator/tests), or nothing at all.
protocol HealthDataProviding {
    /// Whether a real health source exists on this device.
    var isAvailable: Bool { get }

    /// Request read authorization for the relevant types. Returns whether the
    /// permission sheet completed without error (HealthKit never reveals whether
    /// READ access was actually granted — we treat completion as "connected").
    func requestAuthorization() async -> Bool

    /// Today's aggregate (nil if unavailable / no data).
    func aggregate(forLocalDate date: Date) async -> HealthDailyAggregate?

    /// The last `days` aggregates (most recent first), skipping empty days.
    func recentAggregates(days: Int) async -> [HealthDailyAggregate]
}

extension HealthDataProviding {
    func todayAggregate() async -> HealthDailyAggregate? {
        await aggregate(forLocalDate: Date())
    }
}

/// Shared local-date helpers for health aggregation.
enum HealthDates {
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func dayBounds(_ date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
