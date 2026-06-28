import SwiftUI

/// Account deletion — easy to find, honest, and never blocked by the optional
/// exit reason. Offers "Delete now" and "Schedule in 7 days" (recoverable).
struct DeleteAccountView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var working = false
    @State private var scheduled = false
    @State private var error: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if scheduled {
                            scheduledState
                        } else {
                            intro
                            reasonCard
                            appleNote
                            actions
                            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.tint(Theme.primaryAccent) } }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete your account now?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete now", role: .destructive) { Task { await deleteNow() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all your DeskFit data and signs you out. This can’t be undone.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("We’re sorry to see you go.")
                .font(.title3.weight(.bold)).foregroundStyle(.white)
            Text("Deleting removes your profile, plans, meals and any health summaries from DeskFit and signs you out. If you sign in again later, you’ll start completely fresh. Your raw Apple Health data is never touched.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anything we could’ve done better? (optional)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                TextField("", text: $reason, prompt: Text("Your feedback stays anonymous").foregroundStyle(.white.opacity(0.4)), axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var appleNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Theme.primaryAccent)
            Text("If you subscribed via the App Store, cancel that separately in Settings › Apple ID › Subscriptions — deleting your account here doesn’t cancel an Apple subscription.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                working = true
                Task { let ok = await state.scheduleAccountDeletion(reason: trimmedReason)
                    working = false; if ok { scheduled = true } else { error = "Couldn’t schedule. Try again." } }
            } label: {
                HStack(spacing: 8) { if working { ProgressView().tint(Theme.onAccent) }
                    Label("Schedule deletion in 7 days", systemImage: "calendar.badge.clock") }
            }
            .buttonStyle(PillButtonStyle(filled: true)).disabled(working)

            Button { showDeleteConfirm = true } label: {
                Label("Delete now", systemImage: "trash")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(Theme.danger.opacity(0.55), lineWidth: 1)))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain).disabled(working)
        }
    }

    private var scheduledState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Deletion scheduled", systemImage: "calendar.badge.clock")
                .font(.title3.weight(.bold)).foregroundStyle(Theme.warning)
            Text("Your account will be deleted in 7 days. You can recover it anytime before then by signing in and choosing “Keep my account”.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { _ = await AccountService().cancel(); dismiss() } } label: {
                Label("Keep my account", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PillButtonStyle(filled: true))
            Button("Done") { dismiss() }
                .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    private var trimmedReason: String? {
        let t = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func deleteNow() async {
        working = true
        let ok = await state.deleteAccount(reason: trimmedReason)
        working = false
        if ok { dismiss() } else { error = "Couldn’t delete right now. Check your connection and try again." }
    }
}
