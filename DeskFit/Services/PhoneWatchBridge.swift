import Foundation
import WatchConnectivity

// ─────────────────────────────────────────────────────────────────────────────
// iPhone side of the watchOS companion link. Pushes today's workout + meals to
// the Watch and handles actions sent back (meal/workout completion, check-ins).
// Safe with no Watch paired — every call is guarded and best-effort. Live
// workout "truth" is saved by the Watch via HealthKit, not here.
// ─────────────────────────────────────────────────────────────────────────────

// Payload mirror of the watch-side `WatchModels` (kept local to the iOS target).
private struct WSExercise: Codable { let id: String; let name: String; let detail: String }
private struct WSWorkout: Codable { let title: String; let durationMin: Int; let focusLabel: String; let exercises: [WSExercise] }
private struct WSMeal: Codable { let id: String; let slot: String; let name: String; let kcal: Int; let proteinG: Int; var status: String }
private struct WSSnapshot: Codable { let date: String; let workout: WSWorkout?; let meals: [WSMeal] }
private struct WSAction: Codable {
    let action: String
    var mealId: String?
    var energy: Int?
    var soreness: Int?
    var workoutMinutes: Int?
    var activeEnergyKcal: Int?
}

final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    private let plans = PlanService()
    private let meals = MealTemplateService()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Gather today's plan and push it to the Watch (application context = latest
    /// state, delivered even if the Watch is asleep).
    func syncToday() async {
        guard WCSession.isSupported() else { return }

        var workout: WSWorkout?
        if let plan = await plans.currentWeeklyPlan(),
           let s = plan.sessions.first(where: { $0.date == Weekdays.todayISO() }) {
            workout = WSWorkout(title: s.title, durationMin: s.durationMin, focusLabel: s.focusLabel,
                                exercises: s.exercises.prefix(10).map { WSExercise(id: $0.id, name: $0.name, detail: $0.detail) })
        } else if let sa = await plans.currentStandalone() {
            workout = WSWorkout(title: sa.title, durationMin: sa.durationMin, focusLabel: sa.focusLabel,
                                exercises: sa.main.prefix(10).map { WSExercise(id: $0.id, name: $0.name, detail: $0.detail) })
        }

        var mealRows: [WSMeal] = []
        if let wm = await meals.current(), let day = wm.today() {
            mealRows = day.meals.map { WSMeal(id: $0.id, slot: $0.slot, name: $0.name, kcal: $0.kcal, proteinG: $0.proteinG, status: $0.status) }
        }

        let snap = WSSnapshot(date: Weekdays.todayISO(), workout: workout, meals: mealRows)
        guard let data = try? JSONEncoder().encode(snap),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": obj])
    }

    // MARK: - Incoming actions from the Watch

    private func handle(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let msg = try? JSONDecoder().decode(WSAction.self, from: data) else { return }
        Task {
            switch msg.action {
            case "completeMeal":
                if let id = msg.mealId { _ = await meals.completeMeal(id) }
            case "skipMeal":
                if let id = msg.mealId { _ = await meals.skipMeal(id) }
            case "checkIn":
                _ = await HealthService.shared.submitCheckIn(energy: msg.energy, soreness: msg.soreness, mood: nil, stress: nil)
            case "completeWorkout":
                if let plan = await plans.currentWeeklyPlan(),
                   let s = plan.sessions.first(where: { $0.date == Weekdays.todayISO() }) {
                    _ = await plans.completeSession(s.id)
                }
            default:
                break
            }
            await syncToday() // reflect the change back to the Watch
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { await syncToday() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }
}
