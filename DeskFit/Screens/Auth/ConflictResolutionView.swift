import SwiftUI

/// Shown when an Apple account already has a saved profile AND this device also
/// has a local assessment. The user decides which wins — we never silently
/// overwrite backend data. Default (and most prominent) is "Use Apple account".
struct ConflictResolutionView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// Called after the user resolves (used backend / replaced). Not called on cancel.
    var onResolved: () -> Void
    /// Called when the user cancels (stays where they were).
    var onCancel: () -> Void

    @State private var working = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 10) {
                    Text("We found an existing DeskFit profile")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("This Apple account already has a saved assessment. Which one would you like to keep?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        working = true
                        state.useBackendProfile()
                        Haptics.success()
                        onResolved(); dismiss()
                    } label: {
                        Label("Use Apple account profile", systemImage: "icloud.fill")
                    }
                    .buttonStyle(PillButtonStyle(filled: true))

                    Button {
                        working = true
                        Task {
                            await state.uploadLocalAssessment()
                            Haptics.success()
                            onResolved(); dismiss()
                        }
                    } label: {
                        Label("Replace with this device’s assessment", systemImage: "iphone.and.arrow.forward")
                    }
                    .buttonStyle(PillButtonStyle(filled: false))

                    Button("Cancel") { onCancel(); dismiss() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                }
                .disabled(working)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .interactiveDismissDisabled(true)
        .preferredColorScheme(.dark)
    }
}
