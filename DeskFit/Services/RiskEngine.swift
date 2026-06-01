import Foundation

enum RiskEngine {
    static func priorityActions(profile: UserProfile, gut: GutAnswers, gutScore: Int) -> [String] {
        var actions: [String] = []

        if gut.waterLitres < 2.0 {
            actions.append("Aim for 2–2.5 L of water daily to support digestion.")
        }
        if gut.sleepHours < 7 {
            actions.append("Target 7–8 hours of sleep to improve recovery.")
        }
        if gut.bloatingFrequency == .often || gut.bloatingFrequency == .daily {
            actions.append("Add fibre-rich foods gradually and chew thoroughly to ease bloating.")
        }
        if profile.activity == .sedentary {
            actions.append("Take a 5-minute walk every hour to break up sitting.")
        }
        if gutScore < 60 {
            actions.append("Add one fermented food (yogurt, kefir, kimchi) per day.")
        }
        if profile.medicalFlags.contains(.diabetes) || profile.medicalFlags.contains(.hypertension) {
            actions.append("Discuss any major lifestyle change with your doctor first.")
        }

        let fallbacks = [
            "Add a 10-minute morning stretch routine.",
            "Include a colourful vegetable with every meal.",
            "Stand up and breathe deeply every 60 minutes."
        ]
        for f in fallbacks where actions.count < 3 {
            actions.append(f)
        }

        return Array(actions.prefix(3))
    }
}
