import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 planner contract — Codable models mirroring the backend
// (desk-fit-backend/src/coach/planner.types.ts). Keys match the JSON exactly.
// These decode from the live authenticated backend OR the local PlanLocalEngine
// (demo / offline), so the planner UI is always populated.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Weekly workout plan

struct WeeklySession: Codable, Equatable, Identifiable {
    let id: String
    var weekday: String          // "Mon"
    var date: String             // yyyy-mm-dd
    var title: String
    let focus: String
    let focusLabel: String
    var durationMin: Int
    let location: String
    let equipment: [String]
    var estimatedCalories: Int
    var warmup: [CoachExerciseItem]
    var exercises: [CoachExerciseItem]
    var coachNote: String
    var status: String           // planned | completed | skipped | rescheduled
}

struct WeeklyWorkoutPlan: Codable, Equatable {
    let id: String
    let weekStartDate: String
    var selectedDays: [String]
    let goal: String?
    let level: String?
    let location: String?
    var sessions: [WeeklySession]
    var completedCount: Int
    var plannedCount: Int
    var skippedCount: Int
}

// MARK: - Meal target plan

struct MealTarget: Codable, Equatable, Identifiable {
    let id: String
    let slot: String             // breakfast | lunch | dinner | snack
    let name: String
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let suggestions: [String]
    let coachNote: String
    var status: String           // planned | completed | skipped
}

struct MealPlanResult: Codable, Equatable {
    let id: String
    let mealCount: Int
    let dietaryPref: String
    let proteinPrefs: [String]
    let carbPrefs: [String]
    let fiberPrefs: [String]
    let allergens: [String]
    let dailyKcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    var meals: [MealTarget]
    let coachNote: String
}

// MARK: - Request bodies (match backend DTOs)

struct CreateWeeklyPlanRequest: Encodable {
    let selectedDays: [String]
    let location: String
    let durationMin: Int
    let equipment: [String]
    let level: String
    let goal: String
}

struct SessionActionRequest: Encodable { let sessionId: String }

// MARK: - Standalone (today-only) workout

/// A persisted "today only" workout (mirrors the backend StandaloneWorkout).
struct StandaloneWorkout: Codable, Equatable, Identifiable {
    let id: String
    let date: String
    var title: String
    let focus: String
    let focusLabel: String
    var durationMin: Int
    let location: String
    let equipment: [String]
    var estimatedCalories: Int
    var warmup: [CoachExerciseItem]
    var main: [CoachExerciseItem]
    var coachNote: String
    var status: String          // planned | completed | skipped
}

struct StandaloneWorkoutRequest: Encodable {
    let location: String
    let durationMin: Int
    let equipment: [String]
    let focus: String
    let level: String
    let title: String?
    let date: String
}

struct StandaloneActionRequest: Encodable { let id: String }

struct RescheduleSessionRequest: Encodable {
    let sessionId: String
    let toWeekday: String
}

struct CreateMealPlanRequest: Encodable {
    let mealCount: Int
    let includeSnack: Bool
    let dietaryPref: String
    let proteinPrefs: [String]
    let carbPrefs: [String]
    let fiberPrefs: [String]
    let allergens: [String]
    let dailyKcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
}

struct MealActionRequest: Encodable { let mealId: String }

struct EmptyBody: Encodable {}

// MARK: - Fix my remaining week

struct FixWeekRequest: Encodable {
    let date: String
    let unavailableDays: [String]
}

struct FixWeekChange: Codable, Equatable, Identifiable {
    let sessionId: String
    let title: String
    let from: String
    let to: String
    var id: String { sessionId }
}

struct FixWeekBefore: Codable, Equatable {
    let sessionId: String
    let weekday: String
    let status: String
}

/// Mirrors the backend `FixWeekResult` — the before/after audit of a fix.
struct FixWeekResult: Codable, Equatable {
    let before: [FixWeekBefore]
    let after: [WeeklySession]
    let changes: [FixWeekChange]
    let feasible: Bool
    let fallback: String?      // "shorten" | "skip" | "chooseMoreDays"
    let reason: String?
}

/// Response shape of `POST workouts/fix-week/apply`.
struct FixWeekApplyResponse: Codable, Equatable {
    let plan: WeeklyWorkoutPlan
    let result: FixWeekResult
}

// MARK: - Weekday helpers (shared by planner UI + local engine)

enum Weekdays {
    static let order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let full: [String: String] = [
        "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday",
        "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday",
    ]
    static func index(_ wd: String) -> Int { order.firstIndex(of: wd) ?? 0 }
    static func today() -> String {
        let map = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return map[Calendar.current.component(.weekday, from: Date()) - 1]
    }

    /// The user's LOCAL today as `yyyy-MM-dd` — the source of truth for matching a
    /// session to "today" by DATE (not just weekday) and for telling the backend
    /// which calendar week to resolve. Avoids the "last week's Monday" bug.
    static func todayISO(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Meal preference option types (drive the Plan Meals flow)

enum MealCountOption: Int, PlannerOption {
    case two = 2, three = 3, four = 4
    var id: Int { rawValue }
    var label: String { "\(rawValue) meals" }
}

enum DietaryPref: String, PlannerOption {
    case vegetarian, eggitarian, nonVegetarian, vegan, mixed
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .eggitarian: return "Eggitarian"
        case .nonVegetarian: return "Non-veg"
        case .vegan: return "Vegan"
        case .mixed: return "Mixed"
        }
    }
}

enum ProteinPref: String, PlannerOption {
    case paneer, tofu, fish, chicken, eggs, dal, whey
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .paneer: return "Paneer / tofu"
        case .tofu: return "Tofu"
        case .fish: return "Fish"
        case .chicken: return "Chicken"
        case .eggs: return "Eggs"
        case .dal: return "Dal / beans"
        case .whey: return "Whey protein"
        }
    }
}

enum CarbPref: String, PlannerOption {
    case rice, roti, oats, potato, quinoa, mixed
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .rice: return "Rice"; case .roti: return "Roti"; case .oats: return "Oats"
        case .potato: return "Potato"; case .quinoa: return "Quinoa"; case .mixed: return "Mixed"
        }
    }
}

enum FiberPref: String, PlannerOption {
    case vegetables, fruits, salad, legumes
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .vegetables: return "Vegetables"; case .fruits: return "Fruits"
        case .salad: return "Salad"; case .legumes: return "Legumes"
        }
    }
}

enum AllergenPref: String, PlannerOption {
    case lactose, gluten, nuts, none
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .lactose: return "Lactose"; case .gluten: return "Gluten"
        case .nuts: return "Nuts"; case .none: return "None"
        }
    }
}
