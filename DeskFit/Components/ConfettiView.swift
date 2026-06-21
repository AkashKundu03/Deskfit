import SwiftUI

/// Lightweight, fully native confetti celebration — no third-party package.
/// Driven by a `trigger` value: increment it to fire a burst. Renders with a
/// single Canvas + TimelineView so it's cheap and won't crash on older devices.
struct ConfettiView: View {
    /// Increment to fire a new burst.
    var trigger: Int

    private struct Particle {
        let x: CGFloat            // 0...1 horizontal origin
        let angle: CGFloat        // launch angle (radians)
        let speed: CGFloat        // initial speed
        let spin: CGFloat
        let size: CGFloat
        let color: Color
        let wobble: CGFloat
    }

    @State private var particles: [Particle] = []
    @State private var burstStart: Date?
    @State private var lastTrigger = 0

    private let duration: TimeInterval = 1.8
    private let colors: [Color] = [
        Theme.accent, .yellow, .pink, .mint, .orange, .cyan, .white
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    guard let start = burstStart else { return }
                    let elapsed = timeline.date.timeIntervalSince(start)
                    guard elapsed <= duration else { return }
                    let t = CGFloat(elapsed)
                    let gravity: CGFloat = 900

                    for p in particles {
                        let vx = cos(p.angle) * p.speed
                        let vy = sin(p.angle) * p.speed
                        let px = p.x * size.width + vx * t + sin(t * 6 + p.wobble) * p.wobble * 6
                        let py = size.height * 0.32 + vy * t + 0.5 * gravity * t * t
                        let opacity = max(0, 1 - elapsed / duration)

                        var rect = context
                        rect.opacity = opacity
                        rect.translateBy(x: px, y: py)
                        rect.rotate(by: .radians(Double(p.spin * t * 8)))
                        let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.6)
                        rect.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onChange(of: trigger) { _, newValue in
                guard newValue != lastTrigger else { return }
                lastTrigger = newValue
                fire()
            }
        }
        .allowsHitTesting(false)
    }

    private func fire() {
        particles = (0..<70).map { _ in
            Particle(
                x: CGFloat.random(in: 0.25...0.75),
                angle: CGFloat.random(in: (.pi * 1.05)...(.pi * 1.95)) * -1, // upward fan
                speed: CGFloat.random(in: 250...560),
                spin: CGFloat.random(in: -1...1),
                size: CGFloat.random(in: 7...12),
                color: colors.randomElement() ?? Theme.accent,
                wobble: CGFloat.random(in: 0.6...1.6)
            )
        }
        burstStart = Date()
    }
}

extension View {
    /// Overlay a confetti burst that fires whenever `trigger` changes.
    func celebration(trigger: Int) -> some View {
        overlay(ConfettiView(trigger: trigger).allowsHitTesting(false))
    }
}
