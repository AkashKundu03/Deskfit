import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Codable models mirroring the backend deterministic coach engine
// (desk-fit-backend/src/coach/coach.types.ts). Keys match the JSON exactly, so
// no custom CodingKeys are needed. These decode equally from the live backend
// or from the local CoachEngine fallback (demo / offline).
// ─────────────────────────────────────────────────────────────────────────────

struct NutritionSafety: Codable, Equatable {
    let isAggressive: Bool
    let message: String?
    let saferTimelineMonths: Int?
}

struct HowCalculated: Codable, Equatable {
    let bmr: Double
    let tdee: Double
    let activityMultiplier: Double
    let method: String
}

struct NutritionTargets: Codable, Equatable {
    let goal: String
    let goalLabel: String
    let dailyBurnKcal: Int
    let foodTargetKcal: Int
    let deficitKcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let coachExplanation: String
    let safety: NutritionSafety
    let howCalculated: HowCalculated
}

struct CoachExerciseItem: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let category: String
    let detail: String
    let rest: String
    let cue: String
    let lowImpactAlternative: String?
}

struct GeneratedWorkout: Codable, Equatable {
    let id: String
    let title: String
    let focus: String
    let focusLabel: String
    let durationMin: Int
    let location: String
    let equipment: [String]
    let estimatedCalories: Int
    let warmup: [CoachExerciseItem]
    let main: [CoachExerciseItem]
    let coachNote: String
    var completed: Bool
}

struct WeeklyDay: Codable, Equatable, Identifiable {
    let weekday: String
    let focusLabel: String
    let status: String   // planned | completed | missed | today | rest
    var id: String { weekday }
}

struct WeeklyPlan: Codable, Equatable {
    let days: [WeeklyDay]
    let completedCount: Int
    let plannedCount: Int
    let missedCount: Int
}

struct CoachOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
}

struct ConsistencyCoach: Codable, Equatable {
    let missedDay: String?
    let message: String
    let options: [CoachOption]
}

struct TodayResponse: Codable, Equatable {
    let greeting: String
    let goalContext: String
    let focusLabel: String
    let coachMessage: String
    let nutrition: NutritionTargets
    var workout: GeneratedWorkout      // var: Today screen can mark it completed
    var weekly: WeeklyPlan             // var: "Adjust this week" replaces it
    let consistency: ConsistencyCoach
    let isDemo: Bool
}

// MARK: - Request bodies (Encodable, match backend DTOs)

/// Matches backend CoachProfileDto.
struct CoachProfileRequest: Encodable {
    let name: String?
    let age: Int
    let gender: String
    let heightCm: Double
    let weightKg: Double
    let targetWeightKg: Double
    let activityLevel: String
    let goal: String
    let timelineMonths: Int?
    let missedWeekday: String?

    init(profile: UserProfile, timelineMonths: Int?, missedWeekday: String? = nil) {
        self.name = profile.name.isEmpty ? nil : profile.name
        self.age = profile.age
        self.gender = profile.gender.rawValue
        self.heightCm = profile.heightCm
        self.weightKg = profile.weightKg
        self.targetWeightKg = profile.targetWeightKg
        self.activityLevel = profile.activity.rawValue
        self.goal = CoachGoal.from(profile.goal).rawValue
        self.timelineMonths = timelineMonths
        self.missedWeekday = missedWeekday
    }
}

/// Matches backend GenerateWorkoutDto.
struct GenerateWorkoutRequest: Encodable {
    let location: String
    let durationMin: Int
    let equipment: [String]
    let focus: String
    let level: String
    let title: String?
}

/// Matches backend AdjustWeekDto.
struct AdjustWeekRequest: Encodable {
    let strategy: String
    let missedWeekday: String?
}

struct AdjustWeekResponse: Codable, Equatable {
    let weekly: WeeklyPlan
    let message: String
}

struct WorkoutActionResponse: Codable, Equatable {
    let workout: GeneratedWorkout
    let coachMessage: String
    let options: [CoachOption]?
}

// MARK: - Goal mapping (iOS Goal -> backend coach goal)

/// The backend coach engine only models three goals; the richer iOS `Goal`
/// enum maps onto them (energy/getActive/generalHealth → maintenance).
enum CoachGoal: String {
    case fatLoss, muscleGain, maintenance

    static func from(_ goal: Goal) -> CoachGoal {
        switch goal {
        case .fatLoss: return .fatLoss
        case .muscleGain: return .muscleGain
        case .energy, .getActive, .generalHealth: return .maintenance
        }
    }
}
