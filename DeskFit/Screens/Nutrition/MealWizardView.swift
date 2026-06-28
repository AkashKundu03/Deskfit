import SwiftUI

/// Resumable, one-question-per-screen meal wizard. Collects preferences and
/// builds a repeating weekly meal template from the user's nutrition targets.
struct MealWizardView: View {
    let targets: NutritionTargets
    var onCreated: (WeeklyMealPlanDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    private let service = MealTemplateService()

    // Answers
    @State private var mealCount = 3
    @State private var includeSnack = false
    @State private var diet = "vegetarian"
    @State private var proteins: Set<String> = []
    @State private var carbs: Set<String> = []
    @State private var veg: Set<String> = []
    @State private var allergens: Set<String> = []
    @State private var dislikes: Set<String> = []

    @State private var step = 0
    @State private var building = false
    @State private var error: String?

    private let totalSteps = 7

    // Option tables (slugs match the backend catalog).
    private let proteinOpts: [(String, String, String)] = [ // slug, label, minDiet
        ("tofu", "Tofu", "vegan"), ("dal", "Dal", "vegan"), ("chickpeas", "Chickpeas", "vegan"),
        ("rajma", "Rajma", "vegan"), ("soy_chunks", "Soy chunks", "vegan"),
        ("paneer", "Paneer", "veg"), ("whey", "Whey", "veg"), ("greek_yogurt", "Greek yogurt", "veg"),
        ("eggs", "Eggs", "egg"),
        ("chicken", "Chicken", "nonVeg"), ("fish", "Fish", "nonVeg"),
    ]
    private let carbOpts = [("rice", "Rice"), ("roti", "Roti"), ("oats", "Oats"),
                            ("potato", "Potato"), ("sweet_potato", "Sweet potato"),
                            ("quinoa", "Quinoa"), ("poha", "Poha")]
    private let vegOpts = [("broccoli", "Broccoli"), ("spinach", "Spinach"),
                           ("mixed_veg", "Mixed veg"), ("salad", "Salad"), ("green_beans", "Green beans")]
    private let allergenOpts = [("lactose", "Lactose"), ("gluten", "Gluten"), ("nuts", "Nuts"), ("soy", "Soy")]
    private let dislikeOpts = [("broccoli", "Broccoli"), ("spinach", "Spinach"), ("paneer", "Paneer"),
                              ("eggs", "Eggs"), ("fish", "Fish"), ("oats", "Oats"), ("poha", "Poha")]

    private func dietRank(_ d: String) -> Int {
        switch d { case "vegan": return 0; case "vegetarian": return 1; case "eggitarian": return 2; default: return 3 }
    }
    private func foodRank(_ d: String) -> Int {
        switch d { case "vegan": return 0; case "veg": return 1; case "egg": return 2; default: return 3 }
    }
    private var availableProteins: [(String, String, String)] {
        proteinOpts.filter { foodRank($0.2) <= dietRank(diet) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    ProgressView(value: Double(step + 1), total: Double(totalSteps))
                        .tint(Theme.primaryAccent).padding(.horizontal, 24).padding(.top, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            if let helper { Text(helper).font(.subheadline).foregroundStyle(.white.opacity(0.65)) }
                            stepControl.padding(.top, 12)
                            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                        }
                        .padding(20).id(step)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    }
                    navBar
                }
            }
            .navigationTitle("Plan your meals").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.tint(Theme.primaryAccent) } }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    @ViewBuilder private var stepControl: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                chips([("2", "2 meals"), ("3", "3 meals"), ("4", "4 meals")],
                      isOn: { "\(mealCount)" == $0 }) { mealCount = Int($0) ?? 3 }
                Toggle(isOn: $includeSnack) { Text("Include a snack").foregroundStyle(.white) }
                    .tint(Theme.primaryAccent)
            }
        case 1:
            chips([("vegan", "Vegan"), ("vegetarian", "Vegetarian"), ("eggitarian", "Eggitarian"),
                   ("nonVegetarian", "Non-veg"), ("mixed", "Mixed")], isOn: { diet == $0 }) { setDiet($0) }
        case 2:
            multiChips(availableProteins.map { ($0.0, $0.1) }, set: $proteins)
        case 3:
            multiChips(carbOpts, set: $carbs)
        case 4:
            multiChips(vegOpts, set: $veg)
        case 5:
            multiChips(allergenOpts, set: $allergens)
        default:
            multiChips(dislikeOpts, set: $dislikes)
        }
    }

    private var title: String {
        ["How many meals a day?", "What’s your dietary type?", "Which proteins do you like?",
         "Which carbs do you like?", "Vegetables & fiber?", "Any allergies?",
         "Anything you dislike?"][step]
    }
    private var helper: String? {
        ["", "We’ll only use foods that fit.", "Pick a few — we’ll rotate them.",
         "Pick a few staples.", "Pick the veg you enjoy.", "We’ll avoid these completely.",
         "Optional — we’ll leave these out."][step].nilIfEmpty
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            if step > 0 { Button("Back") { withAnimation { step -= 1 } }.buttonStyle(PillButtonStyle(filled: false)) }
            if step == totalSteps - 1 {
                Button { Task { await build() } } label: {
                    HStack(spacing: 8) { if building { ProgressView().tint(Theme.onAccent) }
                        Text(building ? "Building…" : "Build my week") }
                }
                .buttonStyle(PillButtonStyle(filled: true)).disabled(building)
            } else {
                Button("Next") { withAnimation { step += 1 } }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func setDiet(_ d: String) {
        diet = d
        // Drop proteins no longer valid for the new diet.
        let allowed = Set(availableProteins.map { $0.0 })
        proteins = proteins.intersection(allowed)
    }

    private func build() async {
        building = true; error = nil
        let req = CreateMealTemplateRequest(
            mealCount: mealCount, includeSnack: includeSnack, dietaryPref: diet,
            proteinPrefs: Array(proteins), carbPrefs: Array(carbs), fiberPrefs: Array(veg),
            allergens: Array(allergens), dislikes: Array(dislikes),
            dailyKcal: targets.foodTargetKcal, proteinG: targets.proteinG, carbsG: targets.carbsG,
            fatG: targets.fatG, fiberG: targets.fiberG, date: Weekdays.todayISO())
        if let plan = await service.create(req) {
            Haptics.success()
            onCreated(plan)
            dismiss()
        } else {
            building = false
            error = "Couldn’t build your plan. Check your connection and try again."
        }
    }

    // MARK: - Chip helpers

    private func chips(_ opts: [(String, String)], isOn: @escaping (String) -> Bool,
                       select: @escaping (String) -> Void) -> some View {
        FlowChipGrid(opts: opts, isOn: isOn, tap: { select($0) })
    }
    private func multiChips(_ opts: [(String, String)], set: Binding<Set<String>>) -> some View {
        FlowChipGrid(opts: opts, isOn: { set.wrappedValue.contains($0) }) { slug in
            if set.wrappedValue.contains(slug) { set.wrappedValue.remove(slug) } else { set.wrappedValue.insert(slug) }
            Haptics.selection()
        }
    }
}

/// Wrapping selectable chip grid shared by the meal wizard.
private struct FlowChipGrid: View {
    let opts: [(String, String)]
    let isOn: (String) -> Bool
    let tap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(opts, id: \.0) { slug, label in
                let on = isOn(slug)
                Button { tap(slug) } label: {
                    Text(label).font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(on ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(.white.opacity(0.08))))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(on ? 0 : 0.12), lineWidth: 1))
                        .foregroundStyle(on ? Theme.onAccent : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
