import SwiftUI

/// Premium launch splash. Animates briefly, then transitions into onboarding.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var appear = false
    @State private var glow = false

    var body: some View {
        ZStack {
            AppBackground()

            Circle()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .scaleEffect(glow ? 1.1 : 0.85)

            VStack(spacing: 18) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 24)
                    .scaleEffect(appear ? 1 : 0.7)
                    .opacity(appear ? 1 : 0)

                Text("DeskFit")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                Text("Premium wellness for the 9-to-5 you.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
            // Short, premium transition into onboarding.
            Task {
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                onFinish()
            }
        }
    }
}
