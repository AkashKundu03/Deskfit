import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Local, deterministic mirror of the backend planner engine
// (weekly-planner.service.ts + meal-planner.service.ts). Powers demo mode and
// offline fallback so the planner never depends on the production server.
// Keep roughly in sync with the backend; the backend stays source of truth.
// ─────────────────────────────────────────────────────────────────────────────

enum PlanLocalEngine {

    // MARK: - Weekly plan

    private struct Blueprint { let focus: String; let title: String }

    private static func blueprints(for goal: String) -> [Blueprint] {
        switch goal {
        case "muscleGain":
            return [
                .init(focus: "strength", title: "Push strength"),
                .init(focus: "strength", title: "Pull strength"),
                .init(focus: "mobility", title: "Mobility & core"),
                .init(focus: "strength", title: "Lower-body strength"),
                .init(focus: "balanced", title: "Full-body pump"),
                .init(focus: "cardio", title: "Light conditioning"),
                .init(focus: "mobility", title: "Recovery flow"),
            ]
        case "maintenance":
            return [
                .init(focus: "balanced", title: "Balanced full-body"),
                .init(focus: "cardio", title: "Steady cardio"),
                .init(focus: "strength", title: "Strength maintenance"),
                .init(focus: "mobility", title: "Mobility & core"),
                .init(focus: "cardio", title: "Active-recovery cardio"),
                .init(focus: "balanced", title: "Balanced circuit"),
                .init(focus: "mobility", title: "Recovery flow"),
            ]
        default: // fatLoss
            return [
                .init(focus: "strength", title: "Full-body strength"),
                .init(focus: "cardio", title: "Low-impact conditioning"),
                .init(focus: "strength", title: "Dumbbell strength"),
                .init(focus: "cardio", title: "Fat-loss intervals"),
                .init(focus: "mobility", title: "Mobility & core reset"),
                .init(focus: "balanced", title: "Balanced circuit"),
                .init(focus: "mobility", title: "Recovery flow"),
            ]
        }
    }

    private static let intense: Set<String> = ["strength", "muscleBuilding", "cardio", "fatLoss"]
    private static let lightBlueprints = [
        Blueprint(focus: "mobility", title: "Mobility & core reset"),
        Blueprint(focus: "balanced", title: "Balanced circuit"),
    ]

