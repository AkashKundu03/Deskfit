import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// DeskFit "Today" — a premium, coach-style dashboard that reflects the user's
// REAL plan state: today's scheduled session (from the weekly planner), meal
// targets, and lifecycle actions (complete / skip / reschedule / rebalance).
// Driven by CoachService + PlanService with local fallback, so it's always
// populated — even offline or in demo mode.
// ─────────────────────────────────────────────────────────────────────────────

struct TodayView: View {
    @Environment(AppState.self) private var state
    private let coach = CoachService()
    private let plans = PlanService()

    @State private var today: TodayResponse?
    @State private var weeklyPlan: WeeklyWorkoutPlan?     // real day-wise plan
    @State private var mealPlan: MealPlanResult?
    @State private var generatedWorkout: GeneratedWorkout? // today-only override
    @State private var demoWeekly: WeeklyPlan?             // demo "adjust" override

    @State private var workoutDone = false
    @State private var isLoading = true
    @State private var showPlanner = false
    @State private var showMealPlanner = false
    @State private var rescheduleSession: WeeklySession?
    @State private var banner: String?
    @State private var showAdjust = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if let t = today {
                        heroCard(t)
                        workoutSection(t)
                        weeklySection(t)
                        nutritionCard(t.nutrition)
                        mealSection(t)
                        if weeklyPlan == nil, t.consistency.missedDay != nil {
                            consistencyCard(t.consistency)
                        }
                    } else if isLoading {
                        loadingCard
                    } else {
                        GlassCard {
                            Text("Complete your assessment to see today’s plan.")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 48)   // clears the bottom tab bar comfortably
            }

