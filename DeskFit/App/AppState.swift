import SwiftUI

@Observable
final class AppState {
    var profile: UserProfile
    var gutAnswers: GutAnswers
    var report: HealthReport?
    var onboardingComplete: Bool

    private let persistence = PersistenceService()

    init() {
        let p = PersistenceService()
        self.profile = p.load(UserProfile.self, for: .userProfile) ?? UserProfile()
        self.gutAnswers = p.load(GutAnswers.self, for: .gutAnswers) ?? GutAnswers()
        self.report = p.load(HealthReport.self, for: .healthReport)
        self.onboardingComplete = p.flag(for: .onboardingComplete)
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
