import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// "Your plan" report — coach-friendly, not clinical. Primary cards lead with
// what to DO (food target, weight range, priorities). Technical numbers
// (BMI / BMR / TDEE) live only inside "How this is calculated".
// ─────────────────────────────────────────────────────────────────────────────

struct ReportView: View {
    @Environment(AppState.self) private var state
    private let plans = PlanService()

    @State private var weeklyPlan: WeeklyWorkoutPlan?
    @State private var mealPlan: MealPlanResult?

    private var projection: ProgressProjection {
        ProgressProjection.make(profile: state.profile, report: state.report,
                                weeklyPlan: weeklyPlan, mealPlan: mealPlan)
    }

    var body: some View {
        ZStack {
            AppBackground()

            if let report = state.report {
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        coachIntroCard(report)
                        progressCard
                        nextActionCard
                        foodTargetCard(report)
                        weightRangeCard(report)
                        prioritiesCard(report)
                        gutCard(report)
                        howCalculatedCard(report)

                        Text(HealthReport.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            } else {
                Text("No report yet — complete onboarding.")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .task { await loadPlans() }
    }

    private func loadPlans() async {
        let plan = await plans.currentWeeklyPlan()
        let meals = await plans.currentMealPlan()
        withAnimation { weeklyPlan = plan; mealPlan = meals }
    }

    private var header: some View {
        Text("Your plan")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
    }

    // MARK: - Progress

    private var progressCard: some View {
        GlassCard {
            ProgressChartView(projection: projection)
        }
    }

    private var nextActionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your next best step")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(projection.nextBestAction)
                        .font(.callout).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Cards

    private func coachIntroCard(_ r: HealthReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("Here’s what your numbers say — in plain language. Small, steady steps beat big swings. Let’s start with what to do today.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func foodTargetCard(_ r: HealthReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Daily food target", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(r.calorieTargetLow.rounded()))–\(Int(r.calorieTargetHigh.rounded()))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).monospacedDigit()
                    Text("kcal / day").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                Text("Eat in this range to move toward your goal at a pace you can keep — without crashing your energy.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weightRangeCard(_ r: HealthReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Healthy weight range", systemImage: "scalemass")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 14) {
                    stat("You’re at", String(format: "%.0f kg", state.profile.weightKg))
                    stat("Healthy range",
                         String(format: "%.0f–%.0f kg", r.healthyWeightLowKg, r.healthyWeightHighKg))
                }
                Text("A guide, not a verdict — how you feel and your energy matter just as much as the number.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prioritiesCard(_ r: HealthReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Your priorities", systemImage: "list.star")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                ForEach(Array(r.priorityActions.enumerated()), id: \.offset) { idx, action in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: priorityIcon(idx))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent.opacity(0.15), in: Circle())
                        Text(action)
                            .font(.subheadline).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func gutCard(_ r: HealthReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Digestion & energy", systemImage: "leaf")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 14) {
                    stat("Gut score", "\(r.gutScore)/100")
                    stat("Gut age", "\(r.gutAge) yrs")
                }
                Text("A friendly snapshot of digestion habits. Water, fiber and sleep move this the fastest.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func howCalculatedCard(_ r: HealthReport) -> some View {
        GlassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    howRow("Body mass index (BMI)", String(format: "%.1f · %@", r.bmi, r.bmiCategory))
                    howRow("Resting energy (BMR)", "\(Int(r.bmr.rounded())) kcal")
                    howRow("Maintenance (TDEE)", "\(Int(r.tdee.rounded())) kcal")
                    Text("BMI is a rough screen, not a diagnosis. Your plan is built from your maintenance energy and goal.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 8)
            } label: {
                Text("How this is calculated")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .tint(Theme.accent)
        }
    }

    // MARK: - Pieces

    private var greeting: String {
        let name = state.profile.name.isEmpty ? "there" : state.profile.name
        return "You’ve got this, \(name)."
    }

    private func priorityIcon(_ idx: Int) -> String {
        ["drop.fill", "figure.walk", "fork.knife", "bed.double.fill", "heart.fill"][idx % 5]
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    private func howRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).monospacedDigit()
        }
    }
}
