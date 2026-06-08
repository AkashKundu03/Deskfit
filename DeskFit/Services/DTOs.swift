import Foundation

// MARK: - Auth

struct AuthRequest: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let accessToken: String
}

/// Matches backend AppleAuthDto.
struct AppleAuthRequest: Encodable {
    let identityToken: String
    let email: String?
    let fullName: String?
}

/// Matches backend GoogleAuthDto.
struct GoogleAuthRequest: Encodable {
    let idToken: String
}

// MARK: - Profile

/// Matches backend UpdateProfileDto exactly. Optional fields with nil values
/// are omitted by the encoder, so we never send keys the backend rejects.
struct ProfileSyncDTO: Encodable {
    let name: String?
    let age: Int?
    let gender: String?
    let heightCm: Double?
    let weightKg: Double?
    let targetWeightKg: Double?
    let activityLevel: String?
    let goal: String?
    let medicalFlags: [String: Bool]?

    init(profile: UserProfile) {
        name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profile.name
        age = profile.age
        gender = profile.gender.rawValue
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        targetWeightKg = profile.targetWeightKg
        activityLevel = profile.activity.rawValue           // iOS `activity` -> backend `activityLevel`
        goal = profile.goal.rawValue
        // Set<MedicalFlag> -> dictionary object expected by backend (@IsObject).
        medicalFlags = Dictionary(uniqueKeysWithValues: profile.medicalFlags.map { ($0.rawValue, true) })
    }
}

// MARK: - Gut answers

/// Matches backend UpdateGutAnswersDto exactly.
struct GutAnswersSyncDTO: Encodable {
    let bowelFrequency: String?
    let stoolConsistency: String?
    let bloatingFrequency: String?
    let waterIntake: Double?
    let sleepHours: Double?

    init(gut: GutAnswers) {
        bowelFrequency = gut.bowelFrequency.rawValue
        stoolConsistency = gut.stoolConsistency.rawValue
        bloatingFrequency = gut.bloatingFrequency.rawValue
        waterIntake = gut.waterLitres                       // iOS `waterLitres` -> backend `waterIntake`
        sleepHours = gut.sleepHours
    }
}

// MARK: - Report

/// Matches backend UpdateReportDto exactly. `generatedAt` is intentionally not
/// sent because the backend DTO does not accept it (forbidNonWhitelisted).
struct ReportSyncDTO: Encodable {
    let bmi: Double?
    let bmiCategory: String?
    let bmr: Double?
    let tdee: Double?
    let healthyWeightMin: Double?
    let healthyWeightMax: Double?
    let targetCaloriesMin: Double?
    let targetCaloriesMax: Double?
    let gutHealthScore: Double?
    let educationalGutAge: Int?
    let priorityActions: [String]?
    let riskSignals: [String]?

    init(report: HealthReport) {
        bmi = report.bmi
        bmiCategory = report.bmiCategory
        bmr = report.bmr
        tdee = report.tdee
        healthyWeightMin = report.healthyWeightLowKg        // iOS `healthyWeightLowKg` -> `healthyWeightMin`
        healthyWeightMax = report.healthyWeightHighKg       // iOS `healthyWeightHighKg` -> `healthyWeightMax`
        targetCaloriesMin = report.calorieTargetLow         // iOS `calorieTargetLow` -> `targetCaloriesMin`
        targetCaloriesMax = report.calorieTargetHigh        // iOS `calorieTargetHigh` -> `targetCaloriesMax`
        gutHealthScore = Double(report.gutScore)            // iOS `gutScore` (Int) -> `gutHealthScore` (Double)
        educationalGutAge = report.gutAge                   // iOS `gutAge` -> `educationalGutAge`
        priorityActions = report.priorityActions
        riskSignals = nil
    }
}

// MARK: - Events

/// Matches backend CreateEventDto exactly.
struct EventSyncDTO: Encodable {
    let eventName: String
    let metadata: [String: String]?
}
