import SwiftUI

/// Assessment onboarding — exactly ONE question per screen (14 questions).
/// Drives the same AppState bindings and the same generateReport() calculations.
struct AssessmentFlowView: View {
    @Environment(AppState.self) private var state
    var onFinish: () -> Void

    @State private var index = 0
    private let total = 14

    private var title: String {
        switch index {
        case 0: return "What should we call you?"
        case 1: return "How old are you?"
        case 2: return "What is your gender?"
        case 3: return "How tall are you?"
        case 4: return "What is your current weight?"
        case 5: return "What is your target weight?"
        case 6: return "How active are you on most days?"
        case 7: return "How much water do you drink daily?"
        case 8: return "How many hours do you sleep?"
        case 9: return "How often do you have bowel movements?"
        case 10: return "What is your stool consistency?"
        case 11: return "How often do you feel bloated?"
        case 12: return "What is your main goal?"
        default: return "Do any health flags apply to you?"
        }
    }

    private var helper: String {
        switch index {
        case 0: return "We'll use this to personalize your report."
        case 1: return "Used to estimate your gut age and calorie needs."
        case 2: return "Helps us calculate your metabolism accurately."
        case 3: return "Used for your healthy weight range."
        case 4: return "Be honest — this stays private on your device."
        case 5: return "Where you'd like to be. No pressure."
        case 6: return "Think about a typical day, not your best day."
        case 7: return "A rough daily average is fine."
        case 8: return "Your usual nightly sleep."
        case 9: return "A key signal of gut health."
        case 10: return "Pick the closest match."
        case 11: return "Bloating frequency tells us a lot about your gut."
        case 12: return "We'll tailor your priorities around this."
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
            bigStepper(
                value: "\(state.profile.age)",
                unit: "years",
                onDec: { if state.profile.age > 15 { state.profile.age -= 1 } },
                onInc: { if state.profile.age < 90 { state.profile.age += 1 } })
        case 2:
            singleSelect($state.profile.gender, Gender.allCases) { $0.label }
        case 3:
            bigStepper(
                value: String(format: "%.0f", state.profile.heightCm),
                unit: "cm",
                onDec: { if state.profile.heightCm > 120 { state.profile.heightCm -= 1 } },
                onInc: { if state.profile.heightCm < 220 { state.profile.heightCm += 1 } })
        case 4:
            bigStepper(
                value: String(format: "%.1f", state.profile.weightKg),
                unit: "kg",
                onDec: { if state.profile.weightKg > 35 { state.profile.weightKg -= 0.5 } },
                onInc: { if state.profile.weightKg < 200 { state.profile.weightKg += 0.5 } })
        case 5:
            bigStepper(
                value: String(format: "%.1f", state.profile.targetWeightKg),
                unit: "kg",
                onDec: { if state.profile.targetWeightKg > 35 { state.profile.targetWeightKg -= 0.5 } },
                onInc: { if state.profile.targetWeightKg < 200 { state.profile.targetWeightKg += 0.5 } })
        case 6:
            singleSelect($state.profile.activity, ActivityLevel.allCases) { $0.label }
        case 7:
            bigStepper(
                value: String(format: "%.1f", state.gutAnswers.waterLitres),
                unit: "litres",
                onDec: { if state.gutAnswers.waterLitres > 0 { state.gutAnswers.waterLitres -= 0.1 } },
                onInc: { if state.gutAnswers.waterLitres < 6 { state.gutAnswers.waterLitres += 0.1 } })
        case 8:
            bigStepper(
                value: String(format: "%.1f", state.gutAnswers.sleepHours),
                unit: "hours",
                onDec: { if state.gutAnswers.sleepHours > 3 { state.gutAnswers.sleepHours -= 0.5 } },
                onInc: { if state.gutAnswers.sleepHours < 12 { state.gutAnswers.sleepHours += 0.5 } })
        case 9:
            singleSelect($state.gutAnswers.bowelFrequency, BowelFrequency.allCases) { $0.label }
        case 10:
            singleSelect($state.gutAnswers.stoolConsistency, StoolConsistency.allCases) { $0.label }
        case 11:
            singleSelect($state.gutAnswers.bloatingFrequency, BloatingFrequency.allCases) { $0.label }
        case 12:
            singleSelect($state.profile.goal, Goal.allCases) { $0.label }
        default:
            flagGrid
        }
    }

    // MARK: - Reusable controls

    private func bigStepper(value: String, unit: String, onDec: @escaping () -> Void, onInc: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                circleButton("minus", action: onDec)
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(unit).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
                .frame(minWidth: 130)
                circleButton("plus", action: onInc)
            }
        }
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.1), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
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
                        selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(selected ? .black : .white)
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
                            selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.08)),
                            in: Capsule())
                        .foregroundStyle(selected ? .black : .white)
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
