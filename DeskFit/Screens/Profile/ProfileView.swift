import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @State private var showResetConfirm = false
    @State private var showLogoutConfirm = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    profileHeader

                    goalCard
                    bodyCard
                    lifestyleCard
                    preferencesCard

                    // Primary action: Logout (only when signed in).
                    if state.isAuthenticated {
                        Button { showLogoutConfirm = true } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(PillButtonStyle(filled: true))
                        .padding(.top, 8)
                    } else {
                        Button { state.requiresAuth = true } label: {
                            Label("Sign in to sync", systemImage: "icloud.and.arrow.up")
                        }
                        .buttonStyle(PillButtonStyle(filled: true))
                        .padding(.top, 8)
                    }

                    // Secondary, low-emphasis action.
                    Button("Retake assessment") { showResetConfirm = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 2)

                    Text(HealthReport.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .confirmationDialog("Log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { state.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your report stays on this device. Sign back in anytime to sync across devices.")
        }
        .confirmationDialog("Retake assessment?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { state.resetAssessment() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your saved answers and report on this device.")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Theme.accent.opacity(0.85))
                .frame(width: 88, height: 88)
                .overlay(
                    Text(initials)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                )
            Text(state.profile.name.isEmpty ? "Welcome" : state.profile.name)
                .font(.title.weight(.semibold)).foregroundStyle(.white)
            HStack(spacing: 8) {
                Image(systemName: state.isAuthenticated ? "checkmark.seal.fill" : "iphone")
                    .font(.caption)
                Text(state.isAuthenticated ? "Synced account" : "On this device")
                    .font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 16)
    }

    // MARK: - Cards

    private var goalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Your goal", "target")
                Text(state.profile.goal.label)
                    .font(.title2.weight(.bold)).foregroundStyle(.white)
                HStack(spacing: 14) {
                    snapshot("Now", String(format: "%.0f kg", state.profile.weightKg))
                    Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.4))
                    snapshot("Target", String(format: "%.0f kg", state.profile.targetWeightKg))
                }
            }
        }
    }

    private var bodyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Body snapshot", "figure.stand")
                HStack(spacing: 12) {
                    snapshot("Age", "\(state.profile.age)")
                    snapshot("Height", String(format: "%.0f cm", state.profile.heightCm))
                    snapshot("Weight", String(format: "%.0f kg", state.profile.weightKg))
                }
                row("Gender", state.profile.gender.label)
                row("Activity", state.profile.activity.label)
            }
        }
    }

    private var lifestyleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Lifestyle", "moon.stars")
                HStack(spacing: 12) {
                    snapshot("Water", String(format: "%.1f L", state.gutAnswers.waterLitres))
                    snapshot("Sleep", String(format: "%.1f hr", state.gutAnswers.sleepHours))
                }
                row("Digestion", state.gutAnswers.bowelFrequency.label)
                row("Comfort", state.gutAnswers.bloatingFrequency.label + " bloating")
            }
        }
    }

    private var preferencesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Health notes", "heart.text.square")
                let flags = state.profile.medicalFlags
                    .filter { $0 != .none }
                    .map { $0.label }
                if flags.isEmpty {
                    Text("No health flags — we’ll keep your plan general and gentle.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowChips(items: flags)
                }
            }
        }
    }

    // MARK: - Pieces

    private func cardHeader(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func snapshot(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var initials: String {
        let parts = state.profile.name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return chars.isEmpty ? "D" : chars.joined().uppercased()
    }
}

/// Simple wrapping chip row for health notes.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
