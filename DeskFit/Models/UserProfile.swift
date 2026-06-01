import Foundation

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var age: Int = 30
    var gender: Gender = .male
    var heightCm: Double = 170
    var weightKg: Double = 70
    var targetWeightKg: Double = 68
    var activity: ActivityLevel = .sedentary
    var goal: Goal = .generalHealth
    var medicalFlags: Set<MedicalFlag> = [.none]
}
