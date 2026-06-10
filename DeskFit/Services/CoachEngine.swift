import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Local, deterministic mirror of the backend coach engine. Used for demo mode
// and as an offline fallback so the premium Today/Nutrition/Workout UI is always
// populated — never blank, never dependent on the production server.
//
// The math mirrors desk-fit-backend/src/coach. Keep the two in rough sync; the
// backend remains the source of truth when reachable.
// ─────────────────────────────────────────────────────────────────────────────

enum CoachEngine {

    // MARK: - Tunables (mirror nutrition-rules.ts)
    private static let kcalPerKgFat = 7700.0
    private static let weeksPerMonth = 4.345
    private static let proteinPerKg: [CoachGoal: Double] = [.fatLoss: 1.8, .muscleGain: 2.0, .maintenance: 1.6]
    private static let fatPerKg = 0.8
    private static let muscleSurplus = 300.0

    private static func minFood(_ gender: Gender) -> Double {
        switch gender { case .male: return 1500; case .female: return 1200; case .other: return 1400 }
    }

    // MARK: - Nutrition

    static func nutrition(profile: UserProfile, timelineMonths: Int?) -> NutritionTargets {
        let goal = CoachGoal.from(profile.goal)
        let bmr = HealthCalculator.bmr(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                       age: profile.age, gender: profile.gender)
        let tdee = HealthCalculator.tdee(bmr: bmr, activity: profile.activity)
        let dailyBurn = Int(tdee.rounded())
        let floorFood = max(minFood(profile.gender), bmr * 0.9)

        var foodTarget = Double(dailyBurn)
        var deficit = 0.0
        var aggressive = false
        var message: String? = nil
        var safer: Int? = nil

        switch goal {
        case .fatLoss:
            let kgToLose = max(0, profile.weightKg - profile.targetWeightKg)
            let months = Double((timelineMonths ?? 4) > 0 ? (timelineMonths ?? 4) : 4)
            let weeks = max(1, months * weeksPerMonth)
            let desiredWeeklyKg = kgToLose / weeks
            let desiredDeficit = desiredWeeklyKg * kcalPerKgFat / 7

            let safeWeeklyKg = min(0.0075 * profile.weightKg, 1.0)
            let maxByRate = safeWeeklyKg * kcalPerKgFat / 7
            let maxByFloor = tdee - floorFood
            let maxByFraction = tdee * 0.25
            let allowed = max(0, min(desiredDeficit, maxByRate, maxByFloor, maxByFraction))

            aggressive = desiredDeficit > allowed + 30
            deficit = allowed.rounded()
            foodTarget = (tdee - allowed).rounded()

            let achievableWeeklyKg = allowed * 7 / kcalPerKgFat
            if aggressive && achievableWeeklyKg > 0 {
                safer = Int(ceil(kgToLose / achievableWeeklyKg / weeksPerMonth))
                message = "This goal may be too aggressive to do safely. A more sustainable timeline would be around \(safer!) months — your plan is set to that safer pace so you keep your energy and muscle."
            }
        case .muscleGain:
            deficit = -muscleSurplus
            foodTarget = (tdee + muscleSurplus).rounded()
        case .maintenance:
            deficit = 0
            foodTarget = Double(dailyBurn)
        }

        if foodTarget < floorFood { foodTarget = floorFood; deficit = (tdee - foodTarget).rounded() }

        let proteinG = Int((proteinPerKg[goal]! * profile.weightKg).rounded())
        let fatG = Int((fatPerKg * profile.weightKg).rounded())
        let carbsG = max(0, Int(((foodTarget - Double(proteinG * 4) - Double(fatG * 9)) / 4).rounded()))
        let fiberG = max(25, Int((foodTarget / 1000 * 14).rounded()))

        return NutritionTargets(
            goal: goal.rawValue,
            goalLabel: goalLabel(goal),
            dailyBurnKcal: dailyBurn,
            foodTargetKcal: Int(foodTarget),
            deficitKcal: Int(deficit),
            proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG,
            coachExplanation: coachExplanation(goal),
            safety: NutritionSafety(isAggressive: aggressive, message: message, saferTimelineMonths: safer),
            howCalculated: HowCalculated(bmr: bmr.rounded(), tdee: Double(dailyBurn),
                                         activityMultiplier: profile.activity.multiplier,
                                         method: "Mifflin–St Jeor BMR × activity, with sustainable deficit guardrails")
        )
    }

    // MARK: - Workouts (compact local library, enough for demo/fallback)

