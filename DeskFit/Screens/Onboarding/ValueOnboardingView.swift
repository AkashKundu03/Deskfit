import SwiftUI

/// Premium 3-screen value introduction shown before the assessment.
struct ValueOnboardingView: View {
    var onContinue: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            icon: "figure.seated.side",
            title: "Know Your Gut Age",
            body: "DeskFit helps desk-job professionals understand the gut and body signals that quietly build up from a sedentary 9-to-5 lifestyle."
        ),
        Page(
            icon: "chart.bar.doc.horizontal",
            title: "Get Your Personal Report",
            body: "See your BMI, BMR, TDEE, gut score, educational gut age, and the priority actions that matter most for you right now."
        ),
        Page(
            icon: "sun.max.fill",
            title: "Daily Support for Busy Professionals",
            body: "Coming soon: a daily body reset with simple diet and workout support, designed to fit naturally around your desk job."
        )
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        pageView(item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.3), value: page)

                VStack(spacing: 8) {
                    Button(isLast ? "Start Assessment" : "Next") {
                        if isLast {
                            onContinue()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(PillButtonStyle(filled: true))

                    Button("Skip") { onContinue() }
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.subheadline)
                        .opacity(isLast ? 0 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: item.icon)
                .font(.system(size: 84))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.4), radius: 24)

            VStack(spacing: 14) {
                Text(item.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
