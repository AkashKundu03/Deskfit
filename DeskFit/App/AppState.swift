import SwiftUI

@Observable
final class AppState {
    var profile: UserProfile
    var gutAnswers: GutAnswers
    var report: HealthReport?
    var onboardingComplete: Bool

    /// True when a JWT is present in the Keychain.
    private(set) var isAuthenticated: Bool = KeychainTokenStore.shared.isAuthenticated
    /// Drives the login gate: set true on logout so the router shows AuthView
    /// without discarding the on-device report/profile.
    var requiresAuth: Bool = false
    /// Set when a best-effort backend sync fails; surfaced gently in the UI.
    var syncError: String?

    private let persistence = PersistenceService()

    init() {
        let p = PersistenceService()
        self.profile = p.load(UserProfile.self, for: .userProfile) ?? UserProfile()
        self.gutAnswers = p.load(GutAnswers.self, for: .gutAnswers) ?? GutAnswers()
        self.report = p.load(HealthReport.self, for: .healthReport)
        self.onboardingComplete = p.flag(for: .onboardingComplete)
    }

    func refreshAuthState() {
        isAuthenticated = KeychainTokenStore.shared.isAuthenticated
    }

    /// Logs out: clears the JWT and cached real-user plans, then routes to the
    /// login screen. The user's report/profile stay on-device, and backend data
    /// is never deleted — signing back in reloads everything.
    func signOut() {
        AuthService().logout()
        PersistenceService().clearPlanCaches()
        refreshAuthState()
        requiresAuth = true
    }

    /// Best-effort push of local data to the backend. Never blocks report
    /// generation. On failure it records a friendly message in `syncError`.
    @MainActor
    func syncAll() async {
        guard isAuthenticated else { return }
        syncError = nil
        do {
            try await ProfileSyncService().sync(profile)
            try await GutAnswersSyncService().sync(gutAnswers)
            if let report {
                try await ReportSyncService().sync(report)
                try await EventSyncService().track("assessment_completed")
            }
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't sync right now. Your report is saved on this device."
        }
    }

    /// Called right after a successful social sign-in (before the report exists).
    /// Refreshes auth state and records the event. The actual data push happens
    /// later via syncAll() once the report is generated. Best-effort.
    @MainActor
    func registerSocialLogin() async {
        refreshAuthState()
        try? await EventSyncService().track("social_login_success")
    }

    func generateReport() {
        let bmi   = HealthCalculator.bmi(weightKg: profile.weightKg, heightCm: profile.heightCm)
        let cat   = HealthCalculator.category(for: bmi)
        let bmr   = HealthCalculator.bmr(weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age, gender: profile.gender)
        let tdee  = HealthCalculator.tdee(bmr: bmr, activity: profile.activity)
        let range = HealthCalculator.healthyWeightRange(heightCm: profile.heightCm)
        let cal   = HealthCalculator.calorieTargetRange(tdee: tdee, goal: profile.goal)
        let gut   = GutHealthScorer.score(answers: gutAnswers)
        let age   = GutHealthScorer.gutAge(chronologicalAge: profile.age, score: gut)
        let acts  = RiskEngine.priorityActions(profile: profile, gut: gutAnswers, gutScore: gut)

        self.report = HealthReport(
            bmi: bmi,
            bmiCategory: cat,
            bmr: bmr,
            tdee: tdee,
            healthyWeightLowKg: range.low,
            healthyWeightHighKg: range.high,
            calorieTargetLow: cal.low,
            calorieTargetHigh: cal.high,
            gutScore: gut,
            gutAge: age,
            priorityActions: acts,
            generatedAt: Date()
        )
        self.onboardingComplete = true
        persistAll()
    }

    func resetAssessment() {
        report = nil
        onboardingComplete = false
        profile = UserProfile()
        gutAnswers = GutAnswers()
        persistence.clearAll()
    }

    private func persistAll() {
        persistence.save(profile, for: .userProfile)
        persistence.save(gutAnswers, for: .gutAnswers)
        if let report { persistence.save(report, for: .healthReport) }
        persistence.setFlag(onboardingComplete, for: .onboardingComplete)
    }
}
