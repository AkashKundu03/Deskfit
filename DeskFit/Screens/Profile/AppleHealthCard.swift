import SwiftUI
import UIKit

/// Profile card for the optional Apple Health connection. Connecting and syncing
/// are separate, explicit opt-ins. Raw data stays on-device; only daily
/// aggregates are uploaded, and only while sync is on.
struct AppleHealthCard: View {
    @State private var health = HealthService.shared
    @State private var connecting = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch health.connectionState {
                case .unavailable:
                    Text("Apple Health isn’t available on this device. DeskFit works fully without it.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                case .notConnected:
                    notConnected
                case .connected:
                    connected
                }
            }
        }
        .task { await health.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: "heart.fill", gradient: Theme.energyGradient, size: 30)
            Text("Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Spacer()
            if health.connectionState == .connected {
                Label("Connected", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
            }
        }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Apple Health for better adaptation — workouts, steps, energy, sleep and recovery signals. It’s optional and you can disconnect anytime.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                connecting = true
                Task { _ = await health.connect(); connecting = false }
            } label: {
                HStack(spacing: 8) {
                    if connecting { ProgressView().tint(Theme.onAccent) }
                    Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                }
            }
            .buttonStyle(PillButtonStyle(filled: true))
            .disabled(connecting)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let agg = health.todayAggregate, agg.hasAnyData {
                HStack(spacing: 8) {
                    if let s = agg.steps { snapshot("\(s)", "steps") }
                    if let e = agg.activeEnergyKcal { snapshot("\(e)", "kcal") }
                    if let sl = agg.sleepMinutes { snapshot(sleepText(sl), "sleep") }
                    if let r = agg.restingHR { snapshot("\(r)", "rest HR") }
                }
            } else {
                Text("No Health data yet today.").font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            Text("Last updated \(lastUpdatedText)")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))

            Toggle(isOn: Binding(get: { health.syncEnabled }, set: { health.setSync($0) })) {
                Text("Sync daily insights to DeskFit").font(.subheadline).foregroundStyle(.white)
            }
            .tint(Theme.primaryAccent)

            Text("Raw health data stays on your device. Only daily summaries are shared, and only while this is on.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Manage in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.primaryAccent)
                Spacer()
                Button("Disconnect") { health.disconnect() }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
            }
            Text("To fully revoke access, use Settings › Privacy & Security › Health › DeskFit.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
    }

    private func snapshot(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }

    private func sleepText(_ minutes: Int) -> String { "\(minutes / 60)h \(minutes % 60)m" }

    private var lastUpdatedText: String {
        guard let d = health.lastUpdated else { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
