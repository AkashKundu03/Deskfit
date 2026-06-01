import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 24
    static let accent = Color(red: 0.45, green: 0.95, blue: 0.85)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.10, blue: 0.20),
            Color(red: 0.08, green: 0.20, blue: 0.30),
            Color(red: 0.05, green: 0.30, blue: 0.32)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppBackground: View {
    var body: some View {
        Theme.backgroundGradient.ignoresSafeArea()
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
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if filled {
                        Capsule().fill(Theme.accent)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                }
            )
            .foregroundStyle(filled ? .black : .white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