    static func generate(focus: String, durationMin: Int, location: String,
                         equipment: [String], level: String, title: String? = nil) -> GeneratedWorkout {
        let warmup = [CoachExerciseItem(id: "ex_mob_worlds_greatest", name: "World's greatest stretch",
                                        category: "mobility", detail: "4 min", rest: "No rest",
                                        cue: "Open up everything sitting locks down.", lowImpactAlternative: nil)]
        let library = localMain(for: focus)
        let count = min(max(3, durationMin / 8), library.count)
        let main = Array(library.prefix(count))
        let avgPerMin = focus == "mobility" ? 3.0 : focus == "cardio" ? 9.0 : 6.0
        return GeneratedWorkout(
            id: "w_\(focus)_\(durationMin)_\(location)",
            title: title ?? "\(durationMin)-minute \(displayLocation(location)) \(focusLabel(focus).lowercased())",
            focus: focus, focusLabel: focusLabel(focus),
            durationMin: durationMin, location: location, equipment: equipment,
            estimatedCalories: Int((avgPerMin * Double(durationMin)).rounded()),
            warmup: warmup, main: main, coachNote: coachNote(focus, durationMin), completed: false)
    }

    static func shorter(_ w: GeneratedWorkout) -> GeneratedWorkout {
        let short = max(10, w.durationMin / 2)
        var g = generate(focus: w.focus, durationMin: short, location: w.location,
                         equipment: w.equipment, level: "beginner",
                         title: "Shorter \(w.focusLabel.lowercased()) (\(short) min)")
        g.completed = false
        return g
    }

    // MARK: - Weekly plan

    static func weekly(missedWeekday: String?) -> WeeklyPlan {
        let order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let plan: [(String, String)] = [
            ("Mon", "Fat-loss day"), ("Tue", "Recovery day"), ("Wed", "Strength day"),
            ("Thu", "Rest"), ("Fri", "Cardio day"), ("Sat", "Balanced day"), ("Sun", "Rest")
        ]
        let today = todayWeekday()
        let todayIdx = order.firstIndex(of: today) ?? 0
        let days = plan.map { (wd, label) -> WeeklyDay in
            let idx = order.firstIndex(of: wd) ?? 0
            let status: String
            if label == "Rest" { status = "rest" }
            else if wd == missedWeekday { status = "missed" }
            else if wd == today { status = "today" }
            else if idx < todayIdx { status = "completed" }
            else { status = "planned" }
            return WeeklyDay(weekday: wd, focusLabel: label, status: status)
        }
        return WeeklyPlan(
            days: days,
            completedCount: days.filter { $0.status == "completed" }.count,
            plannedCount: days.filter { $0.status == "planned" || $0.status == "today" }.count,
            missedCount: days.filter { $0.status == "missed" }.count)
    }

    // MARK: - Today

    static func today(profile: UserProfile, timelineMonths: Int?, missedWeekday: String?, isDemo: Bool) -> TodayResponse {
        let nutrition = nutrition(profile: profile, timelineMonths: timelineMonths)
        let focus = focusForToday()
        let goal = CoachGoal.from(profile.goal)
        let location = goal == .muscleGain ? "gym" : (focus == "mobility" ? "office" : "home")
        let equipment = goal == .muscleGain ? ["dumbbells", "barbell", "bench"] : ["bodyweight"]
        let duration = focus == "mobility" ? 15 : (goal == .muscleGain ? 45 : 25)
        let level = profile.activity == .sedentary || profile.activity == .light ? "beginner"
                  : profile.activity == .moderate ? "intermediate" : "advanced"
        let workout = generate(focus: focus, durationMin: duration, location: location, equipment: equipment, level: level)
        let weekly = weekly(missedWeekday: missedWeekday)

        return TodayResponse(
            greeting: greeting(profile),
            goalContext: goalContext(profile, foodTarget: nutrition.foodTargetKcal, months: timelineMonths),
            focusLabel: focusLabel(focus),
            coachMessage: coachMessage(focus, food: nutrition.foodTargetKcal, protein: nutrition.proteinG),
            nutrition: nutrition, workout: workout, weekly: weekly,
            consistency: consistency(missedWeekday: missedWeekday),
            isDemo: isDemo)
    }

