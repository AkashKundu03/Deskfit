import SwiftUI

/// "How DeskFit works" — a polished 5-screen intro shown before the account
/// choice and questionnaire. Plain language, SF Symbols, one idea per screen.
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
            icon: "deskclock.fill",
            title: "Built around your workday",
            body: "DeskFit adapts to a busy desk-job schedule — short, doable sessions that fit between meetings."
        ),
        Page(
            icon: "figure.run",
            title: "Today’s workout, or a full week",
            body: "Generate a single workout for today, or a weekly plan across the days you choose."
        ),
        Page(
            icon: "fork.knife",
            title: "Simple meal targets",
            body: "Plan your day by calories, protein, carbs, fat and fiber — with easy portion ideas, not strict recipes."
        ),
        Page(
            icon: "bell.badge.fill",
            title: "Gentle reminders",
            body: "Schedule workout and meal reminders so the right thing happens at the right time."
        ),
        Page(
            icon: "chart.xyaxis.line",
            title: "See your progress",
            body: "Track your path toward your goal weight with a clear, friendly progress chart."
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
                    Button(isLast ? "Get started" : "Next") {
                        Haptics.selection()
                        if isLast { onContinue() } else { withAnimation { page += 1 } }
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
            ZStack {
                Circle()
                    .fill(Theme.primaryAccent.opacity(0.18))
                    .frame(width: 168, height: 168)
                    .blur(radius: 16)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)
                    .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
                Image(systemName: item.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.primaryButtonGradient)
                    .symbolRenderingMode(.hierarchical)
                    .shadow(color: Theme.primaryAccent.opacity(0.5), radius: 18)
            }

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
