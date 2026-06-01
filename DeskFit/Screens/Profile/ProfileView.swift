import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
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
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(state.profile.age) yrs • \(state.profile.goal.label)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 24)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Body").font(.headline).foregroundStyle(.white)
                            row("Gender", state.profile.gender.label)
                            row("Height", String(format: "%.0f cm", state.profile.heightCm))
                            row("Weight", String(format: "%.1f kg", state.profile.weightKg))
                            row("Target", String(format: "%.1f kg", state.profile.targetWeightKg))
                            row("Activity", state.profile.activity.label)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Lifestyle").font(.headline).foregroundStyle(.white)
                            row("Water", String(format: "%.1f L", state.gutAnswers.waterLitres))
                            row("Sleep", String(format: "%.1f hr", state.gutAnswers.sleepHours))
                            row("Bowel", state.gutAnswers.bowelFrequency.label)
                            row("Stool", state.gutAnswers.stoolConsistency.label)
                            row("Bloating", state.gutAnswers.bloatingFrequency.label)
                        }
                    }

                    Button("Retake assessment") { showResetConfirm = true }
                        .buttonStyle(PillButtonStyle(filled: false))
                        .padding(.top, 8)

                    Text(HealthReport.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .confirmationDialog("Retake assessment?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { state.resetAssessment() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears your saved answers and report.")
        }
    }

    private var initials: String {
        let parts = state.profile.name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return chars.isEmpty ? "D" : chars.joined().uppercased()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.semibold)
        }
    }
}
