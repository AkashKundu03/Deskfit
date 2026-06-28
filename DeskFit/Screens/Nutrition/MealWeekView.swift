import SwiftUI

/// Read-only 7-day view of the repeating weekly meal template.
struct MealWeekView: View {
    let plan: WeeklyMealPlanDTO
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(plan.days) { day in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(Weekdays.full[day.weekday] ?? day.weekday)
                                        .font(.headline).foregroundStyle(.white)
                                    ForEach(day.meals) { meal in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(meal.slot.capitalized)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Theme.nutritionAccent)
                                                Spacer()
                                                Text("\(meal.kcal) kcal · \(meal.proteinG)g P")
                                                    .font(.caption).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                                            }
                                            Text(meal.portions.map { "\($0.name) \(Int($0.grams))g" }.joined(separator: " · "))
                                                .font(.caption2).foregroundStyle(.white.opacity(0.6))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if meal.id != day.meals.last?.id { Divider().overlay(.white.opacity(0.08)) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Your meal week").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(Theme.primaryAccent) } }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
