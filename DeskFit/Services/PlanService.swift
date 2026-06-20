import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Facade for the Phase 2 planner. Resolution order mirrors CoachService:
//   • Demo mode      → local engine, kept IN-MEMORY only (never persisted /
//                      networked) so demo data stays fully separate from real
//                      user data.
//   • Authenticated  → live backend (DB-backed persistence), result cached
//                      locally for instant offline reload.
//   • Otherwise      → local engine + on-device cache (continuity without login).
// The UI calls only this type and always gets a populated, mutating plan.
// ─────────────────────────────────────────────────────────────────────────────

struct PlanService {
    private let client = APIClient()
    private let persistence = PersistenceService()
    private let tokenStore = KeychainTokenStore.shared

    // Demo plans live only for the app session — they never touch UserDefaults
    // or the backend, keeping the VC demo isolated from real accounts.
    private static var demoWeekly: WeeklyWorkoutPlan?
    private static var demoMeal: MealPlanResult?

    private var isAuthed: Bool { tokenStore.isAuthenticated }

    // MARK: - Weekly workout plan

    func createWeeklyPlan(_ req: CreateWeeklyPlanRequest) async -> WeeklyWorkoutPlan {
        if AppConfig.useDemoData {
            let p = localWeekly(from: req)
            Self.demoWeekly = p
            return p
        }
        if isAuthed,
           let p = try? await client.post("workouts/weekly-plan", body: req, authorized: true, as: WeeklyWorkoutPlan.self) {
            cacheWeekly(p)
            return p
        }
        let p = localWeekly(from: req)
        cacheWeekly(p)
        return p
    }

    func currentWeeklyPlan() async -> WeeklyWorkoutPlan? {
        if AppConfig.useDemoData { return Self.demoWeekly }
        if isAuthed,
           let p = try? await client.get("workouts/weekly-plan/current", authorized: true, as: WeeklyWorkoutPlan.self) {
            cacheWeekly(p)
            return p
        }
        return cachedWeekly()
    }

    func completeSession(_ sessionId: String) async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/session/complete",
                           body: SessionActionRequest(sessionId: sessionId),
                           local: { PlanLocalEngine.setStatus($0, sessionId: sessionId, status: "completed") })
    }

    func skipSession(_ sessionId: String) async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/session/skip",
                           body: SessionActionRequest(sessionId: sessionId),
                           local: { PlanLocalEngine.setStatus($0, sessionId: sessionId, status: "skipped") })
    }

    func rescheduleSession(_ sessionId: String, to weekday: String) async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/session/reschedule",
                           body: RescheduleSessionRequest(sessionId: sessionId, toWeekday: weekday),
                           local: { PlanLocalEngine.reschedule($0, sessionId: sessionId, toWeekday: weekday) })
    }

    func shorterSession(_ sessionId: String) async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/session/shorter",
                           body: SessionActionRequest(sessionId: sessionId),
                           local: { PlanLocalEngine.shorter($0, sessionId: sessionId) })
    }

    func rebalanceWeek() async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/rebalance-week",
                           body: EmptyBody(),
                           local: { PlanLocalEngine.rebalance($0) })
    }

    // MARK: - Meal target plan

    func createMealPlan(_ req: CreateMealPlanRequest) async -> MealPlanResult {
        if AppConfig.useDemoData {
            let p = localMeal(from: req)
            Self.demoMeal = p
            return p
        }
        if isAuthed,
           let p = try? await client.post("nutrition/meal-plan", body: req, authorized: true, as: MealPlanResult.self) {
            cacheMeal(p)
            return p
        }
        let p = localMeal(from: req)
        cacheMeal(p)
        return p
    }

    func currentMealPlan() async -> MealPlanResult? {
        if AppConfig.useDemoData { return Self.demoMeal }
        if isAuthed,
           let p = try? await client.get("nutrition/meal-plan/today", authorized: true, as: MealPlanResult.self) {
            cacheMeal(p)
            return p
        }
        return cachedMeal()
    }

    func completeMeal(_ mealId: String) async -> MealPlanResult? {
        await mutateMeal(path: "nutrition/meal/complete",
                         body: MealActionRequest(mealId: mealId),
                         local: { PlanLocalEngine.setMealStatus($0, mealId: mealId, status: "completed") })
    }

    func skipMeal(_ mealId: String) async -> MealPlanResult? {
        await mutateMeal(path: "nutrition/meal/skip",
                         body: MealActionRequest(mealId: mealId),
                         local: { PlanLocalEngine.setMealStatus($0, mealId: mealId, status: "skipped") })
    }

    /// Clears the cached real-user plans (called on logout). Demo stays untouched.
    func clearRealCaches() { persistence.clearPlanCaches() }

    // MARK: - Shared mutation helpers

    private func mutateWeekly<B: Encodable>(path: String, body: B,
                                            local: (WeeklyWorkoutPlan) -> WeeklyWorkoutPlan) async -> WeeklyWorkoutPlan? {
        if AppConfig.useDemoData {
            guard let cur = Self.demoWeekly else { return nil }
            let p = local(cur); Self.demoWeekly = p; return p
        }
        if isAuthed,
           let p = try? await client.post(path, body: body, authorized: true, as: WeeklyWorkoutPlan.self) {
            cacheWeekly(p)
            return p
        }
        guard let cur = cachedWeekly() else { return nil }
        let p = local(cur); cacheWeekly(p); return p
    }

    private func mutateMeal<B: Encodable>(path: String, body: B,
                                          local: (MealPlanResult) -> MealPlanResult) async -> MealPlanResult? {
        if AppConfig.useDemoData {
            guard let cur = Self.demoMeal else { return nil }
            let p = local(cur); Self.demoMeal = p; return p
        }
        if isAuthed,
           let p = try? await client.post(path, body: body, authorized: true, as: MealPlanResult.self) {
            cacheMeal(p)
            return p
        }
        guard let cur = cachedMeal() else { return nil }
        let p = local(cur); cacheMeal(p); return p
    }

    // MARK: - Local builders + cache

    private func localWeekly(from req: CreateWeeklyPlanRequest) -> WeeklyWorkoutPlan {
        PlanLocalEngine.buildWeekly(selectedDays: req.selectedDays, location: req.location,
                                    durationMin: req.durationMin, equipment: req.equipment,
                                    level: req.level, goal: req.goal)
    }

    private func localMeal(from req: CreateMealPlanRequest) -> MealPlanResult {
        PlanLocalEngine.buildMeal(dailyKcal: req.dailyKcal, proteinG: req.proteinG, carbsG: req.carbsG,
                                  fatG: req.fatG, fiberG: req.fiberG, mealCount: req.mealCount,
                                  includeSnack: req.includeSnack, dietaryPref: req.dietaryPref,
                                  proteinPrefs: req.proteinPrefs, carbPrefs: req.carbPrefs,
                                  fiberPrefs: req.fiberPrefs, allergens: req.allergens)
    }

    private func cacheWeekly(_ p: WeeklyWorkoutPlan) { persistence.save(p, for: .weeklyPlanCache) }
    private func cachedWeekly() -> WeeklyWorkoutPlan? { persistence.load(WeeklyWorkoutPlan.self, for: .weeklyPlanCache) }
    private func cacheMeal(_ p: MealPlanResult) { persistence.save(p, for: .mealPlanCache) }
    private func cachedMeal() -> MealPlanResult? { persistence.load(MealPlanResult.self, for: .mealPlanCache) }
}
