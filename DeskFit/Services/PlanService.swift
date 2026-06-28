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
           // Send the user's LOCAL date so the backend resolves THIS week (and
           // auto-continues a stale plan) instead of leaking last week's sessions.
           let p = try? await client.get("workouts/weekly-plan/current?date=\(Weekdays.todayISO())",
                                         authorized: true, as: WeeklyWorkoutPlan.self) {
            cacheWeekly(p)
            return p
        }
        return cachedWeekly()
    }

    /// Preview "Fix my remaining week" without persisting (for the confirm sheet).
    func previewFixWeek(unavailableDays: [String] = []) async -> FixWeekResult? {
        guard isAuthed else {
            // Local/guest: compute a client-side preview from the cached plan.
            guard let plan = cachedWeekly() else { return nil }
            return PlanLocalEngine.fixWeekPreview(plan, unavailableDays: unavailableDays)
        }
        return try? await client.post("workouts/fix-week/preview",
                                      body: FixWeekRequest(date: Weekdays.todayISO(), unavailableDays: unavailableDays),
                                      authorized: true, as: FixWeekResult.self)
    }

    /// Apply "Fix my remaining week"; returns the updated plan.
    func applyFixWeek(unavailableDays: [String] = []) async -> WeeklyWorkoutPlan? {
        if AppConfig.useDemoData {
            guard let cur = Self.demoWeekly else { return nil }
            let p = PlanLocalEngine.rebalance(cur); Self.demoWeekly = p; return p
        }
        if isAuthed,
           let res = try? await client.post("workouts/fix-week/apply",
                                            body: FixWeekRequest(date: Weekdays.todayISO(), unavailableDays: unavailableDays),
                                            authorized: true, as: FixWeekApplyResponse.self) {
            cacheWeekly(res.plan)
            return res.plan
        }
        guard let cur = cachedWeekly() else { return nil }
        let p = PlanLocalEngine.rebalance(cur); cacheWeekly(p); return p
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

    /// Regenerate one day's workout without touching the rest of the week.
    func regenerateSession(_ sessionId: String) async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/session/regenerate",
                           body: SessionActionRequest(sessionId: sessionId),
                           local: { PlanLocalEngine.regenerate($0, sessionId: sessionId) })
    }

    func rebalanceWeek() async -> WeeklyWorkoutPlan? {
        await mutateWeekly(path: "workouts/rebalance-week",
                           body: EmptyBody(),
                           local: { PlanLocalEngine.rebalance($0) })
    }

    // MARK: - Standalone (today-only) workout

    private static var demoStandalone: StandaloneWorkout?

    /// Generate + persist a one-off workout for today. Authed → backend; demo →
    /// in-memory; guest/offline → local engine + cache.
    func saveStandalone(_ req: StandaloneWorkoutRequest) async -> StandaloneWorkout {
        let local = {
            PlanLocalEngine.buildStandalone(location: req.location, durationMin: req.durationMin,
                                            equipment: req.equipment, focus: req.focus, level: req.level,
                                            title: req.title, date: req.date)
        }
        if AppConfig.useDemoData { let p = local(); Self.demoStandalone = p; return p }
        if isAuthed,
           let p = try? await client.post("workouts/standalone", body: req, authorized: true, as: StandaloneWorkout.self) {
            cacheStandalone(p); return p
        }
        let p = local(); cacheStandalone(p); return p
    }

    /// Today's standalone workout, if one was generated today.
    func currentStandalone() async -> StandaloneWorkout? {
        if AppConfig.useDemoData { return Self.demoStandalone }
        if isAuthed,
           let p = try? await client.get("workouts/standalone/today?date=\(Weekdays.todayISO())",
                                         authorized: true, as: StandaloneWorkout.self) {
            cacheStandalone(p); return p
        }
        // Fall back to cache, but only if it's actually for today.
        let cached = cachedStandalone()
        return cached?.date == Weekdays.todayISO() ? cached : nil
    }

    func completeStandalone(_ id: String) async -> StandaloneWorkout? {
        await mutateStandalone(path: "workouts/standalone/complete", id: id, status: "completed")
    }

    func skipStandalone(_ id: String) async -> StandaloneWorkout? {
        await mutateStandalone(path: "workouts/standalone/skip", id: id, status: "skipped")
    }

    private func mutateStandalone(path: String, id: String, status: String) async -> StandaloneWorkout? {
        if AppConfig.useDemoData {
            guard let c = Self.demoStandalone else { return nil }
            let p = PlanLocalEngine.setStandaloneStatus(c, status: status); Self.demoStandalone = p; return p
        }
        if isAuthed,
           let p = try? await client.post(path, body: StandaloneActionRequest(id: id), authorized: true, as: StandaloneWorkout.self) {
            cacheStandalone(p); return p
        }
        guard let c = cachedStandalone() else { return nil }
        let p = PlanLocalEngine.setStandaloneStatus(c, status: status); cacheStandalone(p); return p
    }

    private func cacheStandalone(_ p: StandaloneWorkout) { persistence.save(p, for: .standaloneCache) }
    private func cachedStandalone() -> StandaloneWorkout? { persistence.load(StandaloneWorkout.self, for: .standaloneCache) }

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
