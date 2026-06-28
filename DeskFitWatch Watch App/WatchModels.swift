import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Lightweight payloads exchanged with the iPhone over WatchConnectivity. Kept
// deliberately small — the phone is the source of truth; the Watch shows today's
// workout/meals and reports completions + live workout sessions back.
// (Mirror of the iOS-side `WatchSync` shapes so both encode/decode identically.)
// ─────────────────────────────────────────────────────────────────────────────

struct WatchExercise: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
}

struct WatchWorkout: Codable, Equatable {
    let title: String
    let durationMin: Int
    let focusLabel: String
    let exercises: [WatchExercise]
}

struct WatchMeal: Codable, Identifiable, Equatable {
    let id: String
    let slot: String
    let name: String
    let kcal: Int
    let proteinG: Int
    var status: String
}

/// Snapshot the phone pushes to the Watch.
struct WatchSnapshot: Codable, Equatable {
    var date: String
    var workout: WatchWorkout?
    var meals: [WatchMeal]
    var hasWorkoutToday: Bool { workout != nil }
}

/// Actions the Watch sends back to the phone.
enum WatchAction: String, Codable {
    case completeWorkout
    case completeMeal
    case skipMeal
    case checkIn
}

struct WatchActionMessage: Codable {
    let action: WatchAction
    var mealId: String?
    var energy: Int?
    var soreness: Int?
    var workoutMinutes: Int?
    var activeEnergyKcal: Int?
}
