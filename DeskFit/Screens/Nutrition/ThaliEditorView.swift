import SwiftUI

/// "Build your thali" — adjust each portion's grams or swap its food, with live
/// recalculated totals. Every edit calls the backend, which validates against the
/// user's diet/allergens and returns the updated plan.
struct ThaliEditorView: View {
    let meal: MealDTO
    var onUpdated: (WeeklyMealPlanDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    private let service = MealTemplateService()

    @State private var current: MealDTO
    @State private var catalog: [FoodCatalogItem] = []
    @State private var working = false
    @State private var error: String?

    init(meal: MealDTO, onUpdated: @escaping (WeeklyMealPlanDTO) -> Void) {
        self.meal = meal
        self.onUpdated = onUpdated
        _current = State(initialValue: meal)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        totalsCard
                        ForEach(current.portions) { p in portionCard(p) }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(Theme.danger)
                        }
                        Text("Totals update as you adjust. Diet and allergens are always respected.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Build your \(current.slot)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(Theme.primaryAccent) } }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { catalog = await service.catalog() }
        }
        .preferredColorScheme(.dark)
    }

    private var totalsCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Text(current.name).font(.headline).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MacroPill(value: "\(current.kcal)", label: "kcal", tint: Theme.nutritionAccent)
                    MacroPill(value: "\(current.proteinG)g", label: "Protein", tint: Theme.primaryAccent)
                    MacroPill(value: "\(current.carbsG)g", label: "Carbs", tint: Theme.warning)
                    MacroPill(value: "\(current.fatG)g", label: "Fat", tint: Theme.secondaryAccent)
                }
            }
        }
    }

    private func portionCard(_ p: MealPortionDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(p.grams))g · \(p.kcal) kcal")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                }
                // Grams stepper.
                HStack(spacing: 16) {
                    gramsButton("minus", p, delta: -10)
                    Text("\(Int(p.grams)) g").font(.headline).foregroundStyle(.white).monospacedDigit()
                        .frame(minWidth: 70)
                    gramsButton("plus", p, delta: 10)
                    Spacer()
                    swapMenu(p)
                }
            }
            .opacity(working ? 0.6 : 1)
        }
    }

    private func gramsButton(_ symbol: String, _ p: MealPortionDTO, delta: Double) -> some View {
        Button {
            Task { await edit(portionId: p.id, grams: max(5, p.grams + delta), foodSlug: nil) }
        } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.white.opacity(0.1), in: Circle())
        }
        .disabled(working)
    }

    private func swapMenu(_ p: MealPortionDTO) -> some View {
        let options = catalog.filter { $0.category == categoryOf(p.foodSlug) && $0.slug != p.foodSlug }
        return Menu {
            ForEach(options) { food in
                Button(food.name) { Task { await edit(portionId: p.id, grams: nil, foodSlug: food.slug) } }
            }
        } label: {
            Label("Swap", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.primaryAccent)
        }
        .disabled(working || options.isEmpty)
    }

    private func categoryOf(_ slug: String) -> String {
        catalog.first { $0.slug == slug }?.category ?? "protein"
    }

    private func edit(portionId: String, grams: Double?, foodSlug: String?) async {
        working = true; error = nil
        if let plan = await service.editPortion(portionId: portionId, grams: grams, foodSlug: foodSlug) {
            onUpdated(plan)
            if let updated = plan.days.flatMap({ $0.meals }).first(where: { $0.id == current.id }) {
                withAnimation { current = updated }
            }
            Haptics.selection()
        } else {
            error = "That swap isn’t allowed (diet or allergen). Try another."
        }
        working = false
    }
}
