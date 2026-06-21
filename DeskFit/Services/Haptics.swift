import UIKit

/// Lightweight haptic feedback helpers. Centralized so important actions
/// (workout/meal completed, plan generated, rescheduled) feel consistent.
/// All calls are no-ops on devices without a Taptic Engine.
enum Haptics {
    /// Strong positive confirmation — use for completions and achievements.
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    /// Soft warning — use for skips / reschedules.
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }

    /// Medium tap — use for a generated plan or a committed change.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }

    /// Light selection tick.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
