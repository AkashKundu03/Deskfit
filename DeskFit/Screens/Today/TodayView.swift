import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Hi, \(state.profile.name.isEmpty ? "friend" : state.profile.name)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)

                    if let report = state.report {
                        GlassCard {
                            HStack {
                                stat("BMI", String(format: "%.1f", report.bmi))
                                vDivider
                                stat("TDEE", "\(Int(report.tdee.rounded()))")
                                vDivider
                                stat("Gut", "\(report.gutScore)")
                            }
                        }

                        if let first = report.priorityActions.first {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Today’s focus")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                    Text(first)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        if report.priorityActions.count > 1 {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Your wellness plan")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                    ForEach(Array(report.priorityActions.dropFirst().enumerated()), id: \.offset) { _, action in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "circle")
                                                .foregroundStyle(Theme.accent)
                                            Text(action).foregroundStyle(.white)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        GlassCard {
                            Text("Complete your assessment to see today’s plan.")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var vDivider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 36)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(.white).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}
