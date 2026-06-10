import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// DeskFit brand mark — a reusable, code-drawn logo. No external asset files, so
// it can never break Assets.xcassets or the Xcode project. Concept: a calm
// rounded "screen" (desk work) cradling a leaf (nutrition) with an upward motion
// arc (fitness/progress). Premium, minimal, Apple-like.
//
// When real logo art arrives, drop it into Assets.xcassets and swap usages — this
// view is the safe placeholder + in-app mark in the meantime.
// ─────────────────────────────────────────────────────────────────────────────

struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Color(red: 0.30, green: 0.78, blue: 0.95)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: max(1, size * 0.02))
                )
                .shadow(color: Theme.accent.opacity(0.45), radius: size * 0.18, x: 0, y: size * 0.08)

            // Upward motion arc (progress / movement).
            Circle()
                .trim(from: 0.05, to: 0.45)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .frame(width: size * 0.62, height: size * 0.62)
                .rotationEffect(.degrees(125))

            // Leaf (nutrition / wellness).
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("DeskFit")
    }
}

/// Brand mark + wordmark, for headers and the splash.
struct BrandLockup: View {
    var size: CGFloat = 40
    var body: some View {
        HStack(spacing: 12) {
            BrandMark(size: size)
            Text("DeskFit")
                .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ZStack {
        AppBackground()
        VStack(spacing: 32) {
            BrandMark(size: 96)
            BrandLockup(size: 44)
        }
    }
}
