import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// DeskFit "Today" — a premium, coach-style dashboard. No technical jargon as
// primary labels (TDEE/BMR live only inside "How this is calculated"). Driven by
// CoachService (backend) with a local fallback, so it's always populated.
// ─────────────────────────────────────────────────────────────────────────────

struct TodayView: View {
    @Environment(AppState.self) private var state
    private let coach = CoachService()

    @State private var today: TodayResponse?
    @State private var weekly: WeeklyPlan?       // local override after "Adjust"
    @State private var workoutDone = false
    @State private var isLoading = true
    @State private var showPlanner = false
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
                        workoutCard(t)
                        weeklyCard(weekly ?? t.weekly)
                        nutritionCard(t.nutrition)
                        if t.consistency.missedDay != nil {
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
                .padding(.bottom, 32)
            }

            if let banner { toast(banner) }
        }
        .task { await load() }
        .sheet(isPresented: $showPlanner) {
            WorkoutPlannerView(initialFocus: today?.workout.focus)
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

    // MARK: - Today's workout card

    private func workoutCard(_ t: TodayResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Today’s workout", systemImage: "figure.run")

                Text(t.workout.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

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
                    ForEach(t.workout.main.prefix(3)) { ex in
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.accent)
                            Text(ex.name).foregroundStyle(.white)
                            Spacer()
                            Text(ex.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                        }
                    }
                    if t.workout.main.count > 3 {
                        Text("+ \(t.workout.main.count - 3) more")
                            .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.vertical, 2)

                Text(t.workout.coachNote)
                    .font(.footnote).italic()
                    .foregroundStyle(.white.opacity(0.7))

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
                        .buttonStyle(PillButtonStyle(filled: false))
                        .disabled(workoutDone)

                        Button { showAdjust = true } label: { Text("Skip / Adjust") }
                            .buttonStyle(PillButtonStyle(filled: false))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Weekly plan card

    private func weeklyCard(_ plan: WeeklyPlan) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("This week’s plan", systemImage: "calendar")

                HStack(spacing: 8) {
                    ForEach(plan.days) { day in
                        VStack(spacing: 6) {
                            Text(day.weekday).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Circle()
                                .fill(statusColor(day.status))
                                .frame(width: 26, height: 26)
                                .overlay(statusGlyph(day.status))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 14) {
                    countLabel("\(plan.completedCount)", "done", Theme.accent)
                    countLabel("\(plan.plannedCount)", "to go", .white.opacity(0.8))
                    if plan.missedCount > 0 {
                        countLabel("\(plan.missedCount)", "missed", .orange)
                    }
                }
                .font(.footnote)

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
                        Text(n.howCalculated.method)
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
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

    // MARK: - Consistency coach card

    private func consistencyCard(_ c: ConsistencyCoach) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Your coach", systemImage: "heart.text.square")
                Text(c.message)
                    .font(.callout).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(c.options) { opt in
                        Button { Task { await applyStrategy(opt.id) } } label: {
                            HStack {
                                Text(opt.label); Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                        }
                        .buttonStyle(PillButtonStyle(filled: false))
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text("Your coach is preparing today’s plan…").foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Reusable pieces

    private func cardTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(filled ? Theme.accent : .white.opacity(0.12)))
            .foregroundStyle(filled ? .black : .white)
    }

    private func metaChip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.bottom, 24).padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        weekly = nil
        workoutDone = false
        let result = await coach.today(profile: state.profile, timelineMonths: nil, missedWeekday: nil)
        withAnimation(.easeOut(duration: 0.3)) {
            today = result
            isLoading = false
        }
    }

    private func applyStrategy(_ strategy: String) async {
        let missed = AppConfig.useDemoData ? AppConfig.demoMissedWeekday : nil
        let res = await coach.adjustWeek(strategy: strategy, missedWeekday: missed)
        withAnimation { weekly = res.weekly }
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
