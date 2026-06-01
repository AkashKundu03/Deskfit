import SwiftUI

struct ReportView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            AppBackground()

            if let report = state.report {
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        GlassCard {
                            VStack(spacing: 10) {
                                row("BMI", String(format: "%.1f", report.bmi))
                                row("Category", report.bmiCategory)
                                divider
                                row("BMR", "\(Int(report.bmr.rounded())) kcal")
                                row("TDEE", "\(Int(report.tdee.rounded())) kcal")
                                divider
                                row("Healthy weight",
                                    String(format: "%.1f – %.1f kg", report.healthyWeightLowKg, report.healthyWeightHighKg))
                                row("Calorie target",
                                    String(format: "%.0f – %.0f kcal", report.calorieTargetLow, report.calorieTargetHigh))
                            }
                        }

                        GlassCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Gut health score").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                    Text("\(report.gutScore)/100")
                                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Educational gut age").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                    Text("\(report.gutAge) yrs")
                                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top 3 priorities").font(.headline).foregroundStyle(.white)
                                ForEach(Array(report.priorityActions.enumerated()), id: \.offset) { idx, action in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(idx + 1)")
                                            .font(.subheadline.bold())
                                            .frame(width: 24, height: 24)
                                            .background(Theme.accent, in: Circle())
                                            .foregroundStyle(.black)
                                        Text(action)
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        Text(HealthReport.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                Text("No report yet — complete onboarding.")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var header: some View {
        Text("Your wellness report")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.semibold).monospacedDigit()
        }
    }
}
