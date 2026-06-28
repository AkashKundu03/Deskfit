import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — repeating weekly meal template (mirrors the backend /nutrition/weekly
// responses). The plan repeats every week until regenerated; per-meal swaps are
// limited (remainingSwaps / swapLimit).
// ─────────────────────────────────────────────────────────────────────────────

struct MealPortionDTO: Codable, Equatable, Identifiable {
    let id: String
    let foodSlug: String
    let name: String
    let grams: Double
    let kcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
}

struct MealDTO: Codable, Equatable, Identifiable {
    let id: String
    let slot: String           // breakfast | lunch | dinner | snack
    let name: String
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let status: String         // planned | completed | skipped
    let version: Int
    let portions: [MealPortionDTO]
}

struct MealPlanDayDTO: Codable, Equatable, Identifiable {
    let id: String
    let weekday: String        // Mon..Sun
    let meals: [MealDTO]
}

struct WeeklyMealPlanDTO: Codable, Equatable {
    let id: String
    let active: Bool
    let mealCount: Int
    let includeSnack: Bool
    let dietaryPref: String
    let proteinPrefs: [String]
    let carbPrefs: [String]
    let fiberPrefs: [String]
    let allergens: [String]
    let dislikes: [String]
    let dailyKcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let remainingSwaps: Int
    let swapLimit: Int
    let days: [MealPlanDayDTO]

    /// Today's day (by local weekday), falling back to the first day.
    func today() -> MealPlanDayDTO? {
        days.first { $0.weekday == Weekdays.today() } ?? days.first
    }
}

struct FoodCatalogItem: Codable, Equatable, Identifiable {
    let slug: String
    let name: String
    let category: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let fiberPer100g: Double
    let servingGrams: Double
    let servingUnit: String
    let diet: String
    let allergens: [String]
    let source: String
    var id: String { slug }
}

// MARK: - Requests

struct CreateMealTemplateRequest: Encodable {
    let mealCount: Int
    let includeSnack: Bool
    let dietaryPref: String
    let proteinPrefs: [String]
    let carbPrefs: [String]
    let fiberPrefs: [String]
    let allergens: [String]
    let dislikes: [String]
    let dailyKcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let date: String
}

struct RegenerateMealRequest: Encodable {
    let mealId: String
    let date: String
}

struct EditPortionRequest: Encodable {
    let portionId: String
    let grams: Double?
    let foodSlug: String?
}
