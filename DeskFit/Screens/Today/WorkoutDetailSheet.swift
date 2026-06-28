import SwiftUI

/// The full workout for one day — warm-up, every exercise with sets/reps, rest,
/// cues, and easier alternatives. Replaces the dead "+ N more" text. Opened by
/// tapping any scheduled day or "View full workout". For a real plan session it
/// also offers complete / skip / reschedule.
struct WorkoutDetailData: Identifiable, Equatable {
    let id: String
    let title: String
    let focusLabel: String
    let durationMin: Int
    let location: String
    let estimatedCalories: Int
    let warmup: [CoachExerciseItem]
    let exercises: [CoachExerciseItem]
    let coachNote: String
    let status: String?      // session lifecycle; nil for a one-off generated workout
    let sessionId: String?   // present only for persisted plan sessions
    let dateLabel: String?

    init(session s: WeeklySession) {
        id = s.id
        title = s.title
        focusLabel = s.focusLabel
        durationMin = s.durationMin
        location = s.location
        estimatedCalories = s.estimatedCalories
        warmup = s.warmup
        exercises = s.exercises
        coachNote = s.coachNote
        status = s.status
        sessionId = s.id
        dateLabel = WorkoutDetailData.label(weekday: s.weekday, isoDate: s.date)
    }

    init(generated w: GeneratedWorkout, dateLabel: String? = "Today") {
        id = w.id
        title = w.title
        focusLabel = w.focusLabel
        durationMin = w.durationMin
        location = w.location
        estimatedCalories = w.estimatedCalories
        warmup = w.warmup
        exercises = w.main
        coachNote = w.coachNote
        status = nil
        sessionId = nil
        self.dateLabel = dateLabel
    }

    init(standalone s: StandaloneWorkout) {
        id = s.id
        title = s.title
        focusLabel = s.focusLabel
        durationMin = s.durationMin
        location = s.location
        estimatedCalories = s.estimatedCalories
        warmup = s.warmup
        exercises = s.main
        coachNote = s.coachNote
        status = s.status == "planned" ? nil : s.status
        sessionId = nil      // standalone actions live on the card, not the sheet
        dateLabel = "Today"
    }

    private static func label(weekday: String, isoDate: String) -> String {
        let full = Weekdays.full[weekday] ?? weekday
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: isoDate) else { return full }
        let out = DateFormatter()
        out.locale = .current
        out.dateFormat = "MMM d"
        return "\(full) · \(out.string(from: d))"
    }
}

struct WorkoutDetailSheet: View {
    let data: WorkoutDetailData
    var onComplete: (() -> Void)?
    var onSkip: (() -> Void)?
    var onReschedule: (() -> Void)?
    var onRegenerate: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var isCompleted: Bool { data.status == "completed" }
    private var isSkipped: Bool { data.status == "skipped" }
    private var canAct: Bool { data.sessionId != nil && !isCompleted }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if !data.warmup.isEmpty { group("Warm-up", data.warmup) }
                        group("Workout", data.exercises)
                        if !data.coachNote.isEmpty {
                            GlassCard {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "quote.bubble.fill").foregroundStyle(Theme.primaryAccent)
                                    Text(data.coachNote).font(.callout).foregroundStyle(.white.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if canAct { actions }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.primaryAccent)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let dateLabel = data.dateLabel {
                Text(dateLabel.uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.primaryAccent)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(data.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let status = data.status { statusBadge(status) }
            }
            HStack(spacing: 8) {
                chip(data.focusLabel, "bolt.fill")
                chip("\(data.durationMin) min", "clock")
                chip(data.location.capitalized, "mappin.and.ellipse")
                chip("~\(data.estimatedCalories) kcal", "flame")
            }
        }
    }

    private func group(_ title: String, _ items: [CoachExerciseItem]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                ForEach(items) { ex in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ex.name).font(.body.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            Text(ex.detail).font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.primaryAccent).monospacedDigit()
                        }
                        if !ex.cue.isEmpty {
                            Text(ex.cue).font(.caption).foregroundStyle(.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 12) {
                            if !ex.rest.isEmpty {
                                Label(ex.rest, systemImage: "timer")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
                            }
                            if let alt = ex.lowImpactAlternative, !alt.isEmpty {
                                Label("Easier: \(alt)", systemImage: "arrow.down.right.circle")
                                    .font(.caption2).foregroundStyle(Theme.success.opacity(0.9))
                            }
                        }
                    }
                    if ex.id != items.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { onComplete?(); dismiss() } label: {
                Label("Mark completed", systemImage: "checkmark.circle")
            }
            .buttonStyle(PillButtonStyle(filled: true))
            Button { onReschedule?(); dismiss() } label: { Text("Reschedule / make lighter") }
                .buttonStyle(PillButtonStyle(filled: false))
            if onRegenerate != nil {
                Button { onRegenerate?(); dismiss() } label: {
                    Label("Regenerate this day", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PillButtonStyle(filled: false))
            }
            Button(role: .destructive) { onSkip?(); dismiss() } label: { Text("Skip this session") }
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.danger).padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "completed": return ("Completed", Theme.success)
            case "skipped": return ("Skipped", Theme.warning)
            case "rescheduled": return ("Moved", Theme.primaryAccent)
            default: return ("Planned", .white.opacity(0.7))
            }
        }()
        return Text(label).font(.caption2.weight(.bold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white.opacity(0.85))
    }
}
