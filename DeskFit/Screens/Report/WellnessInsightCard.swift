import SwiftUI

/// "Recovery signals" card — deterministic, baseline-based guidance (never a
/// diagnosis). Shows "Learning your baseline" until there's enough data, and a
/// discreet opt-in nudge toggle.
struct WellnessInsightCard: View {
    @State private var health = HealthService.shared
    @State private var insight: HealthInsight?
    @State private var loading = true
    @State private var showCheckIn = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SymbolBadge(systemName: "waveform.path.ecg", gradient: Theme.progressGradient, size: 32)
                    Text("Recovery signals").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }

                if let insight {
                    content(insight)
                } else if loading {
                    HStack(spacing: 10) { ProgressView().tint(Theme.primaryAccent)
                        Text("Reading your signals…").font(.footnote).foregroundStyle(.white.opacity(0.6)) }
                } else {
                    Text("Connect Apple Health and turn on sync in Profile to see personalized recovery signals.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await reload() }
    }

    @ViewBuilder private func content(_ i: HealthInsight) -> some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor(i.status)).frame(width: 9, height: 9)
            Text(i.title).font(.headline).foregroundStyle(.white)
        }
        Text(i.message).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)

        if !i.factors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(i.factors, id: \.self) { f in
                    Label(f, systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                        .labelStyle(BulletLabelStyle())
                }
            }
        }

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(statusColor(i.status))
            Text(i.action).font(.callout).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(statusColor(i.status).opacity(0.12)))

        Button { showCheckIn = true } label: {
            Label("Daily check-in", systemImage: "checklist")
        }
        .buttonStyle(PillButtonStyle(filled: false))

        Toggle(isOn: Binding(get: { health.recoveryNudgesEnabled }, set: { health.setRecoveryNudges($0) })) {
            Text("Recovery nudges").font(.subheadline).foregroundStyle(.white)
        }
        .tint(Theme.primaryAccent)

        DisclosureGroup {
            Text("We compare today against your own 14–28 day baseline for resting heart rate, HRV and sleep, plus your check-ins. It needs about a week of data first. This is educational guidance, not medical advice.")
                .font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(.top, 6)
        } label: {
            Text("How this is computed").font(.footnote.weight(.semibold)).foregroundStyle(Theme.primaryAccent)
        }
        .tint(Theme.primaryAccent)
        .sheet(isPresented: $showCheckIn) {
            CheckInSheet { e, s, m, st in
                if let updated = await health.submitCheckIn(energy: e, soreness: s, mood: m, stress: st) {
                    insight = updated
                    await health.maybeScheduleNudge(for: updated)
                }
            }
        }
    }

    private func reload() async {
        loading = true
        let i = await health.currentInsight()
        insight = i
        loading = false
        if let i { await health.maybeScheduleNudge(for: i) }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "recoveryLower": return Theme.warning
        case "onTrack": return Theme.success
        default: return Theme.primaryAccent   // learning
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.white.opacity(0.4))
            configuration.title
        }
    }
}

/// Quick 1–5 daily check-in (energy / soreness / mood / stress).
struct CheckInSheet: View {
    var onSave: (Int?, Int?, Int?, Int?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var energy = 3
    @State private var soreness = 2
    @State private var mood = 3
    @State private var stress = 2
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        scale("Energy", "bolt.fill", $energy, low: "Low", high: "High")
                        scale("Soreness", "figure.strengthtraining.traditional", $soreness, low: "None", high: "Very")
                        scale("Mood", "face.smiling", $mood, low: "Low", high: "Great")
                        scale("Stress", "wind", $stress, low: "Calm", high: "Stressed")
                        Button {
                            saving = true
                            Task { await onSave(energy, soreness, mood, stress); dismiss() }
                        } label: {
                            HStack(spacing: 8) { if saving { ProgressView().tint(Theme.onAccent) }; Text("Save check-in") }
                        }
                        .buttonStyle(PillButtonStyle(filled: true)).disabled(saving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Daily check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.tint(Theme.primaryAccent) } }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func scale(_ title: String, _ icon: String, _ value: Binding<Int>, low: String, high: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button { value.wrappedValue = n; Haptics.selection() } label: {
                            Text("\(n)").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(value.wrappedValue == n ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(.white.opacity(0.08))))
                                .foregroundStyle(value.wrappedValue == n ? Theme.onAccent : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack { Text(low); Spacer(); Text(high) }
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
