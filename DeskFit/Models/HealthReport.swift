import Foundation

struct HealthReport: Codable, Equatable {
    var bmi: Double
    var bmiCategory: String
    var bmr: Double
    var tdee: Double
    var healthyWeightLowKg: Double
    var healthyWeightHighKg: Double
    var calorieTargetLow: Double
    var calorieTargetHigh: Double
    var gutScore: Int
    var gutAge: Int
    var priorityActions: [String]
    var generatedAt: Date

    static let disclaimer = "This is educational wellness guidance, not medical advice. Please consult a qualified doctor or dietitian for medical conditions."
}
