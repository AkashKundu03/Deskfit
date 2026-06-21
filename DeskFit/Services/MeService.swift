import Foundation

// MARK: - Backend decodables (GET /me, GET /me/assessment)

/// Mirrors the backend UserProfile row. All optional because a freshly-created
/// account has no profile yet.
struct BackendProfile: Decodable {
    let name: String?
    let age: Int?
    let gender: String?
    let heightCm: Double?
    let weightKg: Double?
    let targetWeightKg: Double?
    let activityLevel: String?
    let goal: String?
    let medicalFlags: [String: Bool]?
}

struct BackendGutAnswers: Decodable {
    let bowelFrequency: String?
    let stoolConsistency: String?
    let bloatingFrequency: String?
    let waterIntake: Double?
    let sleepHours: Double?
}

struct BackendReport: Decodable {
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
}

/// Aggregate account snapshot from GET /me.
struct MeResponse: Decodable {
    let id: String
    let email: String
    let authProvider: String
    let profile: BackendProfile?
    let gutAnswers: BackendGutAnswers?
    let report: BackendReport?
    let hasAssessment: Bool
}

// MARK: - Upload (PUT /me/assessment)

/// Combined assessment upload — matches backend UpdateAssessmentDto. Reuses the
/// existing per-section sync DTOs so field mapping stays in one place.
struct AssessmentUploadDTO: Encodable {
    let profile: ProfileSyncDTO?
    let gutAnswers: GutAnswersSyncDTO?
    let report: ReportSyncDTO?
}

/// Reads/writes the authenticated user's account snapshot and combined
/// assessment. Used on launch and after Apple sign-in to decide whether to skip
/// the questionnaire, and to push a guest's local assessment after upgrade.
struct MeService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchMe() async throws -> MeResponse {
        try await client.get("me", authorized: true, as: MeResponse.self)
    }

    /// Push the full local assessment to the signed-in account in one call.
    func uploadAssessment(profile: UserProfile, gut: GutAnswers, report: HealthReport?) async throws {
        let body = AssessmentUploadDTO(
            profile: ProfileSyncDTO(profile: profile),
            gutAnswers: GutAnswersSyncDTO(gut: gut),
            report: report.map { ReportSyncDTO(report: $0) }
        )
        try await client.put("me/assessment", body: body, authorized: true)
    }
}

// MARK: - Mapping backend → local models

extension BackendProfile {
    func toUserProfile() -> UserProfile {
        var p = UserProfile()
        if let name { p.name = name }
        if let age { p.age = age }
        if let gender, let g = Gender(rawValue: gender) { p.gender = g }
        if let heightCm { p.heightCm = heightCm }
        if let weightKg { p.weightKg = weightKg }
        if let targetWeightKg { p.targetWeightKg = targetWeightKg }
        if let activityLevel, let a = ActivityLevel(rawValue: activityLevel) { p.activity = a }
        if let goal, let g = Goal(rawValue: goal) { p.goal = g }
        if let medicalFlags {
            let flags = medicalFlags.filter { $0.value }
                .compactMap { MedicalFlag(rawValue: $0.key) }
            if !flags.isEmpty { p.medicalFlags = Set(flags) }
        }
        return p
    }
}

extension BackendGutAnswers {
    func toGutAnswers() -> GutAnswers {
        var g = GutAnswers()
        if let bowelFrequency, let v = BowelFrequency(rawValue: bowelFrequency) { g.bowelFrequency = v }
        if let stoolConsistency, let v = StoolConsistency(rawValue: stoolConsistency) { g.stoolConsistency = v }
        if let bloatingFrequency, let v = BloatingFrequency(rawValue: bloatingFrequency) { g.bloatingFrequency = v }
        if let waterIntake { g.waterLitres = waterIntake }
        if let sleepHours { g.sleepHours = sleepHours }
        return g
    }
}

extension BackendReport {
    /// Builds a local HealthReport. Returns nil if the core energy numbers are
    /// missing (the backend never generated one).
    func toHealthReport() -> HealthReport? {
        guard let bmi, let bmr, let tdee else { return nil }
        return HealthReport(
            bmi: bmi,
            bmiCategory: bmiCategory ?? "",
            bmr: bmr,
            tdee: tdee,
            healthyWeightLowKg: healthyWeightMin ?? 0,
            healthyWeightHighKg: healthyWeightMax ?? 0,
            calorieTargetLow: targetCaloriesMin ?? 0,
            calorieTargetHigh: targetCaloriesMax ?? 0,
            gutScore: Int((gutHealthScore ?? 0).rounded()),
            gutAge: educationalGutAge ?? 0,
            priorityActions: priorityActions ?? [],
            generatedAt: Date()
        )
    }
}