    static func adjustWeek(missedWeekday: String?, strategy: String) -> AdjustWeekResponse {
        var plan = weekly(missedWeekday: missedWeekday)
        let order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var days = plan.days
        let today = todayWeekday()
        var message = "Done — your week is balanced again. Forward is the only direction that matters."

        if let mIdx = days.firstIndex(where: { $0.status == "missed" }) {
            let missedLabel = days[mIdx].focusLabel
            switch strategy {
            case "move_today", "shorter":
                if let tIdx = days.firstIndex(where: { $0.weekday == today }), days[tIdx].status != "completed" {
                    let label = strategy == "shorter" ? "Shorter \(missedLabel.lowercased())" : missedLabel
                    days[tIdx] = WeeklyDay(weekday: days[tIdx].weekday, focusLabel: label, status: "today")
                }
                days[mIdx] = WeeklyDay(weekday: days[mIdx].weekday, focusLabel: "Rest", status: "rest")
                message = strategy == "shorter"
                    ? "I moved a shorter version to today. Lighter still counts — your week stays on track."
                    : "Moved to today. One flexible day keeps the whole week intact."
            case "rebalance":
                if let rIdx = days.firstIndex(where: { $0.status == "rest" &&
                    (order.firstIndex(of: $0.weekday) ?? 0) > (order.firstIndex(of: days[mIdx].weekday) ?? 0) }) {
                    days[rIdx] = WeeklyDay(weekday: days[rIdx].weekday, focusLabel: missedLabel, status: "planned")
                }
                days[mIdx] = WeeklyDay(weekday: days[mIdx].weekday, focusLabel: "Rest", status: "rest")
                message = "Rebalanced — I slotted the session into a free day so nothing piles up."
            default:
                days[mIdx] = WeeklyDay(weekday: days[mIdx].weekday, focusLabel: "Rest", status: "rest")
                message = "Skipped, no problem. The best plan is the one you can keep — onward."
            }
        }
        plan = WeeklyPlan(days: days,
                          completedCount: days.filter { $0.status == "completed" }.count,
                          plannedCount: days.filter { $0.status == "planned" || $0.status == "today" }.count,
                          missedCount: days.filter { $0.status == "missed" }.count)
        return AdjustWeekResponse(weekly: plan, message: message)
    }

    // MARK: - Local copy / dataset helpers

    private static func localMain(for focus: String) -> [CoachExerciseItem] {
        switch focus {
        case "strength", "muscleBuilding":
            return [
                .init(id: "ex_db_goblet_squat", name: "Goblet squats", category: "strength", detail: "3 × 12", rest: "60s rest", cue: "Sit between your hips, chest tall.", lowImpactAlternative: "Bodyweight box squat"),
                .init(id: "ex_db_row", name: "Dumbbell rows", category: "strength", detail: "3 × 10 / side", rest: "60s rest", cue: "Pull to the hip, squeeze the back.", lowImpactAlternative: nil),
                .init(id: "ex_db_shoulder_press", name: "Shoulder press", category: "strength", detail: "3 × 10", rest: "60s rest", cue: "Ribs down, press without arching.", lowImpactAlternative: "Seated press"),
                .init(id: "ex_core_plank", name: "Forearm plank", category: "core", detail: "3 × 30s", rest: "30s rest", cue: "Straight line, brace the belly.", lowImpactAlternative: "Knees-down plank")
            ]
        case "cardio":
            return [
                .init(id: "ex_outdoor_brisk_walk", name: "Brisk walk", category: "cardio", detail: "8 min", rest: "No rest", cue: "Quick steps, relaxed shoulders.", lowImpactAlternative: nil),
                .init(id: "ex_bw_mountain_climber", name: "Mountain climbers", category: "cardio", detail: "3 × 30s", rest: "30s rest", cue: "Hips low, light quick feet.", lowImpactAlternative: "Standing knee drives"),
                .init(id: "ex_outdoor_jog", name: "Easy jog", category: "cardio", detail: "10 min", rest: "Walk to recover", cue: "Land softly, keep it conversational.", lowImpactAlternative: "Walk–jog intervals")
            ]
        case "mobility":
            return [
                .init(id: "ex_mob_cat_cow", name: "Cat–cow flow", category: "mobility", detail: "3 min", rest: "No rest", cue: "Move with your breath.", lowImpactAlternative: nil),
                .init(id: "ex_desk_hip_flexor_stretch", name: "Hip-flexor stretch", category: "mobility", detail: "2 min", rest: "No rest", cue: "Open the front of the hips.", lowImpactAlternative: nil),
                .init(id: "ex_rec_box_breathing", name: "Box breathing", category: "recovery", detail: "3 min", rest: "No rest", cue: "In 4, hold 4, out 4, hold 4.", lowImpactAlternative: nil)
            ]
        default: // fatLoss / balanced
            return [
                .init(id: "ex_bw_squat", name: "Bodyweight squats", category: "strength", detail: "3 × 15", rest: "45s rest", cue: "Knees over toes, chest proud.", lowImpactAlternative: "Box squat to a chair"),
                .init(id: "ex_bw_lunge", name: "Reverse lunges", category: "strength", detail: "3 × 10 / leg", rest: "45s rest", cue: "Step back, drop the back knee softly.", lowImpactAlternative: "Supported split squat"),
                .init(id: "ex_bw_mountain_climber", name: "Mountain climbers", category: "cardio", detail: "3 × 30s", rest: "30s rest", cue: "Hips low, light quick feet.", lowImpactAlternative: "Standing knee drives"),
                .init(id: "ex_core_plank", name: "Forearm plank", category: "core", detail: "3 × 30s", rest: "30s rest", cue: "Straight line, brace the belly.", lowImpactAlternative: "Knees-down plank")
            ]
        }
    }

