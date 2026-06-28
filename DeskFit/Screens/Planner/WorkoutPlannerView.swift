import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// "Generate Workout Plan" — a polished selection flow (plan type, dates,
// location, time, equipment, focus, level) that produces a deterministic workout
// from the coach engine (backend, with local fallback). Premium and demo-ready.
// ─────────────────────────────────────────────────────────────────────────────

struct WorkoutPlannerView: View {
    var initialFocus: String? = nil
    /// Notifies Today with the persisted single ("today only") workout.
    var onTodayWorkout: ((StandaloneWorkout) -> Void)? = nil
    /// Notifies Today so it can reflect the freshly generated weekly plan.
    var onWeeklyCreated: ((WeeklyWorkoutPlan) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    private let coach = CoachService()
    private let plans = PlanService()

    @State private var planType: PlanType = .todayOnly
    @State private var selectedWeekdays: Set<String> = ["Mon", "Wed", "Fri"]
    @State private var location: PlannerLocation = .home
    @State private var time: PlannerTime = .min30
    @State private var equipment: Set<PlannerEquipment> = [.bodyweight]
    @State private var focus: PlannerFocus = .fatLoss
    @State private var level: PlannerLevel = .beginner

    @State private var generating = false
    @State private var result: GeneratedWorkout?
    @State private var weeklyResult: WeeklyWorkoutPlan?
    @State private var completed = false

    // Step-by-step wizard (one question per screen).
    @State private var step = 0

    private enum Step { case planType, days, location, time, equipment, focus, level }
    private var steps: [Step] {
        planType == .weekly
            ? [.planType, .days, .location, .time, .equipment, .focus, .level]
            : [.planType, .location, .time, .equipment, .focus, .level]
    }
    private var current: Step { steps[min(step, steps.count - 1)] }
    private var isLastStep: Bool { step >= steps.count - 1 }
    private var canAdvance: Bool {
        current == .days ? !selectedWeekdays.isEmpty : true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if let weeklyResult {
                    weeklyResultView(weeklyResult)
                } else if let result {
                    resultView(result)
                } else {
                    wizardView
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(hasResult ? "Back" : "Close") {
                        if hasResult { withAnimation { result = nil; weeklyResult = nil } }
                        else { dismiss() }
                    }
                    .tint(Theme.accent)
                }
            }
            .onAppear { if let f = initialFocus, let mapped = PlannerFocus(backend: f) { focus = mapped } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Wizard (one question per screen)

    private var wizardView: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: Double(steps.count))
                .tint(Theme.primaryAccent)
                .padding(.horizontal, 24).padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stepTitle)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let helper = stepHelper {
                        Text(helper).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    stepControl
                        .padding(.top, 12)
                }
                .padding(20)
                .id(step) // re-trigger slide transition per step
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            }

            navBar
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    @ViewBuilder private var stepControl: some View {
        switch current {
        case .planType:
            chipGrid(PlanType.allCases, isSelected: { $0 == planType }) { planType = $0 }
        case .days:
            weekdaySelector
        case .location:
            chipGrid(PlannerLocation.allCases, isSelected: { $0 == location }) { location = $0 }
        case .time:
            chipGrid(PlannerTime.allCases, isSelected: { $0 == time }) { time = $0 }
        case .equipment:
            VStack(alignment: .leading, spacing: 12) {
                Button { selectFullGym() } label: {
                    Label("I have a fully-equipped gym", systemImage: "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.workoutGradient))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                chipGrid(PlannerEquipment.allCases, isSelected: { equipment.contains($0) }) { toggleEquipment($0) }
                Text("Pick any you have — bodyweight is always available.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        case .focus:
            chipGrid(PlannerFocus.allCases, isSelected: { $0 == focus }) { focus = $0 }
        case .level:
            chipGrid(PlannerLevel.allCases, isSelected: { $0 == level }) { level = $0 }
        }
    }

    private var stepTitle: String {
        switch current {
        case .planType: return "Today’s workout, or a full week?"
        case .days: return "Which days will you train?"
        case .location: return "Where are you training?"
        case .time: return "How much time do you have?"
        case .equipment: return "What equipment can you use?"
        case .focus: return "What’s your focus?"
        case .level: return "What’s your level?"
        }
    }

    private var stepHelper: String? {
        switch current {
        case .planType: return "A single session for today, or a distinct workout for each day you pick."
        case .days: return "Pick one or more — each day gets its own workout, spaced for recovery."
        case .location: return nil
        case .time: return nil
        case .equipment: return "Choose as many as you like."
        case .focus: return "We’ll bias the exercises toward this."
        case .level: return nil
        }
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
            if isLastStep {
                Button { Task { await generate() } } label: {
                    HStack(spacing: 8) {
                        if generating { ProgressView().tint(Theme.onAccent) }
                        Text(generating ? "Building…" : (planType == .weekly ? "Generate week plan" : "Generate workout"))
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(generating || (planType == .weekly && selectedWeekdays.isEmpty))
            } else {
                Button("Next") { withAnimation { step += 1 } }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func selectFullGym() {
        Haptics.selection()
        equipment = Set(PlannerEquipment.allCases.filter { $0 != .none })
    }

    // MARK: - Result

    private func resultView(_ w: GeneratedWorkout) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(w.focusLabel)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(Theme.onAccent)
                        Text(w.title).font(.title2.weight(.bold)).foregroundStyle(.white)
                        HStack(spacing: 8) {
                            metaChip("\(w.durationMin) min", "clock")
                            metaChip(w.location.capitalized, "mappin.and.ellipse")
                            metaChip("~\(w.estimatedCalories) kcal", "flame")
                        }
                        Text("This becomes today’s workout on your dashboard.")
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                }

                exerciseGroup("Warm-up", w.warmup)
                exerciseGroup("Workout", w.main)

                GlassCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "quote.bubble.fill").foregroundStyle(Theme.accent)
                        Text(w.coachNote).font(.callout).foregroundStyle(.white.opacity(0.9))
                    }
                }

                Button { completed = true } label: {
                    Label(completed ? "Completed" : "Mark completed",
                          systemImage: completed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(completed)

                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
            .padding(20)
        }
    }

    private func exerciseGroup(_ title: String, _ items: [CoachExerciseItem]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                ForEach(items) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ex.name).font(.body.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            Text(ex.detail).font(.subheadline).foregroundStyle(Theme.accent).monospacedDigit()
                        }
                        Text(ex.cue).font(.caption).foregroundStyle(.white.opacity(0.65))
                        HStack(spacing: 10) {
                            Text(ex.rest).font(.caption2).foregroundStyle(.white.opacity(0.5))
                            if let alt = ex.lowImpactAlternative {
                                Text("· Easier: \(alt)").font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    if ex.id != items.last?.id {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
    }

    // MARK: - Reusable controls

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipGrid<T: PlannerOption>(_ items: [T], isSelected: @escaping (T) -> Bool,
                                            action: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                Button { action(item) } label: {
                    Text(item.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected(item) ? Theme.accent : .white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(isSelected(item) ? 0 : 0.12), lineWidth: 1)
                        )
                        .foregroundStyle(isSelected(item) ? Theme.onAccent : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func segmented<T: PlannerOption>(_ items: [T], selection: Binding<T>,
                                             label: @escaping (T) -> String) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Button { selection.wrappedValue = item } label: {
                    Text(label(item))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selection.wrappedValue.id == item.id ? Theme.accent : .white.opacity(0.08))
                        )
                        .foregroundStyle(selection.wrappedValue.id == item.id ? Theme.onAccent : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaChip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - Logic

    private func toggleEquipment(_ e: PlannerEquipment) {
        if equipment.contains(e) { equipment.remove(e) } else { equipment.insert(e) }
        if equipment.isEmpty { equipment = [.bodyweight] }
    }

    private func generate() async {
        generating = true
        let eq = equipment.isEmpty ? ["bodyweight"] : equipment.map { $0.raw }

        if planType == .weekly {
            let req = CreateWeeklyPlanRequest(
                selectedDays: Weekdays.order.filter { selectedWeekdays.contains($0) },
                location: location.raw,
                durationMin: time.rawValue,
                equipment: eq,
                level: level.raw,
                goal: CoachGoal.from(state.profile.goal).rawValue
            )
            let plan = await plans.createWeeklyPlan(req)
            onWeeklyCreated?(plan)
            withAnimation { weeklyResult = plan; generating = false }
            return
        }

        let req = GenerateWorkoutRequest(
            location: location.raw,
            durationMin: time.rawValue,
            equipment: eq,
            focus: focus.raw,
            level: level.raw,
            title: nil
        )
        let w = await coach.generate(req)
        // Persist it as today's standalone workout so its completion survives.
        let saved = await plans.saveStandalone(StandaloneWorkoutRequest(
            location: location.raw, durationMin: time.rawValue, equipment: eq,
            focus: focus.raw, level: level.raw, title: nil, date: Weekdays.todayISO()))
        onTodayWorkout?(saved)
        withAnimation { result = w; generating = false; completed = false }
    }

    // MARK: - Computed

    private var hasResult: Bool { result != nil || weeklyResult != nil }
    private var navTitle: String {
        if weeklyResult != nil { return "Your week" }
        if result != nil { return "Your workout" }
        return "Plan your workout"
    }

    // MARK: - Weekday selector

    private var weekdaySelector: some View {
        HStack(spacing: 8) {
            ForEach(Weekdays.order, id: \.self) { wd in
                let on = selectedWeekdays.contains(wd)
                Button {
                    Haptics.selection()
                    if on { selectedWeekdays.remove(wd) } else { selectedWeekdays.insert(wd) }
                } label: {
                    Text(wd)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(on ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(.white.opacity(0.08)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(on ? 0 : 0.12), lineWidth: 1)
                        )
                        .foregroundStyle(on ? Theme.onAccent : .white)
                        .scaleEffect(on ? 1.06 : 1)
                        .shadow(color: on ? Theme.primaryAccent.opacity(0.5) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
            }
        }
    }

    // MARK: - Weekly result (grouped by day)

    private func weeklyResultView(_ plan: WeeklyWorkoutPlan) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your week is ready")
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("\(plan.sessions.count) sessions · each day a distinct workout, spaced for recovery.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(plan.sessions) { s in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(Weekdays.full[s.weekday] ?? s.weekday)
                                    .font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text(s.focusLabel)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.accent))
                                    .foregroundStyle(Theme.onAccent)
                            }
                            Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                            HStack(spacing: 8) {
                                metaChip("\(s.durationMin) min", "clock")
                                metaChip(s.location.capitalized, "mappin.and.ellipse")
                                metaChip("~\(s.estimatedCalories) kcal", "flame")
                            }
                            ForEach(s.exercises.prefix(3)) { ex in
                                HStack(spacing: 10) {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.accent)
                                    Text(ex.name).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Text(ex.detail).font(.caption).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                                }
                            }
                            if s.exercises.count > 3 {
                                Text("+ \(s.exercises.count - 3) more")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }

                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            .padding(20)
        }
    }
}

// MARK: - Planner option types

protocol PlannerOption: Identifiable, Hashable, CaseIterable {
    var label: String { get }
}

enum PlanType: String, PlannerOption {
    case todayOnly, weekly
    var id: String { rawValue }
    var label: String { self == .todayOnly ? "Today only" : "Weekly plan" }
}

enum PlannerLocation: String, PlannerOption {
    case gym, home, outdoor, office, mixed
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .gym: return "Gym"; case .home: return "Home"; case .outdoor: return "Outdoor"
        case .office: return "Desk reset"; case .mixed: return "Mixed"
        }
    }
}

enum PlannerTime: Int, PlannerOption {
    case min10 = 10, min20 = 20, min30 = 30, min45 = 45, min60 = 60
    var id: Int { rawValue }
    var label: String { "\(rawValue) min" }
}

enum PlannerEquipment: String, PlannerOption {
    case bodyweight, dumbbells, barbell, bench, resistanceBand, pullupBar, treadmill, cycle
    case kettlebell, cable, machine, smithMachine, rowingMachine, jumpRope, medicineBall, trx
    case none
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .bodyweight: return "Bodyweight"; case .dumbbells: return "Dumbbells"
        case .barbell: return "Barbell"; case .bench: return "Bench"
        case .resistanceBand: return "Band"; case .pullupBar: return "Pull-up bar"
        case .treadmill: return "Treadmill"; case .cycle: return "Cycle"
        case .kettlebell: return "Kettlebell"; case .cable: return "Cable"
        case .machine: return "Machines"; case .smithMachine: return "Smith machine"
        case .rowingMachine: return "Rower"; case .jumpRope: return "Jump rope"
        case .medicineBall: return "Med ball"; case .trx: return "TRX"
        case .none: return "None"
        }
    }
}

enum PlannerFocus: String, PlannerOption {
    case fatLoss, strength, muscleBuilding, mobility, cardio, balanced
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .fatLoss: return "Fat loss"; case .strength: return "Strength"
        case .muscleBuilding: return "Muscle"; case .mobility: return "Mobility"
        case .cardio: return "Cardio"; case .balanced: return "Balanced"
        }
    }
    init?(backend: String) {
        guard let v = PlannerFocus(rawValue: backend) else { return nil }
        self = v
    }
}

enum PlannerLevel: String, PlannerOption {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String { rawValue.capitalized }
}
