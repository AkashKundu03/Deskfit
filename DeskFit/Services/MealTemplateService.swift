import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 client for the repeating weekly meal template (/nutrition/weekly/*).
// Cloud-synced & premium: requires an Apple account. Guests are gated to sign in
// (handled by the caller). Authenticated results are cached for offline reload.
// ─────────────────────────────────────────────────────────────────────────────

struct MealTemplateService {
    private let client = APIClient()
    private let persistence = PersistenceService()
    private let tokenStore = KeychainTokenStore.shared

    private var isAuthed: Bool { tokenStore.isAuthenticated }

    /// Create (or replace) the user's repeating weekly meal template.
    func create(_ req: CreateMealTemplateRequest) async -> WeeklyMealPlanDTO? {
        guard isAuthed,
              let p = try? await client.post("nutrition/weekly/plan", body: req,
                                             authorized: true, as: WeeklyMealPlanDTO.self)
        else { return nil }
        cache(p)
        return p
    }

    /// The active weekly meal template, or nil if none / not signed in.
    func current() async -> WeeklyMealPlanDTO? {
        guard isAuthed else { return nil }
        if let p = try? await client.get("nutrition/weekly/current?date=\(Weekdays.todayISO())",
                                         authorized: true, as: WeeklyMealPlanDTO.self) {
            cache(p)
            return p
        }
        return cached()
    }

    func regenerateMeal(_ mealId: String) async throws -> WeeklyMealPlanDTO {
        let p = try await client.post("nutrition/weekly/meal/regenerate",
                                      body: RegenerateMealRequest(mealId: mealId, date: Weekdays.todayISO()),
                                      authorized: true, as: WeeklyMealPlanDTO.self)
        cache(p)
        return p
    }

    func completeMeal(_ mealId: String) async -> WeeklyMealPlanDTO? {
        try? await mutate("nutrition/weekly/meal/complete", MealActionRequest(mealId: mealId))
    }

    func skipMeal(_ mealId: String) async -> WeeklyMealPlanDTO? {
        try? await mutate("nutrition/weekly/meal/skip", MealActionRequest(mealId: mealId))
    }

    func editPortion(portionId: String, grams: Double?, foodSlug: String?) async -> WeeklyMealPlanDTO? {
        try? await mutate("nutrition/weekly/portion",
                          EditPortionRequest(portionId: portionId, grams: grams, foodSlug: foodSlug))
    }

    func catalog() async -> [FoodCatalogItem] {
        guard isAuthed,
              let items = try? await client.get("nutrition/weekly/food-catalog",
                                                authorized: true, as: [FoodCatalogItem].self)
        else { return [] }
        return items
    }

    // MARK: - Helpers

    private func mutate<B: Encodable>(_ path: String, _ body: B) async throws -> WeeklyMealPlanDTO {
        let p = try await client.post(path, body: body, authorized: true, as: WeeklyMealPlanDTO.self)
        cache(p)
        return p
    }

    private func cache(_ p: WeeklyMealPlanDTO) { persistence.save(p, for: .weeklyMealCache) }
    private func cached() -> WeeklyMealPlanDTO? { persistence.load(WeeklyMealPlanDTO.self, for: .weeklyMealCache) }
}
