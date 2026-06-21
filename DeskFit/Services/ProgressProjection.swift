import Foundation

/// Deterministic, on-device projection of the user's path toward their goal
/// weight. No HealthKit, no health data collection, no AI — derived purely from
/// the assessment, the report's energy numbers, and plan-completion consistency.
struct ProgressProjection {
    let startWeight: Double
    let targetWeight: Double
    let isLoss: Bool
    /// Projected weight at each week index (point 0 = today).
    let points: [Double]
    let weeksToGoal: Int
    let weeklyChangeKg: Double
    let plannedDailyDeficit: Int
    let workoutConsistency: Double   // 0...1
    let mealConsistency: Double      // 0...1
    /// True when consistency is assumed (no plan data yet) rather than measured.
    let consistencyAssumed: Bool
    /// The user's chosen timeline (months) to reach their goal, if set.
    let targetMonths: Int?

    private static let kcalPerKg = 7700.0
    private static let weekCap = 24

    static func make(profile: UserProfile,
                     report: HealthReport?,
                     weeklyPlan: WeeklyWorkoutPlan?,
                     mealPlan: MealPlanResult?) -> ProgressProjection {
        let start = profile.weightKg
        let target = profile.targetWeightKg
        let isLoss = target <= start
        let gap = abs(start - target)

        // Consistency — measured from plans when available, else a gentle default.
        var assumed = false
        let workoutConsistency: Double = {
            if let p = weeklyPlan {
                let total = p.completedCount + p.plannedCount + p.skippedCount
                if total > 0 { return Double(p.completedCount) / Double(total) }
            }
            assumed = true
            return 0.7
        }()
        let mealConsistency: Double = {
            if let m = mealPlan, !m.meals.isEmpty {
                let done = m.meals.filter { $0.status == "completed" }.count
                let acted = m.meals.filter { $0.status != "planned" }.count
                if acted > 0 { return Double(done) / Double(acted) }
            }
            return 0.7
        }()

        // Planned daily energy gap from the report (fallback to a safe estimate).
        let tdee = report?.tdee ?? 0
        let midTarget: Double = {
            guard let r = report, r.calorieTargetHigh > 0 else { return tdee }
            return (r.calorieTargetLow + r.calorieTargetHigh) / 2
        }()
        let rawDailyGap = abs(tdee - midTarget)
        let plannedDailyDeficit = rawDailyGap > 0 ? rawDailyGap : 400  // sensible floor

        // Nutrition drives weight most; training supports it.
        let consistency = max(0.3, min(1.0, mealConsistency * 0.6 + workoutConsistency * 0.4))
        let effectiveDaily = plannedDailyDeficit * consistency
        let weeklyChange = max(0.05, effectiveDaily * 7 / kcalPerKg)

        let weeksToGoal = gap < 0.1 ? 0 : min(weekCap, Int(ceil(gap / weeklyChange)))
        let span = max(weeksToGoal, gap < 0.1 ? 4 : weeksToGoal) // always draw something

        var points: [Double] = []
        for week in 0...max(1, span) {
            let delta = weeklyChange * Double(week)
            let w = isLoss ? max(target, start - delta) : min(target, start + delta)
            points.append(w)
        }

        return ProgressProjection(
            startWeight: start,
            targetWeight: target,
            isLoss: isLoss,
            points: points,
            weeksToGoal: weeksToGoal,
            weeklyChangeKg: weeklyChange,
            plannedDailyDeficit: Int(plannedDailyDeficit.rounded()),
            workoutConsistency: workoutConsistency,
            mealConsistency: mealConsistency,
            consistencyAssumed: assumed,
            targetMonths: gap < 0.1 ? nil : profile.timelineMonths
        )
    }

    /// Compares the user's chosen timeline against the projected pace.
    var timelineNote: String? {
        guard let targetMonths, weeksToGoal > 0 else { return nil }
        let targetWeeks = Double(targetMonths) * 4.33
        if Double(weeksToGoal) <= targetWeeks * 1.1 {
            return "Your \(targetMonths)-month goal looks realistic at this pace."
        }
        return "Your \(targetMonths)-month goal is ambitious — staying consistent will get you closest."
    }

    /// Friendly one-line summary used as the chart subtitle.
    var summary: String {
        if weeksToGoal <= 0 {
            return "You're right around your goal weight — nice."
        }
        let verb = isLoss ? "lose" : "gain"
        let perWeek = String(format: "%.1f", weeklyChangeKg)
        return "At your current pace you'd \(verb) about \(perWeek) kg/week — roughly \(weeksToGoal) weeks to your goal."
    }

    /// The single best next action surfaced under the chart.
    var nextBestAction: String {
        if mealConsistency < 0.6 {
            return "Lock in your meal targets — nutrition moves the needle most."
        }
        if workoutConsistency < 0.6 {
            return "Add one more session this week to keep momentum."
        }
        return "Stay consistent — you're on a sustainable path."
    }
}
