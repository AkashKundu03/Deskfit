import Foundation

enum GutHealthScorer {
    static func score(answers: GutAnswers) -> Int {
        var score = 0

        switch answers.bowelFrequency {
        case .daily, .multipleDay: score += 30
        case .everyOtherDay:       score += 20
        case .fewPerWeek:          score += 10
        case .rarely:              score += 0
        }

        switch answers.stoolConsistency {
        case .normal:       score += 25
        case .firm, .soft:  score += 18
        case .hard, .loose: score += 8
        }

        switch answers.bloatingFrequency {
        case .never:     score += 20
        case .rarely:    score += 16
        case .sometimes: score += 10
        case .often:     score += 4
        case .daily:     score += 0
        }

        // Water target ~2.5 L
        let waterPts = Int((min(answers.waterLitres, 2.5) / 2.5) * 15)
        score += max(0, waterPts)

        // Sleep target 7–9 h
        let sleepPts: Int
        switch answers.sleepHours {
        case 7...9:           sleepPts = 10
        case 6..<7, 9.01...10: sleepPts = 7
        case 5..<6:           sleepPts = 4
        default:              sleepPts = 2
        }
        score += sleepPts

        return min(100, max(0, score))
    }

    static func gutAge(chronologicalAge: Int, score: Int) -> Int {
        // Educational only — older if low score, younger if high.
        let delta = Double(50 - score) / 5.0   // ~ -10 ... +10
        return max(15, chronologicalAge + Int(delta.rounded()))
    }
}