    private static func goalLabel(_ g: CoachGoal) -> String {
        switch g { case .fatLoss: return "Fat-loss day"; case .muscleGain: return "Strength day"; case .maintenance: return "Balance day" }
    }
    private static func coachExplanation(_ g: CoachGoal) -> String {
        switch g {
        case .fatLoss: return "This keeps you in a steady, sustainable deficit — enough to lose fat without crashing your energy at work or losing muscle."
        case .muscleGain: return "A small surplus with high protein gives your body what it needs to build strength, without unnecessary fat gain."
        case .maintenance: return "This keeps your fuel near your daily burn so you hold your progress and feel steady through long desk days."
        }
    }
    private static func focusLabel(_ f: String) -> String {
        switch f {
        case "fatLoss": return "Fat-loss day"; case "strength": return "Strength day"
        case "muscleBuilding": return "Muscle-building day"; case "mobility": return "Recovery day"
        case "cardio": return "Cardio day"; default: return "Balanced day"
        }
    }
    private static func displayLocation(_ l: String) -> String { l == "office" ? "desk" : l }
    private static func coachNote(_ focus: String, _ duration: Int) -> String {
        if focus == "mobility" { return "Move easy and breathe — this is how you undo a day of sitting." }
        if duration <= 15 { return "Short and focused. A little, often, beats perfect-but-never." }
        if focus == "fatLoss" { return "Keep the rests honest and the effort steady. You’ve got this." }
        return "Leave a rep or two in the tank and finish feeling strong, not wrecked."
    }
    private static func greeting(_ p: UserProfile) -> String {
        let name = p.name.isEmpty ? "there" : p.name
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
        return "Good \(part), \(name)"
    }
    private static func goalContext(_ p: UserProfile, foodTarget: Int, months: Int?) -> String {
        switch CoachGoal.from(p.goal) {
        case .fatLoss:
            let m = (months ?? 4) > 0 ? (months ?? 4) : 4
            return "To move from \(Int(p.weightKg)) kg to \(Int(p.targetWeightKg)) kg in about \(m) months, your food target is around \(foodTarget.formatted()) kcal/day."
        case .muscleGain:
            return "Building toward \(Int(p.targetWeightKg)) kg with a steady, strength-focused plan."
        case .maintenance:
            return "Holding your progress and keeping your energy steady through long desk days."
        }
    }
    private static func coachMessage(_ focus: String, food: Int, protein: Int) -> String {
        let f = food.formatted()
        switch focus {
        case "mobility": return "Today is a recovery day. Keep your food target around \(f) kcal and aim for \(protein)g protein. A few minutes of easy movement is enough to stay on track."
        case "cardio": return "Today is a cardio day. Keep your food target around \(f) kcal and hit \(protein)g protein. Even a brisk walk after work counts."
        case "strength", "muscleBuilding": return "Today is a strength day. Fuel around \(f) kcal and \(protein)g protein to recover well and build."
        default: return "Today is a fat-loss day. Keep your food target around \(f) kcal and hit \(protein)g protein. A short workout is enough to stay on track."
        }
    }
    private static func consistency(missedWeekday: String?) -> ConsistencyCoach {
        guard let missed = missedWeekday else {
            return ConsistencyCoach(missedDay: nil,
                message: "You’re showing up — that’s the whole game. Keep the streak going at your own pace.",
                options: [])
        }
        let full = fullWeekday(missed)
        return ConsistencyCoach(missedDay: full,
            message: "You missed \(full). No problem — I can make today lighter and still keep your week on track.",
            options: [
                CoachOption(id: "move_today", label: "Move it to today"),
                CoachOption(id: "shorter", label: "Create a shorter version"),
                CoachOption(id: "rebalance", label: "Rebalance this week"),
                CoachOption(id: "skip", label: "Skip and continue")
            ])
    }

    private static func focusForToday() -> String { focusForWeekday(todayWeekday()) }
    private static func focusForWeekday(_ wd: String) -> String {
        switch wd {
        case "Mon": return "fatLoss"; case "Tue": return "mobility"; case "Wed": return "strength"
        case "Fri": return "cardio"; case "Sat": return "balanced"; default: return "mobility"
        }
    }
    private static func todayWeekday() -> String {
        let map = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return map[Calendar.current.component(.weekday, from: Date()) - 1]
    }
    private static func fullWeekday(_ s: String) -> String {
        ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday",
         "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"][s] ?? s
    }
}
