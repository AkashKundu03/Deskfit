import SwiftUI

struct WelcomeView: View {
    var onStart: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 24)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 10) {
                    Text("DeskFit")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Premium wellness for the 9-to-5 you.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

                Spacer()

                Button("Begin Assessment", action: onStart)
                    .buttonStyle(PillButtonStyle(filled: true))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
        }
    }
}
