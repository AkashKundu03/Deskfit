import Foundation

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case fatLoss, muscleGain, energy, getActive, generalHealth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fatLoss: return "Fat loss"
        case .muscleGain: return "Muscle gain"
        case .energy: return "Improve energy"
        case .getActive: return "Get active"
        case .generalHealth: return "General health"
        }
    }
}

enum MedicalFlag: String, Codable, CaseIterable, Identifiable {
    case none, diabetes, hypertension, pcos, thyroid, digestive, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .diabetes: return "Diabetes"
        case .hypertension: return "Hypertension"
        case .pcos: return "PCOS / PCOD"
        case .thyroid: return "Thyroid"
        case .digestive: return "Digestive issues"
        case .other: return "Other"
        }
    }
}

enum BowelFrequency: String, Codable, CaseIterable, Identifiable {
    case multipleDay, daily, everyOtherDay, fewPerWeek, rarely
    var id: String { rawValue }
    var label: String {
        switch self {
        case .multipleDay: return "Multiple times a day"
        case .daily: return "Once a day"
        case .everyOtherDay: return "Every other day"
        case .fewPerWeek: return "A few times a week"
        case .rarely: return "Rarely"
        }
    }
}

enum StoolConsistency: String, Codable, CaseIterable, Identifiable {
    case hard, firm, normal, soft, loose
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BloatingFrequency: String, Codable, CaseIterable, Identifiable {
    case never, rarely, sometimes, often, daily
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
