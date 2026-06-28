import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// DeskFit "Today" — a premium, coach-style dashboard that reflects the user's
// REAL plan state: today's scheduled session (from the weekly planner), meal
// targets, and lifecycle actions (complete / skip / reschedule / rebalance).
// Driven by CoachService + PlanService with local fallback, so it's always
// populated — even offline or in demo mode.
// ─────────────────────────────────────────────────────────────────────────────

struct TodayView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    /// The local day the visible plan was loaded for — used to detect rollover.
    @State private var loadedDay = Weekdays.todayISO()
    private let coach = CoachService()
    private let plans = PlanService()
    private let mealTemplate = MealTemplateService()

    @State private var today: TodayResponse?
    @State private var weeklyPlan: WeeklyWorkoutPlan?     // real day-wise plan
    @State private var mealPlan: MealPlanResult?
    @State private var standalone: StandaloneWorkout? // today-only persisted workout
    @State private var demoWeekly: WeeklyPlan?             // demo "adjust" override

    @State private var workoutDone = false
    @State private var isLoading = true
    @State private var showPlanner = false
    @State private var showMealPlanner = false
    // Phase 2 — repeating weekly meal template.
    @State private var weeklyMeal: WeeklyMealPlanDTO?
    @State private var showMealWizard = false
    @State private var showMealWeek = false
    @State private var thaliMeal: MealDTO?
    @State private var rescheduleSession: WeeklySession?
    @State private var banner: String?
    @State private var showAdjust = false

    // Full workout-detail sheet (tappable days / "View full workout").
    @State private var detail: WorkoutDetailData?
    @State private var pendingRescheduleAfterDetail: WeeklySession?

    // "Fix my remaining week" preview/confirm.
    @State private var fixPreview: FixWeekResult?
    @State private var showFixWeek = false

    // Engagement: sign-in gate for guests, celebration + reminders.
    @State private var showSignInGate = false
    @State private var pendingPremiumAction: (() -> Void)?
    @State private var confettiTrigger = 0
    @State private var showWorkoutReminders = false
    @State private var showMealReminders = false

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
        // Refresh when returning to the foreground (and after a day/timezone
        // change), and tick once a minute to catch midnight while the app is open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshForCurrentDay() } }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if Weekdays.todayISO() != loadedDay { Task { await refreshForCurrentDay() } }
        }
        .sheet(isPresented: $showPlanner, onDismiss: { Task { await reloadPlans() } }) {
            WorkoutPlannerView(
                initialFocus: today?.workout.focus,
                onTodayWorkout: { sa in
                    standalone = sa
                    Haptics.impact()
                },
                onWeeklyCreated: { plan in
                    weeklyPlan = plan
                    standalone = nil
                    Haptics.impact()
                    flash("Your week is set — \(plan.sessions.count) sessions ready.")
                }
            )
        }
        .sheet(isPresented: $showMealPlanner) {
            if let t = today {
                MealPlannerView(targets: t.nutrition, onCreated: { mp in
                    mealPlan = mp
                    Haptics.impact()
                })
            }
        }
        .sheet(isPresented: $showMealWizard) {
            if let t = today {
                MealWizardView(targets: t.nutrition, onCreated: { wm in weeklyMeal = wm })
            }
        }
        .sheet(isPresented: $showMealWeek) {
            if let wm = weeklyMeal { MealWeekView(plan: wm) }
        }
        .sheet(item: $thaliMeal) { meal in
            ThaliEditorView(meal: meal, onUpdated: { wm in weeklyMeal = wm })
        }
        .sheet(item: $rescheduleSession) { session in
            RescheduleSheet(session: session, allWeekdays: Weekdays.order) { action in
                await handleReschedule(session, action)
            }
        }
        .sheet(isPresented: $showFixWeek) {
            if let p = fixPreview {
                FixWeekSheet(preview: p, onConfirm: { await confirmFixWeek() })
            }
        }
        .sheet(item: $detail, onDismiss: {
            if let s = pendingRescheduleAfterDetail {
                pendingRescheduleAfterDetail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rescheduleSession = s }
            }
        }) { d in
            WorkoutDetailSheet(
                data: d,
                onComplete: d.sessionId == nil ? nil : { Task { await completeBySessionId(d.sessionId!) } },
                onSkip: d.sessionId == nil ? nil : { Task { await skipBySessionId(d.sessionId!) } },
                onReschedule: d.sessionId == nil ? nil : { pendingRescheduleAfterDetail = sessionById(d.sessionId!) },
                onRegenerate: d.sessionId == nil ? nil : { Task { await regenerateBySessionId(d.sessionId!) } }
            )
        }
        .confirmationDialog("Adjust your week", isPresented: $showAdjust, titleVisibility: .visible) {
            ForEach(adjustOptions, id: \.0) { opt in
                Button(opt.1) { Task { await applyStrategy(opt.0) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSignInGate, onDismiss: runPendingPremiumActionIfAuthed) {
            SignInGateView(onAuthenticated: {}).environment(state)
        }
        .sheet(isPresented: $showWorkoutReminders) {
            ReminderSettingsView(kinds: [.workout])
        }
        .sheet(isPresented: $showMealReminders) {
            ReminderSettingsView(kinds: [.breakfast, .lunch, .dinner])
        }
        .celebration(trigger: confettiTrigger)
    }

    // MARK: - Premium gating (guests get a sign-in gate)

    /// Run a premium action if entitled; otherwise present the sign-in gate and
    /// resume the action after a successful sign-in.
    private func requirePlanAccess(_ action: @escaping () -> Void) {
        switch EntitlementService.shared.planAccess(isAuthenticated: state.isAuthenticated) {
        case .allowed, .needsSubscription:
            // Internal/TestFlight: subscription placeholder is active, so don't
            // block testing. Real IAP gating will branch on .needsSubscription.
            action()
        case .needsSignIn:
            pendingPremiumAction = action
            showSignInGate = true
        }
    }

    private func runPendingPremiumActionIfAuthed() {
        guard state.isAuthenticated, let action = pendingPremiumAction else {
            pendingPremiumAction = nil
            return
        }
        pendingPremiumAction = nil
        // Small delay so the gate sheet finishes dismissing before the next sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { action() }
    }

    private func openPlanner() { requirePlanAccess { showPlanner = true } }
    private func openMealPlanner() { requirePlanAccess { showMealPlanner = true } }

    private func celebrate() {
        Haptics.success()
        confettiTrigger += 1
    }

    /// "Remind me" for the workout — opens the workout reminder scheduler.
    private var remindMeButton: some View {
        Button { showWorkoutReminders = true } label: {
            Label("Remind me", systemImage: "bell")
        }
        .buttonStyle(PillButtonStyle(filled: false))
    }

    /// "Set meal reminders" for the meal card.
    private var mealRemindersButton: some View {
        Button { showMealReminders = true } label: {
            Label("Set meal reminders", systemImage: "bell")
        }
        .buttonStyle(PillButtonStyle(filled: false))
    }

    private let adjustOptions: [(String, String)] = [
        ("move_today", "Move it to today"),
        ("shorter", "Create a shorter version"),
        ("rebalance", "Fix my remaining week"),
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
                    .foregroundStyle(AppConfig.useDemoData ? .white : .white.opacity(0.8))
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
        if let sa = standalone {
            standaloneCard(sa)
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
                    viewFullWorkoutButton(extra: s.exercises.count - 3) { detail = WorkoutDetailData(session: s) }
                }
                Text(s.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 10) {
                    if s.status == "completed" {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.success.opacity(0.18)))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Button {
                            Task { await completeScheduled(s) }
                        } label: { Label("Mark completed", systemImage: "checkmark.circle") }
                            .buttonStyle(PillButtonStyle(filled: true))
                        Button { rescheduleSession = s } label: { Text("Skip / Reschedule") }
                            .buttonStyle(PillButtonStyle(filled: false))
                    }
                    remindMeButton
                    Button { openPlanner() } label: { Text("Regenerate / change") }
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
                Button { openPlanner() } label: { Text("Add a workout today") }
                    .buttonStyle(PillButtonStyle(filled: true))
                remindMeButton
            }
        }
    }

    /// A freshly generated single workout (today-only).
    private func standaloneCard(_ sa: StandaloneWorkout) -> some View {
        let done = sa.status == "completed"
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Today’s workout", systemImage: "figure.run")
                    Spacer()
                    if done {
                        statusBadge("completed")
                    } else {
                        Text("Just for today").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
                Text(sa.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    metaChip("\(sa.durationMin) min", "clock")
                    metaChip(sa.location.capitalized, "mappin.and.ellipse")
                    metaChip("~\(sa.estimatedCalories) kcal", "flame")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sa.main.prefix(3)) { ex in exerciseRow(ex) }
                    viewFullWorkoutButton(extra: sa.main.count - 3) { detail = WorkoutDetailData(standalone: sa) }
                }
                Text(sa.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 10) {
                    Button {
                        Task { await completeStandalone(sa) }
                    } label: {
                        Label(done ? "Completed" : "Mark completed",
                              systemImage: done ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(PillButtonStyle(filled: true)).disabled(done)
                    remindMeButton
                    Button { openPlanner() } label: { Text("Generate another") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
                .padding(.top, 4)
            }
        }
    }

    private func completeStandalone(_ sa: StandaloneWorkout) async {
        if let u = await plans.completeStandalone(sa.id) { withAnimation { standalone = u } }
        celebrate()
        flash("Nice work — that’s another day your body and focus will thank you for.")
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
                    viewFullWorkoutButton(extra: t.workout.main.count - 3) { detail = WorkoutDetailData(generated: t.workout) }
                }
                Text(t.workout.coachNote).font(.footnote).italic().foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 10) {
                    Button { openPlanner() } label: { Text("Generate today’s workout") }
                        .buttonStyle(PillButtonStyle(filled: true))
                    HStack(spacing: 10) {
                        Button {
                            workoutDone = true
                            celebrate()
                            flash("Nice work — that’s another day your body and focus will thank you for.")
                        } label: {
                            Label(workoutDone ? "Completed" : "Mark completed",
                                  systemImage: workoutDone ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(PillButtonStyle(filled: false)).disabled(workoutDone)
                        Button { showAdjust = true } label: { Text("Skip / Adjust") }
                            .buttonStyle(PillButtonStyle(filled: false))
                    }
                    remindMeButton
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
                        .onTapGesture { if let s { detail = WorkoutDetailData(session: s) } }
                    }
                }

                HStack(spacing: 14) {
                    countLabel("\(plan.completedCount)", "done", Theme.success)
                    countLabel("\(plan.plannedCount)", "to go", .white.opacity(0.8))
                    if plan.skippedCount > 0 { countLabel("\(plan.skippedCount)", "skipped", Theme.warning) }
                }
                .font(.footnote)

                Text("Tap any day to reschedule it.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 10) {
                    Button { Task { await openFixWeek() } } label: {
                        Label("Fix my remaining week", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(PillButtonStyle(filled: false))
                    Button { openPlanner() } label: { Text("Edit week") }
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
                    countLabel("\(plan.completedCount)", "done", Theme.success)
                    countLabel("\(plan.plannedCount)", "to go", .white.opacity(0.8))
                    if plan.missedCount > 0 { countLabel("\(plan.missedCount)", "missed", Theme.warning) }
                }
                .font(.footnote)
                Button { openPlanner() } label: { Text("Plan your week") }
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
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                        Text(msg).font(.footnote).foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warning.opacity(0.12)))
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
        if let wm = weeklyMeal {
            weeklyMealCard(wm)
        } else {
            mealCTACard()
        }
    }

    // MARK: - Weekly meal template (Phase 2)

    private func weeklyMealCard(_ wm: WeeklyMealPlanDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    cardTitle("Today’s meals", systemImage: "fork.knife")
                    Spacer()
                    Text("\(wm.dailyKcal) kcal")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                }
                if let day = wm.today() {
                    ForEach(day.meals) { meal in
                        mealRow(meal, remainingSwaps: wm.remainingSwaps)
                        if meal.id != day.meals.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("\(wm.remainingSwaps) of \(wm.swapLimit) meal swaps left this week")
                }
                .font(.caption).foregroundStyle(Theme.nutritionAccent)

                HStack(spacing: 10) {
                    Button { showMealWeek = true } label: { Text("See full week") }
                        .buttonStyle(PillButtonStyle(filled: false))
                    Button { openMealWizard() } label: { Text("Edit plan") }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
                mealRemindersButton
            }
        }
    }

    private func mealRow(_ meal: MealDTO, remainingSwaps: Int) -> some View {
        let completed = meal.status == "completed"
        let skipped = meal.status == "skipped"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SymbolBadge(systemName: mealSlotIcon(meal.slot), gradient: Theme.nutritionGradient, size: 38)
                    .opacity(skipped ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.slot.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(skipped ? Theme.textTertiary : .white)
                    Text("\(meal.kcal) kcal · \(meal.proteinG)g protein")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                }
                Spacer()
                if completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    Menu {
                        Button { Task { await completeWeeklyMeal(meal.id) } } label: { Label("Mark completed", systemImage: "checkmark.circle") }
                        Button { thaliMeal = meal } label: { Label("Build your thali", systemImage: "slider.horizontal.3") }
                        Button { Task { await regenerateWeeklyMeal(meal.id) } } label: { Label("Swap meal (\(remainingSwaps) left)", systemImage: "arrow.triangle.2.circlepath") }
                        Button(role: .destructive) { Task { await skipWeeklyMeal(meal.id) } } label: { Label("Skip", systemImage: "xmark.circle") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            // Food-level detail.
            ForEach(meal.portions) { p in
                HStack(spacing: 8) {
                    Circle().fill(Theme.nutritionAccent.opacity(0.6)).frame(width: 5, height: 5)
                    Text(p.name).font(.caption).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(p.grams))g · \(p.kcal) kcal")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                }
                .padding(.leading, 50)
            }
            Button { thaliMeal = meal } label: {
                Label("Build your thali", systemImage: "slider.horizontal.3")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.nutritionAccent)
            }
            .buttonStyle(.plain).padding(.leading, 50)
        }
    }

    private func mealSlotIcon(_ slot: String) -> String {
        switch slot {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.stars.fill"
        default: return "leaf.fill"
        }
    }

    private func openMealWizard() { requirePlanAccess { showMealWizard = true } }

    private func completeWeeklyMeal(_ id: String) async {
        if let p = await mealTemplate.completeMeal(id) {
            withAnimation { weeklyMeal = p }
            let allDone = p.today()?.meals.allSatisfy { $0.status == "completed" } ?? false
            if allDone { celebrate(); flash("All meals logged — perfect nutrition day. 🎉") }
            else { Haptics.success(); flash("Logged. Protein first — you’re on target.") }
        }
    }

    private func skipWeeklyMeal(_ id: String) async {
        Haptics.warning()
        if let p = await mealTemplate.skipMeal(id) { withAnimation { weeklyMeal = p } }
        flash("Meal skipped — adjust the rest of your day if hungry.")
    }

    private func regenerateWeeklyMeal(_ id: String) async {
        do {
            let p = try await mealTemplate.regenerateMeal(id)
            withAnimation { weeklyMeal = p }
            Haptics.impact()
            flash("Meal swapped — \(p.remainingSwaps) of \(p.swapLimit) swaps left this week.")
        } catch {
            if case APIError.server(let status, let message) = error, status == 409 {
                flash(message)   // quota exhausted
            } else {
                flash("Couldn’t swap that meal — try again.")
            }
        }
    }

    private func mealCard(_ mp: MealPlanResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    cardTitle("Today’s meals", systemImage: "fork.knife")
                    Spacer()
                    Text("\(mp.dailyKcal.formatted()) kcal")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                }
                ForEach(mp.meals) { meal in
                    MealTargetRow(
                        icon: mealIcon(for: meal),
                        title: meal.name,
                        kcal: meal.kcal,
                        proteinG: meal.proteinG,
                        carbsG: meal.carbsG,
                        fatG: meal.fatG,
                        fiberG: meal.fiberG,
                        status: meal.status,
                        suggestion: meal.suggestions.first,
                        onComplete: { Task { await completeMeal(meal) } },
                        onSkip: { Task { await skipMeal(meal) } }
                    )
                    if meal.id != mp.meals.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
                Text(mp.coachNote).font(.caption).italic().foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button { openMealPlanner() } label: { Text("Adjust meal targets") }
                    .buttonStyle(PillButtonStyle(filled: false))
                mealRemindersButton
            }
        }
    }

    private func mealCTACard() -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SymbolBadge(systemName: "fork.knife", gradient: Theme.nutritionGradient, size: 40)
                    Text("Meal targets")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
                Text("Plan your meals")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("A repeating weekly plan with real portions — rice 150g, chicken 180g — built around your preferences.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button { openMealWizard() } label: { Text("Plan my meals") }
                    .buttonStyle(PillButtonStyle(filled: true))
                mealRemindersButton
            }
        }
    }

    /// Maps a meal name to a fitting SF Symbol for its icon badge.
    private func mealIcon(for m: MealTarget) -> String {
        let n = m.name.lowercased()
        if n.contains("break") { return "sunrise.fill" }
        if n.contains("lunch") { return "sun.max.fill" }
        if n.contains("dinner") { return "moon.stars.fill" }
        if n.contains("snack") { return "leaf.fill" }
        return "fork.knife"
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

    /// Opens the full workout-detail sheet. Shows the remaining-exercise count
    /// when there are more than the 3 previewed.
    private func viewFullWorkoutButton(extra: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(extra > 0 ? "View full workout · +\(extra) more" : "View full workout")
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.primaryAccent)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

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
            .foregroundStyle(filled ? Theme.onAccent : .white)
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "completed": return ("Completed", Theme.success)
            case "skipped": return ("Skipped", Theme.warning)
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
        case "completed": return Theme.success
        case "today": return .white
        case "missed": return Theme.warning
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
        case "completed": return Theme.success
        case "skipped": return Theme.warning
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
        case "completed": return Theme.success
        case "skipped": return Theme.warning
        default: return .white.opacity(0.3)
        }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium)).foregroundStyle(Theme.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.bottom, 24).padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    /// Match by LOCAL DATE, not weekday — so today's card always reflects the
    /// real calendar day even across week rollovers. Falls back to weekday for
    /// older cached plans whose dates predate this fix.
    private func todaySession(_ plan: WeeklyWorkoutPlan) -> WeeklySession? {
        let today = Weekdays.todayISO()
        return plan.sessions.first { $0.date == today }
            ?? plan.sessions.first { $0.weekday == Weekdays.today() }
    }

    private func sessionById(_ id: String) -> WeeklySession? {
        weeklyPlan?.sessions.first { $0.id == id }
    }

    private func completeBySessionId(_ id: String) async {
        if let s = sessionById(id) { await completeScheduled(s) }
    }

    private func skipBySessionId(_ id: String) async {
        Haptics.warning()
        if let u = await plans.skipSession(id) { withAnimation { weeklyPlan = u } }
        flash("Skipped — no problem. Use “Fix my remaining week” to rebalance.")
    }

    private func regenerateBySessionId(_ id: String) async {
        Haptics.impact()
        if let u = await plans.regenerateSession(id) { withAnimation { weeklyPlan = u } }
        flash("Fresh workout ready for that day.")
    }

    /// Foreground/midnight refresh. A full reload on a new day (so "today" rolls
    /// over correctly); a lighter plan refresh otherwise.
    private func refreshForCurrentDay() async {
        if Weekdays.todayISO() != loadedDay {
            await load()
        } else {
            await reloadPlans()
        }
    }

    private func load() async {
        isLoading = true
        loadedDay = Weekdays.todayISO()
        demoWeekly = nil
        workoutDone = false
        standalone = nil
        let result = await coach.today(profile: state.profile, timelineMonths: nil, missedWeekday: nil)
        let plan = await plans.currentWeeklyPlan()
        let meals = await plans.currentMealPlan()
        let sa = await plans.currentStandalone()
        let wm = await mealTemplate.current()
        withAnimation(.easeOut(duration: 0.3)) {
            today = result
            weeklyPlan = plan
            mealPlan = meals
            standalone = sa
            weeklyMeal = wm
            isLoading = false
        }
        await PhoneWatchBridge.shared.syncToday()   // push today's plan to a paired Watch
    }

    /// Refresh only the persisted plans (after a planner sheet closes).
    private func reloadPlans() async {
        let plan = await plans.currentWeeklyPlan()
        let meals = await plans.currentMealPlan()
        let sa = await plans.currentStandalone()
        let wm = await mealTemplate.current()
        withAnimation {
            weeklyPlan = plan ?? weeklyPlan
            mealPlan = meals ?? mealPlan
            standalone = sa ?? standalone
            weeklyMeal = wm ?? weeklyMeal
        }
    }

    private func completeScheduled(_ s: WeeklySession) async {
        if let updated = await plans.completeSession(s.id) {
            withAnimation { weeklyPlan = updated }
            // Workout completed → celebrate. Cancel today's nag.
            NotificationService.shared.cancelToday(.workout)
            if updated.plannedCount == 0, updated.completedCount > 0 {
                celebrate()   // weekly target achieved
                flash("Weekly target hit — every planned session done. 🎉")
            } else {
                celebrate()
                flash("Done — that’s consistency compounding. Nicely played.")
            }
        } else {
            flash("Done — that’s consistency compounding. Nicely played.")
        }
    }

    private func handleReschedule(_ s: WeeklySession, _ action: RescheduleAction) async {
        Haptics.warning()
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
            await openFixWeek()
        }
    }

    /// Fetch a "Fix my remaining week" preview and present the confirmation sheet.
    private func openFixWeek() async {
        guard let preview = await plans.previewFixWeek() else {
            flash("No active plan to fix yet.")
            return
        }
        fixPreview = preview
        showFixWeek = true
    }

    /// Apply the previewed fix after the user confirms.
    private func confirmFixWeek() async {
        Haptics.impact()
        if let u = await plans.applyFixWeek() { withAnimation { weeklyPlan = u } }
        flash("Your remaining week is sorted — nothing piles up.")
    }

    private func completeMeal(_ m: MealTarget) async {
        if let u = await plans.completeMeal(m.id) {
            withAnimation { mealPlan = u }
            NotificationService.shared.cancelToday(mealReminderKind(for: m))
            let allDone = !u.meals.isEmpty && u.meals.allSatisfy { $0.status == "completed" }
            if allDone {
                celebrate()
                flash("All meals logged — that’s a perfect nutrition day. 🎉")
            } else {
                Haptics.success()
                flash("\(m.name) logged. Protein first — you’re on target.")
            }
        } else {
            Haptics.success()
            flash("\(m.name) logged. Protein first — you’re on target.")
        }
    }

    private func skipMeal(_ m: MealTarget) async {
        Haptics.warning()
        if let u = await plans.skipMeal(m.id) { withAnimation { mealPlan = u } }
        flash("\(m.name) skipped — adjust the rest of the day if you’re hungry.")
    }

    /// Best-effort mapping of a meal to its reminder kind by name.
    private func mealReminderKind(for m: MealTarget) -> ReminderKind {
        let n = m.name.lowercased()
        if n.contains("break") { return .breakfast }
        if n.contains("lunch") { return .lunch }
        return .dinner
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
