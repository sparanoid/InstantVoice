import SwiftUI

/// The practice half of a try-it-out step: the sample to read aloud, then the shortcut and the text area that the
/// dictation pastes into.
struct OnboardingPracticeSection: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    @Binding var text: String
    let onShortcutChanged: () -> Void

    @State private var isFieldFocused = false

    var body: some View {
        Section {
            Text(LocalizedStringKey(step.sampleText))
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } header: {
            Text(LocalizedStringKey(step.sampleLabel))
        }

        Section {
            LabeledContent("Recording Shortcut") {
                OnboardingShortcutSetupView(
                    action: shortcutAction,
                    onShortcutChanged: onShortcutChanged
                )
            }

            if step.layout == .transform {
                textArea
            }
        } footer: {
            Text(LocalizedStringKey(hasShortcut ? step.configuredInstruction : "Choose a shortcut to get started."))
        }
        .onAppear {
            focusFieldIfReady()
        }
        .onChange(of: hasShortcut) { _, _ in
            focusFieldIfReady()
        }
    }

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(LocalizedStringKey(step.fieldPlaceholder))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }

            OnboardingLockedTextEditor(
                text: $text,
                isEnabled: hasShortcut,
                isFocused: $isFieldFocused
            )
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(height: 104)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isFieldFocused ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor),
                    lineWidth: isFieldFocused ? 2 : 1
                )
        )
        .opacity(hasShortcut ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.18), value: hasShortcut)
        .animation(.easeInOut(duration: 0.12), value: isFieldFocused)
        .padding(.vertical, 4)
    }

    /// Dictation pastes into the focused view, so the text area takes focus once a shortcut exists.
    private func focusFieldIfReady() {
        guard hasShortcut else {
            isFieldFocused = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isFieldFocused = true
        }
    }
}
