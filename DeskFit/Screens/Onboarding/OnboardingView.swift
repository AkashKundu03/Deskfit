import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    var onFinish: () -> Void

    var body: some View {
        @Bindable var state = state

        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    GlassCard {
                        VStack(spacing: 14) {
                            HStack {
                                Text("Name").foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                TextField("Your name", text: $state.profile.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 180)
                            }
                            intStepperRow("Age", value: $state.profile.age, range: 15...90, unit: "yrs")
                            pickerRow("Gender", selection: $state.profile.gender, options: Gender.allCases) { $0.label }
                            doubleStepperRow("Height", value: $state.profile.heightCm, range: 120...220, step: 1, unit: "cm", format: "%.0f")
                            doubleStepperRow("Weight", value: $state.profile.weightKg, range: 35...200, step: 0.5, unit: "kg", format: "%.1f")
                            doubleStepperRow("Target weight", value: $state.profile.targetWeightKg, range: 35...200, step: 0.5, unit: "kg", format: "%.1f")
                        }
                    }

                    GlassCard {
                        VStack(spacing: 14) {
                            pickerRow("Activity level", selection: $state.profile.activity, options: ActivityLevel.allCases) { $0.label }
                            pickerRow("Main goal", selection: $state.profile.goal, options: Goal.allCases) { $0.label }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Medical flags").font(.headline).foregroundStyle(.white)
                            flagGrid
                        }
                    }

                    GlassCard {
                        VStack(spacing: 14) {
                            pickerRow("Bowel frequency", selection: $state.gutAnswers.bowelFrequency, options: BowelFrequency.allCases) { $0.label }
                            pickerRow("Stool consistency", selection: $state.gutAnswers.stoolConsistency, options: StoolConsistency.allCases) { $0.label }
                            pickerRow("Bloating", selection: $state.gutAnswers.bloatingFrequency, options: BloatingFrequency.allCases) { $0.label }
                            doubleStepperRow("Water intake", value: $state.gutAnswers.waterLitres, range: 0...6, step: 0.1, unit: "L", format: "%.1f")
                            doubleStepperRow("Sleep", value: $state.gutAnswers.sleepHours, range: 3...12, step: 0.5, unit: "hr", format: "%.1f")
                        }
                    }

                    Button("Generate Report", action: onFinish)
                        .buttonStyle(PillButtonStyle(filled: true))
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tell us about you")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("A short check-in to build your wellness report.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private var flagGrid: some View {
        @Bindable var state = state
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) {
            ForEach(MedicalFlag.allCases) { flag in
                let selected = state.profile.medicalFlags.contains(flag)
                Button {
                    toggleFlag(flag)
                } label: {
                    Text(flag.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.08)),
                            in: Capsule()
                        )
                        .foregroundStyle(selected ? Theme.onAccent : .white)
                }
            }
        }
    }

    private func toggleFlag(_ flag: MedicalFlag) {
        if state.profile.medicalFlags.contains(flag) {
            state.profile.medicalFlags.remove(flag)
            if state.profile.medicalFlags.isEmpty {
                state.profile.medicalFlags = [.none]
            }
        } else {
            if flag == .none {
                state.profile.medicalFlags = [.none]
            } else {
                state.profile.medicalFlags.remove(.none)
                state.profile.medicalFlags.insert(flag)
            }
        }
    }

    private func intStepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("\(value.wrappedValue) \(unit)").foregroundStyle(.white).monospacedDigit()
            Stepper("", value: value, in: range).labelsHidden().tint(Theme.accent)
        }
    }

    private func doubleStepperRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, format: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("\(String(format: format, value.wrappedValue)) \(unit)")
                .foregroundStyle(.white).monospacedDigit()
            Stepper("", value: value, in: range, step: step).labelsHidden().tint(Theme.accent)
        }
    }

    private func pickerRow<T: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
    }
}