    static func buildWeekly(selectedDays: [String], location: String, durationMin: Int,
                            equipment: [String], level: String, goal: String) -> WeeklyWorkoutPlan {
        let days = selectedDays
            .filter { Weekdays.order.contains($0) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { Weekdays.index($0) < Weekdays.index($1) }

        let pool = blueprints(for: goal)
        var bps = days.enumerated().map { (i, _) in pool[i % pool.count] }

        // Space intensity: two calendar-adjacent intense days → make the 2nd light.
        var lightCursor = 0
        for i in 1..<max(1, days.count) where i < days.count {
            let adjacent = Weekdays.index(days[i]) - Weekdays.index(days[i - 1]) == 1
            if adjacent && intense.contains(bps[i].focus) && intense.contains(bps[i - 1].focus) {
                bps[i] = lightBlueprints[lightCursor % lightBlueprints.count]
                lightCursor += 1
            }
        }

        let monday = mondayOfThisWeek()
        let sessions = days.enumerated().map { (i, weekday) -> WeeklySession in
            let bp = bps[i]
            let w = CoachEngine.generate(focus: bp.focus, durationMin: durationMin,
                                         location: location, equipment: equipment,
                                         level: level, title: bp.title)
            return WeeklySession(
                id: "\(weekday)_\(bp.focus)_\(i)",
                weekday: weekday,
                date: dateString(monday, weekdayIndex: Weekdays.index(weekday)),
                title: bp.title,
                focus: w.focus, focusLabel: w.focusLabel,
                durationMin: w.durationMin, location: w.location, equipment: w.equipment,
                estimatedCalories: w.estimatedCalories,
                warmup: w.warmup, exercises: w.main,
                coachNote: w.coachNote, status: "planned")
        }

        return recounted(WeeklyWorkoutPlan(
            id: "local_\(Int(Date().timeIntervalSince1970))",
            weekStartDate: dateString(monday, weekdayIndex: 0),
            selectedDays: days, goal: goal, level: level, location: location,
            sessions: sessions, completedCount: 0, plannedCount: 0, skippedCount: 0))
    }

    static func setStatus(_ plan: WeeklyWorkoutPlan, sessionId: String, status: String) -> WeeklyWorkoutPlan {
        var p = plan
        if let i = p.sessions.firstIndex(where: { $0.id == sessionId }) {
            p.sessions[i].status = status
        }
        return recounted(p)
    }

    static func reschedule(_ plan: WeeklyWorkoutPlan, sessionId: String, toWeekday: String) -> WeeklyWorkoutPlan {
        var p = plan
        let monday = mondayOfThisWeek()
        if let i = p.sessions.firstIndex(where: { $0.id == sessionId }) {
            let old = p.sessions[i].weekday
            p.sessions[i].weekday = toWeekday
            p.sessions[i].date = dateString(monday, weekdayIndex: Weekdays.index(toWeekday))
            p.sessions[i].status = "planned"
            var selected = Set(p.selectedDays)
            selected.remove(old); selected.insert(toWeekday)
            p.selectedDays = Array(selected).sorted { Weekdays.index($0) < Weekdays.index($1) }
        }
        p.sessions.sort { Weekdays.index($0.weekday) < Weekdays.index($1.weekday) }
        return recounted(p)
    }

    static func shorter(_ plan: WeeklyWorkoutPlan, sessionId: String) -> WeeklyWorkoutPlan {
        var p = plan
        if let i = p.sessions.firstIndex(where: { $0.id == sessionId }) {
            let s = p.sessions[i]
            let short = max(10, s.durationMin / 2)
            let w = CoachEngine.generate(focus: s.focus, durationMin: short, location: s.location,
                                         equipment: s.equipment, level: "beginner",
                                         title: "Shorter \(s.title.lowercased()) (\(short) min)")
            p.sessions[i].title = w.title
            p.sessions[i].durationMin = w.durationMin
            p.sessions[i].estimatedCalories = w.estimatedCalories
            p.sessions[i].warmup = w.warmup
            p.sessions[i].exercises = w.main
            p.sessions[i].coachNote = w.coachNote
            p.sessions[i].status = "planned"
        }
        return recounted(p)
    }

    static func rebalance(_ plan: WeeklyWorkoutPlan) -> WeeklyWorkoutPlan {
        var p = plan
        let monday = mondayOfThisWeek()
        let todayIdx = Weekdays.index(Weekdays.today())
        let remaining = Array(Weekdays.order[todayIdx...])
        let movable = p.sessions.enumerated().filter { $0.element.status != "completed" }
        guard !movable.isEmpty, !remaining.isEmpty else { return recounted(p) }

        let count = movable.count
        let step = Double(remaining.count) / Double(count)
        for (k, item) in movable.enumerated() {
            let target = count >= remaining.count
                ? remaining[k % remaining.count]
                : remaining[Int(Double(k) * step)]
            p.sessions[item.offset].weekday = target
            p.sessions[item.offset].date = dateString(monday, weekdayIndex: Weekdays.index(target))
            p.sessions[item.offset].status = "planned"
        }
        p.sessions.sort { Weekdays.index($0.weekday) < Weekdays.index($1.weekday) }
        p.selectedDays = Array(Set(p.sessions.map { $0.weekday }))
            .sorted { Weekdays.index($0) < Weekdays.index($1) }
        return recounted(p)
    }

    /// Regenerate ONE session's workout (guest/offline). Cycles the focus so the
    /// user gets a genuinely different session; other days are untouched.
    static func regenerate(_ plan: WeeklyWorkoutPlan, sessionId: String) -> WeeklyWorkoutPlan {
        var p = plan
        guard let i = p.sessions.firstIndex(where: { $0.id == sessionId }) else { return recounted(p) }
        let s = p.sessions[i]
        let order = ["strength", "cardio", "mobility", "balanced"]
        let idx = order.firstIndex(of: s.focus) ?? -1
        var next = order[(idx + 1 + order.count) % order.count]
        if next == s.focus { next = order[(idx + 2 + order.count) % order.count] }
        let w = CoachEngine.generate(focus: next, durationMin: s.durationMin,
                                     location: s.location, equipment: s.equipment, level: "beginner")
        // focus/focusLabel are `let`, so rebuild the session value.
        p.sessions[i] = WeeklySession(
            id: s.id, weekday: s.weekday, date: s.date, title: w.title,
            focus: w.focus, focusLabel: w.focusLabel, durationMin: s.durationMin,
            location: s.location, equipment: s.equipment, estimatedCalories: w.estimatedCalories,
            warmup: w.warmup, exercises: w.main, coachNote: w.coachNote, status: "planned")
        return recounted(p)
    }

    // MARK: - Standalone (today-only) workouts (guest/offline)

    static func buildStandalone(location: String, durationMin: Int, equipment: [String],
                                focus: String, level: String, title: String?, date: String) -> StandaloneWorkout {
        let w = CoachEngine.generate(focus: focus, durationMin: durationMin, location: location,
                                     equipment: equipment, level: level, title: title)
        return StandaloneWorkout(
            id: "local_sa_\(Int(Date().timeIntervalSince1970))",
            date: date, title: w.title, focus: w.focus, focusLabel: w.focusLabel,
            durationMin: w.durationMin, location: w.location, equipment: w.equipment,
            estimatedCalories: w.estimatedCalories, warmup: w.warmup, main: w.main,
            coachNote: w.coachNote, status: "planned")
    }

    static func setStandaloneStatus(_ s: StandaloneWorkout, status: String) -> StandaloneWorkout {
        var p = s; p.status = status; return p
    }

    /// The session scheduled for today, if any (used by Today's workout card).
    static func todaySession(_ plan: WeeklyWorkoutPlan) -> WeeklySession? {
        plan.sessions.first { $0.weekday == Weekdays.today() }
    }

    /// Local "Fix my remaining week" preview (guest/offline). Mirrors the backend
    /// rules: only future planned sessions move, completed/skipped are untouched,
    /// no double-booking, unavailable days respected; reports infeasible+fallback.
    static func fixWeekPreview(_ plan: WeeklyWorkoutPlan, unavailableDays: [String]) -> FixWeekResult {
        let monday = mondayOfThisWeek()
        let order = Weekdays.order
        let todayIdx = Weekdays.index(Weekdays.today())
        let unavailable = Set(unavailableDays)
        let before = plan.sessions.map {
            FixWeekBefore(sessionId: $0.id, weekday: $0.weekday, status: $0.status)
        }
        func isFuturePlanned(_ s: WeeklySession) -> Bool {
            (s.status == "planned" || s.status == "rescheduled") && Weekdays.index(s.weekday) > todayIdx
        }
        let movable = plan.sessions.filter(isFuturePlanned)
        let fixed = plan.sessions.filter { !isFuturePlanned($0) }
        if movable.isEmpty {
            return FixWeekResult(before: before, after: plan.sessions, changes: [],
                                 feasible: true, fallback: nil, reason: nil)
        }
        let occupied = Set(fixed.map { Weekdays.index($0.weekday) })
        var candidates: [Int] = []
        for i in (todayIdx + 1)..<order.count where !occupied.contains(i) && !unavailable.contains(order[i]) {
            candidates.append(i)
        }
        if candidates.count < movable.count {
            return FixWeekResult(before: before, after: plan.sessions, changes: [], feasible: false,
                                 fallback: "chooseMoreDays",
                                 reason: "Need \(movable.count) open day(s) after today, but only \(candidates.count) available.")
        }
        var chosen: [Int] = []
        let step = Double(candidates.count) / Double(movable.count)
        for i in 0..<movable.count { chosen.append(candidates[Int(Double(i) * step)]) }
        let ordered = movable.sorted { Weekdays.index($0.weekday) < Weekdays.index($1.weekday) }
        var moveTo: [String: Int] = [:]
        for (i, s) in ordered.enumerated() { moveTo[s.id] = chosen[i] }

        var changes: [FixWeekChange] = []
        let after = plan.sessions.map { s -> WeeklySession in
            guard let idx = moveTo[s.id] else { return s }
            var ns = s
            let newWeekday = order[idx]
            if newWeekday != s.weekday {
                changes.append(FixWeekChange(sessionId: s.id, title: s.title, from: s.weekday, to: newWeekday))
            }
            ns.weekday = newWeekday
            ns.date = dateString(monday, weekdayIndex: idx)
            ns.status = "rescheduled"
            return ns
        }
        return FixWeekResult(before: before, after: after, changes: changes, feasible: true, fallback: nil, reason: nil)
    }

    private static func recounted(_ plan: WeeklyWorkoutPlan) -> WeeklyWorkoutPlan {
        var p = plan
        p.completedCount = p.sessions.filter { $0.status == "completed" }.count
        p.plannedCount = p.sessions.filter { $0.status == "planned" || $0.status == "rescheduled" }.count
        p.skippedCount = p.sessions.filter { $0.status == "skipped" }.count
        return p
    }

    // MARK: - Meal plan

    private static let slotName: [String: String] = [
        "breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snack",
    ]
    private static let slotCoach: [String: String] = [
        "breakfast": "Front-load protein so you stay full through the morning desk block.",
        "lunch": "Your biggest plate — steady carbs here fuel the afternoon slump-free.",
        "dinner": "Protein + veg, lighter on carbs, so you sleep and recover well.",
        "snack": "A simple protein-forward bite to bridge the gap, not a second meal.",
    ]

    static func buildMeal(dailyKcal: Int, proteinG: Int, carbsG: Int, fatG: Int, fiberG: Int,
                          mealCount: Int, includeSnack: Bool, dietaryPref: String,
                          proteinPrefs: [String], carbPrefs: [String], fiberPrefs: [String],
                          allergens: [String]) -> MealPlanResult {
        let slots = resolveSlots(mealCount: mealCount, includeSnack: includeSnack)
        let weights = normalizedWeights(slots: slots, mealCount: mealCount)

        var meals: [MealTarget] = []
        var tk = 0, tp = 0, tc = 0, tf = 0, tfib = 0
        for (i, slot) in slots.enumerated() {
            let last = i == slots.count - 1
            let frac = weights[slot] ?? 0
            let kcal = last ? dailyKcal - tk : Int((Double(dailyKcal) * frac).rounded())
            let p = last ? proteinG - tp : Int((Double(proteinG) * frac).rounded())
            let c = last ? carbsG - tc : Int((Double(carbsG) * frac).rounded())
            let f = last ? fatG - tf : Int((Double(fatG) * frac).rounded())
            let fib = last ? fiberG - tfib : Int((Double(fiberG) * frac).rounded())
            tk += kcal; tp += p; tc += c; tf += f; tfib += fib
            meals.append(MealTarget(
                id: "meal_\(slot)", slot: slot, name: slotName[slot] ?? slot.capitalized,
                kcal: max(0, kcal), proteinG: max(0, p), carbsG: max(0, c),
                fatG: max(0, f), fiberG: max(0, fib),
                suggestions: suggestions(slot: slot, dietaryPref: dietaryPref,
                                         proteinPrefs: proteinPrefs, carbPrefs: carbPrefs,
                                         fiberPrefs: fiberPrefs, allergens: allergens),
                coachNote: slotCoach[slot] ?? "", status: "planned"))
        }

        return MealPlanResult(
            id: "local_meal", mealCount: mealCount, dietaryPref: dietaryPref,
            proteinPrefs: proteinPrefs, carbPrefs: carbPrefs, fiberPrefs: fiberPrefs, allergens: allergens,
            dailyKcal: dailyKcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG,
            meals: meals,
            coachNote: "These are targets, not rules. Hit the protein number first, keep meals roughly to these sizes, and the day takes care of itself.")
    }

    static func setMealStatus(_ plan: MealPlanResult, mealId: String, status: String) -> MealPlanResult {
        var p = plan
        if let i = p.meals.firstIndex(where: { $0.id == mealId }) { p.meals[i].status = status }
        return p
    }

    private static func resolveSlots(mealCount: Int, includeSnack: Bool) -> [String] {
        var base: [String]
        if mealCount <= 2 { base = ["breakfast", "dinner"] }
        else if mealCount == 3 { base = ["breakfast", "lunch", "dinner"] }
        else { base = ["breakfast", "lunch", "snack", "dinner"] }
        if includeSnack && !base.contains("snack") {
            base = ["breakfast", "lunch", "snack", "dinner"].filter { base.contains($0) || $0 == "snack" }
        }
        return base
    }

    private static func normalizedWeights(slots: [String], mealCount: Int) -> [String: Double] {
        let layouts: [Int: [String: Double]] = [
            2: ["breakfast": 0.45, "dinner": 0.55],
            3: ["breakfast": 0.27, "lunch": 0.38, "dinner": 0.35],
            4: ["breakfast": 0.25, "lunch": 0.32, "snack": 0.13, "dinner": 0.30],
        ]
        let base = layouts[min(4, max(2, mealCount))] ?? layouts[3]!
        var raw: [String: Double] = [:]; var sum = 0.0
        for s in slots { let w = base[s] ?? (s == "snack" ? 0.12 : 0.30); raw[s] = w; sum += w }
        var norm: [String: Double] = [:]
        for s in slots { norm[s] = (raw[s] ?? 0) / (sum == 0 ? 1 : sum) }
        return norm
    }

    private static let proteinLabel: [String: String] = [
        "paneer": "Paneer", "tofu": "Tofu", "fish": "Fish", "chicken": "Chicken",
        "eggs": "Eggs", "dal": "Dal / beans", "whey": "Whey shake",
    ]
    private static let carbLabel: [String: String] = [
        "rice": "Rice", "roti": "Roti", "oats": "Oats", "potato": "Potato",
        "quinoa": "Quinoa", "mixed": "Mixed grains",
    ]
    private static let fiberLabel: [String: String] = [
        "vegetables": "Veg", "fruits": "Fruit", "salad": "Salad", "legumes": "Legumes",
    ]

    private static func suggestions(slot: String, dietaryPref: String, proteinPrefs: [String],
                                    carbPrefs: [String], fiberPrefs: [String], allergens: [String]) -> [String] {
        let proteins = filterProteins(prefs: proteinPrefs, diet: dietaryPref, allergens: allergens)
        let carbs = pickCarbs(slot: slot, prefs: carbPrefs, allergens: allergens)
        let fibers = fiberPrefs.isEmpty ? ["vegetables"] : fiberPrefs

        let p1 = proteinLabel[proteins.first ?? ""] ?? "Protein source"
        let p2 = proteinLabel[proteins[safe: 1] ?? proteins.first ?? ""] ?? p1
        let c1 = carbLabel[carbs.first ?? ""] ?? "Whole grains"
        let c2 = carbLabel[carbs[safe: 1] ?? carbs.first ?? ""] ?? c1
        let f1 = fiberLabel[fibers.first ?? ""] ?? "Veg"

        switch slot {
        case "snack": return ["\(p1) + \(f1)", "\(p2) shake + fruit"]
        case "breakfast": return ["\(p1) + \(c1) + \(f1)", "\(p2) + fruit + \(c2)"]
        default: return ["\(p1) + \(c1) + \(f1)", "\(p2) + \(c2) + salad"]
        }
    }

    private static func filterProteins(prefs: [String], diet: String, allergens: [String]) -> [String] {
        var list = prefs.isEmpty ? ["dal", "paneer"] : prefs
        var block = Set<String>()
        if diet == "vegetarian" { ["fish", "chicken", "eggs"].forEach { block.insert($0) } }
        if diet == "eggitarian" { ["fish", "chicken"].forEach { block.insert($0) } }
        if diet == "vegan" { ["fish", "chicken", "eggs", "paneer", "whey"].forEach { block.insert($0) } }
        if allergens.contains("lactose") { ["paneer", "whey"].forEach { block.insert($0) } }
        let filtered = list.filter { !block.contains($0) }
        list = filtered.isEmpty ? ["dal", "tofu"] : filtered
        return list
    }

    private static func pickCarbs(slot: String, prefs: [String], allergens: [String]) -> [String] {
        var list = prefs.isEmpty ? ["rice", "oats"] : prefs
        if allergens.contains("gluten") {
            let ng = list.filter { $0 != "roti" }; list = ng.isEmpty ? ["rice", "oats"] : ng
        }
        if slot == "breakfast" && list.contains("oats") {
            list = ["oats"] + list.filter { $0 != "oats" }
        }
        return list
    }

    // MARK: - Date helpers

    private static func mondayOfThisWeek() -> Date {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1 = Sun … 7 = Sat
        let daysFromMon = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMon, to: today) ?? today
    }

    private static func dateString(_ monday: Date, weekdayIndex: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(byAdding: .day, value: weekdayIndex, to: monday) ?? monday
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
