import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Reusable visual building blocks for a premium, readable dark UI.
// ─────────────────────────────────────────────────────────────────────────────

/// A rounded gradient icon badge. Use for meal/workout/progress accents so icons
/// read as intentional, not decorative.
struct SymbolBadge: View {
    let systemName: String
    var gradient: LinearGradient = Theme.primaryButtonGradient
    var size: CGFloat = 38
    var iconScale: CGFloat = 0.46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * iconScale, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
    }
}

/// A small labelled macro pill (e.g. "30g · Carbs"). Tinted to its nutrient.
struct MacroPill: View {
    let value: String
    let label: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            Text(value).font(.caption.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
    }
}

/// Full-width gradient CTA. Thin wrapper for consistency where a button isn't
/// using PillButtonStyle directly.
struct GradientActionButton: View {
    let title: String
    var systemImage: String? = nil
    var gradient: LinearGradient = Theme.primaryButtonGradient
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(gradient))
            .foregroundStyle(Theme.onAccent)
            .shadow(color: Theme.primaryAccent.opacity(0.35), radius: 14, y: 6)
        }
    }
}

/// One meal row: gradient icon badge, name, primary kcal · protein, an obvious
/// status/affordance, and (optional) secondary macro pills.
struct MealTargetRow: View {
    let icon: String
    let title: String
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let status: String
    var suggestion: String?
    var onComplete: () -> Void
    var onSkip: () -> Void

    @State private var showMacros = false

    private var isCompleted: Bool { status == "completed" }
    private var isSkipped: Bool { status == "skipped" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SymbolBadge(systemName: icon, gradient: Theme.nutritionGradient, size: 40)
                    .opacity(isSkipped ? 0.4 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSkipped ? Theme.textTertiary : Theme.textPrimary)
                        .strikethrough(isSkipped)
                    HStack(spacing: 6) {
                        Text("\(kcal) kcal").font(.subheadline.weight(.bold)).monospacedDigit()
                        Text("·").foregroundStyle(Theme.textTertiary)
                        Text("\(proteinG)g protein").font(.subheadline).monospacedDigit()
                    }
                    .foregroundStyle(isSkipped ? Theme.textTertiary : Theme.textSecondary)
                }

                Spacer()

                statusControl
            }

            if let suggestion, !isSkipped {
                Text("Try: \(suggestion)")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 52)
            }

            // Secondary macros under a light disclosure — keeps the row clean.
            Button { withAnimation(.snappy) { showMacros.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(showMacros ? "Hide macros" : "Carbs · Fat · Fiber")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showMacros ? 180 : 0))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.nutritionAccent)
                .padding(.leading, 52)
            }
            .buttonStyle(.plain)

            if showMacros {
                HStack(spacing: 8) {
                    MacroPill(value: "\(carbsG)g", label: "Carbs", tint: Theme.nutritionAccent)
                    MacroPill(value: "\(fatG)g", label: "Fat", tint: Theme.secondaryAccent)
                    MacroPill(value: "\(fiberG)g", label: "Fiber", tint: Theme.success)
                }
                .padding(.leading, 52)
            }
        }
    }

    @ViewBuilder private var statusControl: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.success)
        } else {
            Menu {
                Button { onComplete() } label: { Label("Mark completed", systemImage: "checkmark.circle") }
                Button(role: .destructive) { onSkip() } label: { Label("Skip", systemImage: "xmark.circle") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
