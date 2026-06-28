import Foundation
import HealthKit

/// Drives an explicit HKWorkoutSession with a live builder, exposing heart rate,
/// zone, elapsed time and active energy. HealthKit is the saved-workout truth.
@Observable
final class WorkoutManager: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var heartRate: Double = 0
    private(set) var activeEnergyKcal: Double = 0
    private(set) var elapsed: TimeInterval = 0

    /// User's estimated max HR for zone display (220 − age, defaulted).
    var maxHR: Double = 190

    private var timer: Timer?

    func requestAuthorization() async -> Bool {
        let share: Set = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        do { try await store.requestAuthorization(toShare: share, read: read); return true }
        catch { return false }
    }

    func start() {
        guard !isRunning else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            isRunning = true
            isPaused = false
            startTimer()
        } catch {
            isRunning = false
        }
    }

    func pause() { session?.pause(); isPaused = true; timer?.invalidate() }
    func resume() { session?.resume(); isPaused = false; startTimer() }

    func end() {
        timer?.invalidate()
        session?.end()
        isRunning = false
        isPaused = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let builder = self.builder else { return }
            Task { @MainActor in self.elapsed = builder.elapsedTime }
        }
    }

    var zone: Int {
        guard heartRate > 0 else { return 0 }
        let pct = heartRate / maxHR
        switch pct {
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            builder?.endCollection(withEnd: date) { [weak self] _, _ in
                self?.builder?.finishWorkout { _, _ in }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let qt = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: qt) else { continue }
            if qt == HKQuantityType(.heartRate) {
                let bpm = stats.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                Task { @MainActor in self.heartRate = bpm }
            } else if qt == HKQuantityType(.activeEnergyBurned) {
                let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                Task { @MainActor in self.activeEnergyKcal = kcal }
            }
        }
    }
}