            if let banner { toast(banner) }
        }
        .task { await load() }
        .sheet(isPresented: $showPlanner, onDismiss: { Task { await reloadPlans() } }) {
            WorkoutPlannerView(
                initialFocus: today?.workout.focus,
                onTodayWorkout: { gw in generatedWorkout = gw; workoutDone = false },
                onWeeklyCreated: { plan in
                    weeklyPlan = plan
                    generatedWorkout = nil
                    flash("Your week is set — \(plan.sessions.count) sessions ready.")
                }
            )
        }
        .sheet(isPresented: $showMealPlanner) {
            if let t = today {
                MealPlannerView(targets: t.nutrition, onCreated: { mp in mealPlan = mp })
            }
        }
        .sheet(item: $rescheduleSession) { session in
            RescheduleSheet(session: session, allWeekdays: Weekdays.order) { action in
                await handleReschedule(session, action)
            }
        }
        .confirmationDialog("Adjust your week", isPresented: $showAdjust, titleVisibility: .visible) {
            ForEach(adjustOptions, id: \.0) { opt in
                Button(opt.1) { Task { await applyStrategy(opt.0) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private let adjustOptions: [(String, String)] = [
        ("move_today", "Move it to today"),
        ("shorter", "Create a shorter version"),
        ("rebalance", "Rebalance this week"),
        ("skip", "Skip and continue"),
    ]

    // MARK: - Header

    private var header: some View {
        HStack {
            BrandLockup(size: 34)
            Spacer()
            Button {
                AppConfig.useDemoData.toggle()
                Task { await load() }
            } label: {
                Text(AppConfig.useDemoData ? "Demo ON" : "Demo")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(
                        Capsule().fill(AppConfig.useDemoData ? Theme.accent.opacity(0.9) : .white.opacity(0.10))
                    )
                    .foregroundStyle(AppConfig.useDemoData ? .black : .white.opacity(0.8))
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Hero coach card

    private func heroCard(_ t: TodayResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(t.greeting)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                chip(t.focusLabel, filled: true)
                Text(t.goalContext)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 14) {
                    bigStat("Food target", t.nutrition.foodTargetKcal.formatted(), "kcal")
                    Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 46)
                    bigStat("Protein goal", "\(t.nutrition.proteinG)", "g")
                }
                .padding(.top, 2)

                Text(t.coachMessage)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Workout section (reflects real plan state)

    @ViewBuilder
    private func workoutSection(_ t: TodayResponse) -> some View {
        if let gw = generatedWorkout {
            generatedWorkoutCard(gw)
        } else if let plan = weeklyPlan {
            if let s = todaySession(plan) {
                scheduledCard(s)
            } else {
                restDayCard()
            }
        } else {
            coachWorkoutCard(t)
        }
    }

    /// Today's scheduled session pulled from the weekly plan.
    private func scheduledCard(_ s: WeeklySession) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Today’s workout", systemImage: "figure.run")
                    Spacer()
                    statusBadge(s.status)
                }
                Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    metaChip("\(s.durationMin) min", "clock")
                    metaChip(s.location.capitalized, "mappin.and.ellipse")
                    metaChip("~\(s.estimatedCalories) kcal", "flame")
                }
                if let warm = s.warmup.first {
                    Text("Warm-up · \(warm.name) (\(warm.detail))")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(s.exercises.prefix(3)) { ex in exerciseRow(ex) }
                    if s.exercises.count > 3 {
                        Text("+ \(s.exercises.count - 3) more")
                            .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(s.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 10) {
                    if s.status == "completed" {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.accent.opacity(0.18)))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Button {
                            Task { await completeScheduled(s) }
                        } label: { Label("Mark completed", systemImage: "checkmark.circle") }
                            .buttonStyle(PillButtonStyle(filled: true))
                        Button { rescheduleSession = s } label: { Text("Skip / Reschedule") }
                            .buttonStyle(PillButtonStyle(filled: false))
                    }
                    Button { showPlanner = true } label: { Text("Regenerate / change") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
                .padding(.top, 4)
            }
        }
    }

    /// Shown when today isn't one of the chosen training days.
    private func restDayCard() -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Today’s reset", systemImage: "leaf")
                Text("No session scheduled today — enjoy it.")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("Optional 10-minute reset: a short walk, a few mobility flows, and easy breathing. Recovery is where progress sticks.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button { showPlanner = true } label: { Text("Add a workout today") }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
        }
    }

    /// A freshly generated single workout (today-only).
    private func generatedWorkoutCard(_ w: GeneratedWorkout) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Today’s workout", systemImage: "figure.run")
                    Spacer()
                    Text("Just generated").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Text(w.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    metaChip("\(w.durationMin) min", "clock")
                    metaChip(w.location.capitalized, "mappin.and.ellipse")
                    metaChip("~\(w.estimatedCalories) kcal", "flame")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(w.main.prefix(3)) { ex in exerciseRow(ex) }
                    if w.main.count > 3 {
                        Text("+ \(w.main.count - 3) more").font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(w.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 10) {
                    Button {
                        workoutDone = true
                        flash("Nice work — that’s another day your body and focus will thank you for.")
                    } label: {
                        Label(workoutDone ? "Completed" : "Mark completed",
                              systemImage: workoutDone ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(PillButtonStyle(filled: true)).disabled(workoutDone)
                    Button { showPlanner = true } label: { Text("Generate another") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
                .padding(.top, 4)
            }
        }
    }

    /// Default coach-suggested workout when there's no plan yet (with CTA).
    private func coachWorkoutCard(_ t: TodayResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Today’s workout", systemImage: "figure.run")
                Text(t.workout.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    metaChip("\(t.workout.durationMin) min", "clock")
                    metaChip(t.workout.location.capitalized, "mappin.and.ellipse")
                    metaChip("~\(t.workout.estimatedCalories) kcal", "flame")
                }
                if let warm = t.workout.warmup.first {
                    Text("Warm-up · \(warm.name) (\(warm.detail))")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(t.workout.main.prefix(3)) { ex in exerciseRow(ex) }
                    if t.workout.main.count > 3 {
                        Text("+ \(t.workout.main.count - 3) more").font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(t.workout.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 10) {
                    Button { showPlanner = true } label: { Text("Generate today’s workout") }
                        .buttonStyle(PillButtonStyle(filled: true))
                    HStack(spacing: 10) {
                        Button {
                            workoutDone = true
                            flash("Nice work — that’s another day your body and focus will thank you for.")
                        } label: {
                            Label(workoutDone ? "Completed" : "Mark completed",
                                  systemImage: workoutDone ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(PillButtonStyle(filled: false)).disabled(workoutDone)
                        Button { showAdjust = true } label: { Text("Skip / Adjust") }
                            .buttonStyle(PillButtonStyle(filled: false))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Weekly section

    @ViewBuilder
    private func weeklySection(_ t: TodayResponse) -> some View {
        if let plan = weeklyPlan {
            realWeeklyCard(plan)
        } else {
            demoWeeklyCard(demoWeekly ?? t.weekly)
        }
    }

    private func realWeeklyCard(_ plan: WeeklyWorkoutPlan) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("This week’s plan", systemImage: "calendar")

                HStack(spacing: 8) {
                    ForEach(Weekdays.order, id: \.self) { wd in
                        let s = plan.sessions.first { $0.weekday == wd }
                        VStack(spacing: 6) {
                            Text(wd).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Circle()
                                .fill(realStatusColor(s?.status))
                                .frame(width: 26, height: 26)
                                .overlay(realStatusGlyph(s?.status))
                                .overlay(
                                    Circle().stroke(Theme.accent,
                                                    lineWidth: wd == Weekdays.today() ? 2 : 0)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { if let s, s.status != "completed" { rescheduleSession = s } }
                    }
                }

                HStack(spacing: 14) {
                    countLabel("\(plan.completedCount)", "done", Theme.accent)
                    countLabel("\(plan.plannedCount)", "to go", .white.opacity(0.8))
                    if plan.skippedCount > 0 { countLabel("\(plan.skippedCount)", "skipped", .orange) }
                }
                .font(.footnote)

                Text("Tap any day to reschedule it.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 10) {
                    Button { Task { await rebalance() } } label: { Text("Rebalance week") }
                        .buttonStyle(PillButtonStyle(filled: false))
                    Button { showPlanner = true } label: { Text("Edit week") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
            }
        }
    }

    private func demoWeeklyCard(_ plan: WeeklyPlan) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("This week’s plan", systemImage: "calendar")
                HStack(spacing: 8) {
                    ForEach(plan.days) { day in
                        VStack(spacing: 6) {
                            Text(day.weekday).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Circle().fill(statusColor(day.status)).frame(width: 26, height: 26)
                                .overlay(statusGlyph(day.status))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 14) {
                    countLabel("\(plan.completedCount)", "done", Theme.accent)
                    countLabel("\(plan.plannedCount)", "to go", .white.opacity(0.8))
                    if plan.missedCount > 0 { countLabel("\(plan.missedCount)", "missed", .orange) }
                }
                .font(.footnote)
                Button { showPlanner = true } label: { Text("Plan your week") }
                    .buttonStyle(PillButtonStyle(filled: true))
                Button { showAdjust = true } label: { Text("Adjust this week") }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
        }
    }

    // MARK: - Nutrition card

    private func nutritionCard(_ n: NutritionTargets) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Fuel target", systemImage: "fork.knife")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(n.foodTargetKcal.formatted())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).monospacedDigit()
                    Text("kcal / day").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                HStack(spacing: 10) {
                    macroTile("Protein", "\(n.proteinG)g")
                    macroTile("Carbs", "\(n.carbsG)g")
                    macroTile("Fat", "\(n.fatG)g")
                    macroTile("Fiber", "\(n.fiberG)g")
                }
                Text(n.coachExplanation)
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if n.safety.isAggressive, let msg = n.safety.message {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(msg).font(.footnote).foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.orange.opacity(0.12)))
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        howRow("Your daily burn", "\(n.dailyBurnKcal.formatted()) kcal")
                        howRow("Estimated resting energy (BMR)", "\(Int(n.howCalculated.bmr).formatted()) kcal")
                        howRow("Maintenance (TDEE)", "\(Int(n.howCalculated.tdee).formatted()) kcal")
                        Text(n.howCalculated.method).font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 8)
                } label: {
                    Text("How this is calculated")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .tint(Theme.accent)
            }
        }
    }

    // MARK: - Meal section

    @ViewBuilder
    private func mealSection(_ t: TodayResponse) -> some View {
        if let mp = mealPlan {
            mealCard(mp)
        } else {
            mealCTACard()
        }
    }

    private func mealCard(_ mp: MealPlanResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    cardTitle("Today’s meals", systemImage: "takeoutbag.and.cup.and.straw")
                    Spacer()
                    Text("\(mp.dailyKcal.formatted()) kcal")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                }
                ForEach(mp.meals) { meal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(mealStatusColor(meal.status)).frame(width: 8, height: 8)
                            Text(meal.name).font(.subheadline.weight(.semibold))
                                .foregroundStyle(meal.status == "skipped" ? .white.opacity(0.45) : .white)
                            Spacer()
                            Text("\(meal.kcal) kcal").font(.subheadline).foregroundStyle(.white.opacity(0.75)).monospacedDigit()
                            Menu {
                                Button("Mark completed") { Task { await completeMeal(meal) } }
                                Button("Skip") { Task { await skipMeal(meal) } }
                            } label: {
                                Image(systemName: "ellipsis.circle").foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Text("\(meal.proteinG)P · \(meal.carbsG)C · \(meal.fatG)F · \(meal.fiberG) fiber")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                        if let first = meal.suggestions.first {
                            Text("Try: \(first)").font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if meal.id != mp.meals.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
                Text(mp.coachNote).font(.caption).italic().foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button { showMealPlanner = true } label: { Text("Adjust meal targets") }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
        }
    }

    private func mealCTACard() -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Meal targets", systemImage: "takeoutbag.and.cup.and.straw")
                Text("Plan your meals")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("Split your daily target into breakfast, lunch and dinner — with simple portion ideas for your preferences.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button { showMealPlanner = true } label: { Text("Plan meals") }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
        }
    }

    // MARK: - Consistency coach card (demo only)

    private func consistencyCard(_ c: ConsistencyCoach) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Your coach", systemImage: "heart.text.square")
                Text(c.message).font(.callout).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(c.options) { opt in
                        Button { Task { await applyStrategy(opt.id) } } label: {
                            HStack { Text(opt.label); Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                        }
                        .buttonStyle(PillButtonStyle(filled: false))
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text("Your coach is preparing today’s plan…").foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Reusable pieces

    private func exerciseRow(_ ex: CoachExerciseItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.accent)
            Text(ex.name).foregroundStyle(.white)
            Spacer()
            Text(ex.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
        }
    }

    private func cardTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text).font(.caption.weight(.bold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(filled ? Theme.accent : .white.opacity(0.12)))
            .foregroundStyle(filled ? .black : .white)
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "completed": return ("Completed", Theme.accent)
            case "skipped": return ("Skipped", .orange)
            default: return ("Planned", .white.opacity(0.7))
            }
        }()
        return Text(label).font(.caption2.weight(.bold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func metaChip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white.opacity(0.85))
    }

    private func bigStat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    private func howRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).monospacedDigit()
        }
    }

    private func countLabel(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "completed": return Theme.accent
        case "today": return .white
        case "missed": return .orange
        case "rest": return .white.opacity(0.12)
        default: return .white.opacity(0.28)
        }
    }

    @ViewBuilder private func statusGlyph(_ status: String) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
        case "today": Circle().fill(Theme.accent).frame(width: 10, height: 10)
        case "missed": Image(systemName: "arrow.uturn.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        default: EmptyView()
        }
    }

    private func realStatusColor(_ status: String?) -> Color {
        switch status {
        case "completed": return Theme.accent
        case "skipped": return .orange
        case .some: return .white.opacity(0.28)   // planned / rescheduled
        case nil: return .white.opacity(0.10)      // no session that day
        }
    }

    @ViewBuilder private func realStatusGlyph(_ status: String?) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
        case "skipped": Image(systemName: "arrow.uturn.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        default: EmptyView()
        }
    }

    private func mealStatusColor(_ status: String) -> Color {
        switch status {
        case "completed": return Theme.accent
        case "skipped": return .orange
        default: return .white.opacity(0.3)
        }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium)).foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.bottom, 24).padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func todaySession(_ plan: WeeklyWorkoutPlan) -> WeeklySession? {
        plan.sessions.first { $0.weekday == Weekdays.today() }
    }

    private func load() async {
        isLoading = true
        demoWeekly = nil
        workoutDone = false
        generatedWorkout = nil
        let result = await coach.today(profile: state.profile, timelineMonths: nil, missedWeekday: nil)
        let plan = await plans.currentWeeklyPlan()
        let meals = await plans.currentMealPlan()
        withAnimation(.easeOut(duration: 0.3)) {
            today = result
            weeklyPlan = plan
            mealPlan = meals
            isLoading = false
        }
    }

    /// Refresh only the persisted plans (after the planner sheet closes).
    private func reloadPlans() async {
        let plan = await plans.currentWeeklyPlan()
        let meals = await plans.currentMealPlan()
        withAnimation { weeklyPlan = plan ?? weeklyPlan; mealPlan = meals ?? mealPlan }
    }

    private func completeScheduled(_ s: WeeklySession) async {
        if let updated = await plans.completeSession(s.id) {
            withAnimation { weeklyPlan = updated }
        }
        flash("Done — that’s consistency compounding. Nicely played.")
    }

    private func handleReschedule(_ s: WeeklySession, _ action: RescheduleAction) async {
        switch action {
        case .skip:
            if let u = await plans.skipSession(s.id) { withAnimation { weeklyPlan = u } }
            flash("Skipped \(Weekdays.full[s.weekday] ?? s.weekday). No problem — rebalance anytime.")
        case .reschedule(let wd):
            if let u = await plans.rescheduleSession(s.id, to: wd) { withAnimation { weeklyPlan = u } }
            flash("Moved \(Weekdays.full[s.weekday] ?? s.weekday) → \(Weekdays.full[wd] ?? wd).")
        case .shorter:
            if let u = await plans.shorterSession(s.id) { withAnimation { weeklyPlan = u } }
            flash("Made today lighter — a shorter session still counts.")
        case .rebalance:
            if let u = await plans.rebalanceWeek() { withAnimation { weeklyPlan = u } }
            flash("Rebalanced — I spaced things out so nothing piles up.")
        }
    }

    private func rebalance() async {
        if let u = await plans.rebalanceWeek() { withAnimation { weeklyPlan = u } }
        flash("Rebalanced — your remaining sessions are spread out.")
    }

    private func completeMeal(_ m: MealTarget) async {
        if let u = await plans.completeMeal(m.id) { withAnimation { mealPlan = u } }
        flash("\(m.name) logged. Protein first — you’re on target.")
    }

    private func skipMeal(_ m: MealTarget) async {
        if let u = await plans.skipMeal(m.id) { withAnimation { mealPlan = u } }
        flash("\(m.name) skipped — adjust the rest of the day if you’re hungry.")
    }

    private func applyStrategy(_ strategy: String) async {
        let missed = AppConfig.useDemoData ? AppConfig.demoMissedWeekday : nil
        let res = await coach.adjustWeek(strategy: strategy, missedWeekday: missed)
        withAnimation { demoWeekly = res.weekly }
        flash(res.message)
    }

    private func flash(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { banner = nil }
        }
    }
}
