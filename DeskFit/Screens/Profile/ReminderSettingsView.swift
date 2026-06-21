import SwiftUI
import UIKit

/// Notifications & reminders UI. Used from Profile ("Notifications & reminders"),
/// the Today workout card ("Remind me"), and the meal card ("Set meal reminders").
/// Backed entirely by the native NotificationService (UNUserNotificationCenter).
struct ReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = NotificationService.shared

    /// Optionally limit which reminders are shown (e.g. only meals from a meal card).
    var kinds: [ReminderKind] = ReminderKind.allCases

    @State private var denied = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        if denied {
                            permissionBanner
                        }
                        ForEach(kinds) { kind in
                            ReminderRow(kind: kind)
                        }
                        Text("Reminders are scheduled on your device. DeskFit doesn’t use any third-party push service.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await service.refreshStatus()
                denied = service.authorizationStatus == .denied
            }
        }
        .preferredColorScheme(.dark)
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("Enable notifications for DeskFit in Settings to receive reminders.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.orange.opacity(0.12)))
    }
}

/// One reminder: toggle + time picker. Enabling requests permission at the right
/// moment (only when the user opts in), schedules, and persists.
private struct ReminderRow: View {
    let kind: ReminderKind
    @State private var service = NotificationService.shared
    @State private var enabled = false
    @State private var time = Date()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .onChange(of: enabled) { _, on in toggle(on) }
                }
                if enabled {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .tint(Theme.accent)
                        .foregroundStyle(.white)
                        .onChange(of: time) { _, newValue in reschedule(newValue) }
                }
            }
        }
        .onAppear(perform: loadSetting)
    }

    private func loadSetting() {
        let s = service.setting(for: kind)
        enabled = s.enabled
        time = dateFrom(hour: s.hour, minute: s.minute)
    }

    private func toggle(_ on: Bool) {
        if on {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            Task {
                let granted = await service.enable(kind, hour: comps.hour ?? kind.defaultHour, minute: comps.minute ?? 0)
                if granted { Haptics.selection() } else { enabled = false }
            }
        } else {
            service.disable(kind)
            Haptics.selection()
        }
    }

    private func reschedule(_ newTime: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
        service.reschedule(kind, hour: comps.hour ?? kind.defaultHour, minute: comps.minute ?? 0)
        Haptics.selection()
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
