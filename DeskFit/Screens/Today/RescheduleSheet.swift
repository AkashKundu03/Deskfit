import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Skip / Reschedule bottom sheet — replaces the old generic confirmation dialog.
// Supportive, no-guilt tone. Offers: mark skipped, reschedule to another day,
// shorter version today, or rebalance the rest of the week.
// ─────────────────────────────────────────────────────────────────────────────

enum RescheduleAction {
    case skip
    case reschedule(String)   // target weekday
    case shorter
    case rebalance
}

struct RescheduleSheet: View {
    let session: WeeklySession
    let allWeekdays: [String]
    var onAction: (RescheduleAction) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickingDay = false
    @State private var working = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pickingDay ? "Move to which day?" : "Life happens")
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text(pickingDay
                             ? "Pick a new day for “\(session.title)”. I’ll keep the rest of your week intact."
                             : "No guilt here — pick what fits today and we’ll keep your week on track.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    if pickingDay {
                        dayPicker
                    } else {
                        optionRow("calendar.badge.clock", "Reschedule to another day",
                                  "Move it — e.g. \(Weekdays.full[session.weekday] ?? session.weekday) → another day") {
                            withAnimation { pickingDay = true }
                        }
                        optionRow("bolt.heart", "Make today lighter",
                                  "A shorter version of the same focus.") {
                            run(.shorter)
                        }
                        optionRow("wand.and.stars", "Fix my remaining week",
                                  "Spread remaining sessions so nothing piles up.") {
                            run(.rebalance)
                        }
                        optionRow("xmark.circle", "Mark skipped",
                                  "That’s okay. You can fix your week later.") {
                            run(.skip)
                        }
                    }

                    if working { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }

                    Button(pickingDay ? "Back" : "Cancel") {
                        if pickingDay { withAnimation { pickingDay = false } } else { dismiss() }
                    }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .disabled(working)
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var dayPicker: some View {
        let options = allWeekdays.filter { $0 != session.weekday }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
            ForEach(options, id: \.self) { wd in
                Button { run(.reschedule(wd)) } label: {
                    Text(Weekdays.full[wd] ?? wd)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
    }

    private func optionRow(_ icon: String, _ title: String, _ subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func run(_ action: RescheduleAction) {
        working = true
        Task {
            await onAction(action)
            working = false
            dismiss()
        }
    }
}
