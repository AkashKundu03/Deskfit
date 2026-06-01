import Foundation

struct GutAnswers: Codable, Equatable {
    var bowelFrequency: BowelFrequency = .daily
    var stoolConsistency: StoolConsistency = .normal
    var bloatingFrequency: BloatingFrequency = .rarely
    var waterLitres: Double = 2.0
    var sleepHours: Double = 7.0
}
