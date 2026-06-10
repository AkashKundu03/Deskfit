import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// "Generate Workout Plan" — a polished selection flow (plan type, dates,
// location, time, equipment, focus, level) that produces a deterministic workout
// from the coach engine (backend, with local fallback). Premium and demo-ready.
// ─────────────────────────────────────────────────────────────────────────────

struct WorkoutPlannerView: View {
    var initialFocus: String? = nil

    @Environment(\.dismiss) private var dismiss
    private let coach = CoachService()

    @State private var planType: PlanType = .todayOnly
    @State private var dayCount = 3
    @State private var location: PlannerLocation = .home
    @State private var time: PlannerTime = .min20
    @State private var equipment: Set<PlannerEquipment> = [.bodyweight]
    @State private var focus: PlannerFocus = .fatLoss
    @State private var level: PlannerLevel = .beginner

    @State private var generating = false
    @State private var result: GeneratedWorkout?
    @State private var completed = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if let result {
                    resultView(result)
                } else {
                    formView
                }
            }
            .navigationTitle(result == nil ? "Plan your workout" : "Your workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? "Close" : "Back") {
                        if result == nil { dismiss() } else { withAnimation { result = nil } }
                    }
                    .tint(Theme.accent)
                }
            }
            .onAppear { if let f = initialFocus, let mapped = PlannerFocus(backend: f) { focus = mapped } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {
                section("Plan") {
                    segmented(PlanType.allCases, selection: $planType) { $0.label }
                    if planType == .weekly {
                        HStack {
                            Text("Days this week").foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Stepper("\(dayCount)", value: $dayCount, in: 1...7)
                                .labelsHidden()
                            Text("\(dayCount)").foregroundStyle(.white).monospacedDigit().frame(width: 24)
                        }
                        .font(.subheadline)
                    }
                }

                section("Where are you training?") {
                    chipGrid(PlannerLocation.allCases, isSelected: { $0 == location }) { location = $0 }
                }

                section("How much time?") {
                    chipGrid(PlannerTime.allCases, isSelected: { $0 == time }) { time = $0 }
                }

                section("What do you have?") {
                    chipGrid(PlannerEquipment.allCases, isSelected: { equipment.contains($0) }) { toggleEquipment($0) }
                    Text("Pick one or more — bodyweight is always available.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                }

                section("Today’s focus") {
                    chipGrid(PlannerFocus.allCases, isSelected: { $0 == focus }) { focus = $0 }
                }

                section("Your level") {
                    segmented(PlannerLevel.allCases, selection: $level) { $0.label }
                }

                Button { Task { await generate() } } label: {
                    HStack(spacing: 8) {
                        if generating { ProgressView().tint(.black) }
                        Text(generating ? "Building…" : "Generate workout")
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(generating)
                .padding(.top, 4)
            }
            .padding(20)
        }
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
                            .foregroundStyle(.black)
                        Text(w.title).font(.title2.weight(.bold)).foregroundStyle(.white)
                        HStack(spacing: 8) {
                            metaChip("\(w.durationMin) min", "clock")
                            metaChip(w.location.capitalized, "mappin.and.ellipse")
                            metaChip("~\(w.estimatedCalories) kcal", "flame")
                        }
                        if planType == .weekly {
                            Text("Added to your week · \(dayCount) day\(dayCount > 1 ? "s" : "")")
                                .font(.footnote).foregroundStyle(Theme.accent)
                        }
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
                        .foregroundStyle(isSelected(item) ? .black : .white)
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
                        .foregroundStyle(selection.wrappedValue.id == item.id ? .black : .white)
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
        let req = GenerateWorkoutRequest(
            location: location.raw,
            durationMin: time.rawValue,
            equipment: eq,
            focus: focus.raw,
            level: level.raw,
            title: nil
        )
        let w = await coach.generate(req)
        withAnimation { result = w; generating = false; completed = false }
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
    case bodyweight, dumbbells, barbell, bench, resistanceBand, pullupBar, treadmill, cycle, none
    var id: String { rawValue }
    var raw: String { rawValue }
    var label: String {
        switch self {
        case .bodyweight: return "Bodyweight"; case .dumbbells: return "Dumbbells"
        case .barbell: return "Barbell"; case .bench: return "Bench"
        case .resistanceBand: return "Band"; case .pullupBar: return "Pull-up bar"
        case .treadmill: return "Treadmill"; case .cycle: return "Cycle"; case .none: return "None"
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
