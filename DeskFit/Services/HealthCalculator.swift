import Foundation

enum HealthCalculator {
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0 else { return 0 }
        return weightKg / (m * m)
    }

    static func category(for bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case ..<25:   return "Normal"
        case ..<30:   return "Overweight"
        default:      return "Obese"
        }
    }

    // Mifflin-St Jeor
    static func bmr(weightKg: Double, heightCm: Double, age: Int, gender: Gender) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch gender {
        case .male:   return base + 5
        case .female: return base - 161
        case .other:  return base - 78
        }
    }

    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    static func healthyWeightRange(heightCm: Double) -> (low: Double, high: Double) {
        let m = heightCm / 100
        return (18.5 * m * m, 24.9 * m * m)
    }

    static func calorieTargetRange(tdee: Double, goal: Goal) -> (low: Double, high: Double) {
        switch goal {
        case .fatLoss:     return (tdee - 500, tdee - 300)
        case .muscleGain:  return (tdee + 200, tdee + 400)
        case .energy,
             .getActive,
             .generalHealth: return (tdee - 100, tdee + 100)
        }
    }
}
