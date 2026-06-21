import SwiftUI

/// Assessment onboarding — exactly ONE question per screen (14 questions).
/// Drives the same AppState bindings and the same generateReport() calculations.
struct AssessmentFlowView: View {
    @Environment(AppState.self) private var state
    var onFinish: () -> Void

    @State private var index = 0
    private let total = 15

    private var title: String {
        switch index {
        case 0: return "First, what should we call you?"
        case 1: return "First, your age"
        case 2: return "What’s your gender?"
        case 3: return "Your height"
        case 4: return "Where are you starting?"
        case 5: return "What’s your goal weight?"
        case 6: return "How fast do you want to get there?"
        case 7: return "How active are you on most days?"
        case 8: return "How much water do you drink daily?"
        case 9: return "How many hours do you sleep?"
        case 10: return "How often do you have bowel movements?"
        case 11: return "What is your stool consistency?"
        case 12: return "How often do you feel bloated?"
        case 13: return "What is your main goal?"
        default: return "Do any health flags apply to you?"
        }
    }

    private var helper: String {
        switch index {
        case 0: return "We'll use this to personalize your plan."
        case 1: return "This helps DeskFit keep your plan realistic."
        case 2: return "Helps us calculate your metabolism accurately."
        case 3: return "Used for your healthy weight range."
        case 4: return "This helps DeskFit set realistic food and workout targets."
        case 5: return "We’ll keep the plan realistic and avoid extreme targets."
        case 6: return "We’ll keep the pace safe and realistic."
        case 7: return "Think about a typical day, not your best day."
        case 8: return "A rough daily average is fine."
        case 9: return "Your usual nightly sleep."
        case 10: return "A key signal of gut health."
        case 11: return "Pick the closest match."
        case 12: return "Bloating frequency tells us a lot about your gut."
        case 13: return "We'll tailor your priorities around this."
        default: return "Select all that apply, or None. This is not medical advice."
        }
    }

    private var canContinue: Bool {
        switch index {
        case 0: return !state.profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                progressBar

                Spacer(minLength: 8)

                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(helper)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)

                    answerControl
                        .padding(.top, 12)
                }
                .padding(.horizontal, 28)
                .id(index)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity))

                Spacer()

                navBar
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    // MARK: - Header / footer

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack {
                if index > 0 {
                    Button { withAnimation { index -= 1 } } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                Text("\(index + 1) of \(total)")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                // Balance the back chevron so the counter stays centered.
                Image(systemName: "chevron.left").opacity(0)
            }
            ProgressView(value: Double(index + 1), total: Double(total))
                .tint(Theme.accent)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            if index > 0 {
                Button("Back") { withAnimation { index -= 1 } }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
            Button(index == total - 1 ? "See my report" : "Continue") {
                if index == total - 1 {
                    onFinish()
                } else if canContinue {
                    withAnimation { index += 1 }
                }
            }
            .buttonStyle(PillButtonStyle(filled: true))
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - One answer control per question

    @ViewBuilder
    private var answerControl: some View {
        @Bindable var state = state
        switch index {
        case 0:
            TextField("Your name", text: $state.profile.name)
                .multilineTextAlignment(.center)
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .submitLabel(.next)
        case 1:
            WheelValuePicker(
                value: Binding(get: { Double(state.profile.age) },
                               set: { state.profile.age = Int($0.rounded()) }),
                range: 16...80, step: 1, unit: "years", hint: "Scroll to your age.")
        case 2:
            singleSelect($state.profile.gender, Gender.allCases) { $0.label }
        case 3:
            WheelValuePicker(value: $state.profile.heightCm,
                             range: 130...220, step: 1, unit: "cm",
                             hint: "Scroll to your height.")
        case 4:
            WheelValuePicker(value: $state.profile.weightKg,
                             range: 35...180, step: 0.5, unit: "kg",
                             hint: "Pick where you are today.", format: Self.smartFormat)
        case 5:
            WheelValuePicker(value: $state.profile.targetWeightKg,
                             range: 35...180, step: 0.5, unit: "kg",
                             hint: "Now choose where you want to reach.", format: Self.smartFormat)
        case 6:
            WheelValuePicker(
                value: Binding(get: { Double(state.profile.timelineMonths) },
                               set: { state.profile.timelineMonths = Int($0.rounded()) }),
                range: 1...12, step: 1, unit: "months",
                hint: "A steady pace is easier to keep.")
        case 7:
            singleSelect($state.profile.activity, ActivityLevel.allCases) { $0.label }
        case 8:
            WheelValuePicker(value: $state.gutAnswers.waterLitres,
                             range: 0...6, step: 0.1, unit: "litres",
                             hint: "A rough daily average is fine.",
                             format: { String(format: "%.1f", $0) })
        case 9:
            WheelValuePicker(value: $state.gutAnswers.sleepHours,
                             range: 3...12, step: 0.5, unit: "hours",
                             hint: "Your usual nightly sleep.", format: Self.smartFormat)
        case 10:
            singleSelect($state.gutAnswers.bowelFrequency, BowelFrequency.allCases) { $0.label }
        case 11:
            singleSelect($state.gutAnswers.stoolConsistency, StoolConsistency.allCases) { $0.label }
        case 12:
            singleSelect($state.gutAnswers.bloatingFrequency, BloatingFrequency.allCases) { $0.label }
        case 13:
            singleSelect($state.profile.goal, Goal.allCases) { $0.label }
        default:
            flagGrid
        }
    }

    // MARK: - Reusable controls

    /// Shows whole numbers without a trailing ".0" but keeps the half step.
    static let smartFormat: (Double) -> String = { v in
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func singleSelect<T: Hashable & Identifiable>(
        _ selection: Binding<T>,
        _ options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                let selected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(label(option)).fontWeight(.medium)
                        Spacer()
                        if selected { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
                    .background(
                        selected ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(selected ? Theme.onAccent : .white)
                }
            }
        }
    }

    private var flagGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(MedicalFlag.allCases) { flag in
                let selected = state.profile.medicalFlags.contains(flag)
                Button { toggleFlag(flag) } label: {
                    Text(flag.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selected ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(.white.opacity(0.08)),
                            in: Capsule())
                        .foregroundStyle(selected ? Theme.onAccent : .white)
                }
            }
        }
    }

    private func toggleFlag(_ flag: MedicalFlag) {
        if state.profile.medicalFlags.contains(flag) {
            state.profile.medicalFlags.remove(flag)
            if state.profile.medicalFlags.isEmpty { state.profile.medicalFlags = [.none] }
        } else if flag == .none {
            state.profile.medicalFlags = [.none]
        } else {
            state.profile.medicalFlags.remove(.none)
            state.profile.medicalFlags.insert(flag)
        }
    }
}
