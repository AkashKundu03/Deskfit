import Foundation
import HealthKit

/// Production HealthKit source. Reads daily aggregates only; raw samples never
/// leave the device. Every query is defensive — any failure or missing data
/// yields nil for that metric, never a crash, and the app keeps working.
struct HealthKitProvider: HealthDataProviding {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Only the types we actually use.
    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
        // Optional where supported.
        set.insert(HKQuantityType(.oxygenSaturation))
        return set
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: readTypes,
            )
            return true
        } catch {
            return false
        }
    }

    func aggregate(forLocalDate date: Date) async -> HealthDailyAggregate? {
        guard isAvailable else { return nil }
        let (start, end) = HealthDates.dayBounds(date)
        var agg = HealthDailyAggregate(date: HealthDates.isoDay(date), timezone: TimeZone.current.identifier)
        var coverage: [String: String] = [:]

        if let (v, src) = await sum(HKQuantityType(.stepCount), unit: .count(), start, end) {
            agg.steps = Int(v); if let src { coverage["steps"] = src }
        }
        if let (v, src) = await sum(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), start, end) {
            agg.activeEnergyKcal = Int(v); if let src { coverage["activeEnergy"] = src }
        }
        if let (v, _) = await sum(HKQuantityType(.appleExerciseTime), unit: .minute(), start, end) {
            agg.exerciseMinutes = Int(v)
        }
        if let (v, src) = await avg(HKQuantityType(.restingHeartRate), unit: HKUnit(from: "count/min"), start, end) {
            agg.restingHR = Int(v); if let src { coverage["restingHR"] = src }
        }
        if let (v, _) = await avg(HKQuantityType(.heartRateVariabilitySDNN),
                                  unit: HKUnit.secondUnit(with: .milli), start, end) {
            agg.hrv = (v * 10).rounded() / 10
        }
        if let (mins, src) = await sleepMinutes(start, end) {
            agg.sleepMinutes = mins; if let src { coverage["sleep"] = src }
        }
        if let (count, mins, src) = await workouts(start, end) {
            agg.workoutCount = count; agg.workoutMinutes = mins; if let src { coverage["workouts"] = src }
        }

        if !coverage.isEmpty { agg.sourceCoverage = coverage }
        return agg.hasAnyData ? agg : agg   // return even if empty so "last updated" still moves
    }

    func recentAggregates(days: Int) async -> [HealthDailyAggregate] {
        var out: [HealthDailyAggregate] = []
        for i in 0..<max(1, days) {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()),
               let a = await aggregate(forLocalDate: d), a.hasAnyData {
                out.append(a)
            }
        }
        return out
    }

    // MARK: - Query helpers

    private func sum(_ type: HKQuantityType, unit: HKUnit, _ start: Date, _ end: Date) async -> (Double, String?)? {
        await statistics(type, options: .cumulativeSum, start, end) { stats in
            stats.sumQuantity().map { ($0.doubleValue(for: unit), stats.sources?.first?.name) }
        }
    }

    private func avg(_ type: HKQuantityType, unit: HKUnit, _ start: Date, _ end: Date) async -> (Double, String?)? {
        await statistics(type, options: .discreteAverage, start, end) { stats in
            stats.averageQuantity().map { ($0.doubleValue(for: unit), stats.sources?.first?.name) }
        }
    }

    private func statistics(_ type: HKQuantityType, options: HKStatisticsOptions,
                            _ start: Date, _ end: Date,
                            _ extract: @escaping (HKStatistics) -> (Double, String?)?) async -> (Double, String?)? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                cont.resume(returning: stats.flatMap(extract))
            }
            store.execute(q)
        }
    }

    private func sleepMinutes(_ start: Date, _ end: Date) async -> (Int, String?)? {
        // Look back from midnight of `start` to capture the prior night's sleep.
        let lookback = Calendar.current.date(byAdding: .hour, value: -18, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: lookback, end: end, options: [])
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let seconds = samples
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let src = samples.first?.sourceRevision.source.name
                cont.resume(returning: seconds > 0 ? (Int(seconds / 60), src) : nil)
            }
            store.execute(q)
        }
    }

    private func workouts(_ start: Date, _ end: Date) async -> (Int, Int, String?)? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let minutes = workouts.reduce(0.0) { $0 + $1.duration } / 60
                let src = workouts.first?.sourceRevision.source.name
                cont.resume(returning: (workouts.count, Int(minutes), src))
            }
            store.execute(q)
        }
    }
}
