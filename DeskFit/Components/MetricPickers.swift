import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Native wheel metric picker for the questionnaire — replaces plus/minus
// steppers. Feels like setting time in the iOS Alarm app: scroll the wheel to
// the value, with the selection shown large above it. The wheel provides iOS's
// built-in detent haptics natively.
// ─────────────────────────────────────────────────────────────────────────────

struct WheelValuePicker: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String
    /// Short coach hint shown under the wheel (e.g. "Pick where you are today.").
    var hint: String? = nil
    /// Formats the big value + wheel rows.
    var format: (Double) -> String = { String(Int($0.rounded())) }

    private var options: [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    private var selectedIndex: Binding<Int> {
        Binding(
            get: {
                let i = Int(((value - range.lowerBound) / step).rounded())
                return min(max(i, 0), options.count - 1)
            },
            set: { value = range.lowerBound + Double($0) * step }
        )
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                // Large, readable selected value.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(format(value))
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .animation(.snappy(duration: 0.2), value: value)

                Picker("", selection: selectedIndex) {
                    ForEach(options.indices, id: \.self) { i in
                        Text(format(options[i]))
                            .font(.title3)
                            .foregroundStyle(Theme.textPrimary)
                            .tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .accessibilityLabel("\(unit) picker")
                .accessibilityValue("\(format(value)) \(unit)")

                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// Optional layout wrapper: short title, helper line, and a metric control.
struct MetricQuestionCard<Control: View>: View {
    let title: String
    var helper: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let helper {
                Text(helper)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            control().padding(.top, 8)
        }
    }
}
