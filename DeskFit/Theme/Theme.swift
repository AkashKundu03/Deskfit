import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// DeskFit design tokens — dark-mode-first, premium "AI coach" palette.
//
// Direction: a confident indigo/violet primary with a warm coral energy accent,
// on a deep indigo-black base. Green is RESERVED for success / nutrition /
// completed states only — it is no longer the brand color.
//
//   primaryAccent    → main buttons, selected chips, active tab, chart line,
//                      onboarding highlights, important badges
//   secondaryAccent  → workout energy, streaks, celebration, "start workout"
//   nutritionAccent  → meal/nutrition success (alias of success)
//   success          → completed, checkmarks, "on track"
//   warning          → skipped / rescheduled / behind
//   danger           → logout / destructive
// ─────────────────────────────────────────────────────────────────────────────

enum Theme {
    static let cornerRadius: CGFloat = 24

    // MARK: Brand accents
    /// Indigo/violet — the primary brand accent.
    static let primaryAccent = Color(red: 0.45, green: 0.38, blue: 0.96)
    /// Lighter indigo for gradients / glows.
    static let primaryAccentSoft = Color(red: 0.58, green: 0.50, blue: 1.0)
    /// Electric blue used as the second stop in the primary gradient.
    static let primaryAccentBlue = Color(red: 0.27, green: 0.56, blue: 1.0)
    /// Warm coral — energy / celebration secondary accent.
    static let secondaryAccent = Color(red: 1.0, green: 0.45, blue: 0.40)
    /// Cyan — workout / movement accent.
    static let workoutAccent = Color(red: 0.30, green: 0.80, blue: 0.95)
    /// Warm amber/orange — nutrition / fuel accent (NOT green).
    static let nutritionAccent = Color(red: 1.0, green: 0.66, blue: 0.28)

    // MARK: Status colors
    /// Mint green — success / completed / on-track / healthy. Reserved only.
    static let success = Color(red: 0.27, green: 0.85, blue: 0.60)
    /// Amber — skipped / rescheduled / behind.
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.32)
    /// Soft red — destructive / logout.
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.46)

    // MARK: Text & surfaces
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.5)
    static let divider = Color.white.opacity(0.12)
    /// Text / icon color that sits ON TOP of the primary accent.
    static let onAccent = Color.white

    /// Backward-compatible alias. `Theme.accent` now resolves to the indigo
    /// primary, so existing call sites shift to the new brand automatically.
    static let accent = primaryAccent

    // MARK: Gradients
    /// Deep indigo-black base — not flat black, with a subtle violet lift.
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.05, blue: 0.10),
            Color(red: 0.07, green: 0.07, blue: 0.16),
            Color(red: 0.11, green: 0.07, blue: 0.19)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Primary button / highlight gradient (indigo → electric blue).
    static let primaryButtonGradient = LinearGradient(
        colors: [primaryAccent, primaryAccentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm energy gradient for "start workout" / celebration moments.
    static let energyGradient = LinearGradient(
        colors: [secondaryAccent, Color(red: 1.0, green: 0.60, blue: 0.30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Amber → orange gradient for nutrition / fuel icon badges.
    static let nutritionGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.72, blue: 0.34), Color(red: 1.0, green: 0.52, blue: 0.26)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Blue → cyan gradient for workout / movement icon badges.
    static let workoutGradient = LinearGradient(
        colors: [primaryAccentBlue, workoutAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Violet → cyan gradient for progress moments.
    static let progressGradient = LinearGradient(
        colors: [primaryAccent, workoutAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            // Soft top glow so the dark base reads as crafted, not flat.
            RadialGradient(
                colors: [Theme.primaryAccent.opacity(0.18), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled: Bool = true
    /// Use the warm energy gradient instead of the primary indigo (for
    /// "start workout" / celebration CTAs).
    var energy: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(filled ? Theme.onAccent : Theme.textPrimary)
            .shadow(color: filled ? Theme.primaryAccent.opacity(energy ? 0 : 0.35) : .clear,
                    radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder private var background: some View {
        if filled {
            Capsule().fill(energy ? Theme.energyGradient : Theme.primaryButtonGradient)
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
        }
    }
}
