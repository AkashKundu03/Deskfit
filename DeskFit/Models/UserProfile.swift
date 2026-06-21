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
    /// How many months the user wants to reach their target weight in. Local-only
    /// (not synced to the backend) — drives the realistic-pace projection.
    var timelineMonths: Int = 4
}
