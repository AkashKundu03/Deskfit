import Foundation

/// Deterministic mock health source for the Simulator, previews, and testing the
/// flows without a paired device. Numbers vary by day but are stable per date.
struct MockHealthProvider: HealthDataProviding {
    var isAvailable: Bool { true }

    func requestAuthorization() async -> Bool { true }

    func aggregate(forLocalDate date: Date) async -> HealthDailyAggregate? {
        var agg = HealthDailyAggregate(date: HealthDates.isoDay(date), timezone: TimeZone.current.identifier)
        // Stable pseudo-values derived from the day-of-year.
        let doy = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        agg.steps = 6000 + (doy % 7) * 600
        agg.activeEnergyKcal = 320 + (doy % 5) * 40
        agg.exerciseMinutes = 25 + (doy % 4) * 8
        agg.sleepMinutes = 390 + (doy % 6) * 12
        agg.restingHR = 56 + (doy % 5)
        agg.hrv = 55 + Double(doy % 9)
        agg.workoutCount = (doy % 3 == 0) ? 1 : 0
        agg.workoutMinutes = (doy % 3 == 0) ? 40 : 0
        agg.sourceCoverage = ["steps": "Mock Watch", "sleep": "Mock"]
        agg.sampleTimestamps = ["steps": ISO8601DateFormatter().string(from: date)]
        return agg
    }

    func recentAggregates(days: Int) async -> [HealthDailyAggregate] {
        var out: [HealthDailyAggregate] = []
        for i in 0..<max(1, days) {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()),
               let a = await aggregate(forLocalDate: d) {
                out.append(a)
            }
        }
        return out
    }
}
