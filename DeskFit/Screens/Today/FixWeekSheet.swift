import SwiftUI

/// "Fix my remaining week" — shows a before/after preview and requires
/// confirmation before anything moves. Never moves completed sessions and never
/// reactivates skipped ones (enforced on the backend); when no valid arrangement
/// exists it surfaces the fallback (shorten / skip / choose more days).
struct FixWeekSheet: View {
    let preview: FixWeekResult
    var onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var hasChanges: Bool { !preview.changes.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        if !preview.feasible {
                            infeasibleCard
                        } else if !hasChanges {
                            GlassCard {
                                Label("Your remaining week is already balanced.",
                                      systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(Theme.success)
                            }
                        } else {
                            changesCard
                        }
                        Text("Completed and skipped sessions stay exactly where they are.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                        actions
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Fix my remaining week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private var intro: some View {
        HStack(spacing: 12) {
            SymbolBadge(systemName: "wand.and.stars", gradient: Theme.primaryButtonGradient, size: 40)
            Text("I’ll spread your remaining sessions across your open days so nothing piles up.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var changesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Proposed changes").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                ForEach(preview.changes) { c in
                    HStack(spacing: 10) {
                        Text(c.title).font(.subheadline).foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(Weekdays.full[c.from] ?? c.from).foregroundStyle(.white.opacity(0.6))
                        Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Theme.primaryAccent)
                        Text(Weekdays.full[c.to] ?? c.to).foregroundStyle(Theme.primaryAccent).fontWeight(.semibold)
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var infeasibleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Not enough open days", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warning)
                if let reason = preview.reason {
                    Text(reason).font(.footnote).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Try one of these:").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                fallbackRow("Make a session shorter", "bolt.heart")
                fallbackRow("Skip a session this week", "xmark.circle")
                fallbackRow("Choose more available days", "calendar.badge.plus")
            }
        }
    }

    private func fallbackRow(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.footnote).foregroundStyle(.white.opacity(0.85))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if preview.feasible && hasChanges {
                Button {
                    working = true
                    Task { await onConfirm(); dismiss() }
                } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(Theme.onAccent) }
                        Text("Confirm changes")
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(working)
            }
            Button(preview.feasible && hasChanges ? "Cancel" : "Close") { dismiss() }
                .buttonStyle(PillButtonStyle(filled: false))
                .disabled(working)
        }
        .padding(.top, 4)
    }
}
