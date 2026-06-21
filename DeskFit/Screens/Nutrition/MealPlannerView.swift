import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// "Plan Meals" — collects meal count + dietary / protein / carb / fiber /
// allergen preferences, then produces a meal-wise MACRO TARGET split (not
// recipes) from the deterministic engine (backend with local fallback).
// ─────────────────────────────────────────────────────────────────────────────

struct MealPlannerView: View {
    let targets: NutritionTargets
    var onCreated: ((MealPlanResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    private let plans = PlanService()

    @State private var mealCount: MealCountOption = .three
    @State private var includeSnack = false
    @State private var diet: DietaryPref = .vegetarian
    @State private var proteins: Set<ProteinPref> = [.paneer, .dal]
    @State private var carbs: Set<CarbPref> = [.rice, .oats]
    @State private var fibers: Set<FiberPref> = [.vegetables]
    @State private var allergens: Set<AllergenPref> = [.none]

    @State private var generating = false
    @State private var result: MealPlanResult?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if let result {
                    resultView(result)
                } else {
                    formView
                }
            }
            .navigationTitle(result == nil ? "Plan your meals" : "Your meal targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? "Close" : "Back") {
                        if result == nil { dismiss() } else { withAnimation { result = nil } }
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daily target")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Text("\(targets.foodTargetKcal.formatted()) kcal · \(targets.proteinG)g protein")
                            .font(.title3.weight(.bold)).foregroundStyle(.white)
                        Text("We’ll split this across your meals.")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }

                section("How many meals?") {
                    segmented(MealCountOption.allCases, selected: { $0 == mealCount }) { mealCount = $0 }
                    Toggle(isOn: $includeSnack) {
                        Text("Add a snack").font(.subheadline).foregroundStyle(.white)
                    }
                    .tint(Theme.accent)
                }

                section("Dietary preference") {
                    chipGrid(DietaryPref.allCases, selected: { $0 == diet }) { diet = $0 }
                }

                section("Protein you like") {
                    chipGrid(ProteinPref.allCases, selected: { proteins.contains($0) }) { toggle(&proteins, $0) }
                }

                section("Carbs you like") {
                    chipGrid(CarbPref.allCases, selected: { carbs.contains($0) }) { toggle(&carbs, $0) }
                }

                section("Fiber you like") {
                    chipGrid(FiberPref.allCases, selected: { fibers.contains($0) }) { toggle(&fibers, $0) }
                }

                section("Allergens / restrictions") {
                    chipGrid(AllergenPref.allCases, selected: { allergens.contains($0) }) { toggleAllergen($0) }
                }

                Button { Task { await generate() } } label: {
                    HStack(spacing: 8) {
                        if generating { ProgressView().tint(Theme.onAccent) }
                        Text(generating ? "Building…" : "Generate meal targets")
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(generating)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - Result

    private func resultView(_ plan: MealPlanResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(plan.dailyKcal.formatted()) kcal / day")
                            .font(.title2.weight(.bold)).foregroundStyle(.white)
                        Text("\(plan.proteinG)g protein · \(plan.carbsG)g carbs · \(plan.fatG)g fat · \(plan.fiberG)g fiber")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }

                ForEach(plan.meals) { meal in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(meal.name).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text("\(meal.kcal) kcal")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent).monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                macroPill("P", meal.proteinG)
                                macroPill("C", meal.carbsG)
                                macroPill("F", meal.fatG)
                                macroPill("Fib", meal.fiberG)
                            }
                            if !meal.suggestions.isEmpty {
                                Text("Try: " + meal.suggestions.joined(separator: "  ·  "))
                                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(meal.coachNote)
                                .font(.caption2).italic().foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }

                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            .padding(20)
        }
    }

    private func macroPill(_ label: String, _ value: Int) -> some View {
        Text("\(label) \(value)g")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white.opacity(0.85)).monospacedDigit()
    }

    // MARK: - Reusable controls

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipGrid<T: PlannerOption>(_ items: [T], selected: @escaping (T) -> Bool,
                                            action: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                Button { action(item) } label: {
                    Text(item.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(selected(item) ? Theme.accent : .white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(selected(item) ? 0 : 0.12), lineWidth: 1))
                        .foregroundStyle(selected(item) ? Theme.onAccent : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func segmented<T: PlannerOption>(_ items: [T], selected: @escaping (T) -> Bool,
                                             action: @escaping (T) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Button { action(item) } label: {
                    Text(item.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(selected(item) ? Theme.accent : .white.opacity(0.08)))
                        .foregroundStyle(selected(item) ? Theme.onAccent : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Logic

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func toggleAllergen(_ a: AllergenPref) {
        if a == .none {
            allergens = [.none]
            return
        }
        allergens.remove(.none)
        if allergens.contains(a) { allergens.remove(a) } else { allergens.insert(a) }
        if allergens.isEmpty { allergens = [.none] }
    }

    private func generate() async {
        generating = true
        let req = CreateMealPlanRequest(
            mealCount: mealCount.rawValue,
            includeSnack: includeSnack,
            dietaryPref: diet.raw,
            proteinPrefs: proteins.map { $0.raw },
            carbPrefs: carbs.map { $0.raw },
            fiberPrefs: fibers.map { $0.raw },
            allergens: allergens.map { $0.raw },
            dailyKcal: targets.foodTargetKcal,
            proteinG: targets.proteinG,
            carbsG: targets.carbsG,
            fatG: targets.fatG,
            fiberG: targets.fiberG
        )
        let plan = await plans.createMealPlan(req)
        onCreated?(plan)
        withAnimation { result = plan; generating = false }
    }
}
