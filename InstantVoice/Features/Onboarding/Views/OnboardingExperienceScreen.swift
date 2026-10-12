import SwiftUI

struct OnboardingExperienceScreen: View {
    let step: OnboardingExperienceStep
    let isInIntroPhase: Bool
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    @Binding var text: String
    let isReady: Bool
    let isComplete: Bool
    let onSkipSetup: (() -> Void)?
    let onBackFromIntro: () -> Void
    let onContinueIntro: () -> Void
    let onBackFromPractice: () -> Void
    let onAdvance: () -> Void
    let onShortcutChanged: () -> Void
    let onAppear: () -> Void

    var body: some View {
        Group {
            if isInIntroPhase {
                introPage
                    .transition(.opacity)
            } else {
                practicePage
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isInIntroPhase)
        .onAppear(perform: onAppear)
    }

    private var header: some View {
        OnboardingPageHeader(
            systemImage: step.systemImage,
            tint: tint,
            title: step.title,
            subtitle: step.subtitle
        )
    }

    private var introPage: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                secondaryTitle: onSkipSetup == nil ? nil : "Skip Setup",
                onSecondary: onSkipSetup,
                onBack: onBackFromIntro,
                isPrimaryEnabled: hasShortcut,
                onPrimary: onContinueIntro
            )
        ) {
            header
        } content: {
            Section {
                LabeledContent("Recording Shortcut") {
                    OnboardingShortcutSetupView(
                        action: shortcutAction,
                        onShortcutChanged: onShortcutChanged
                    )
                }
            } footer: {
                Text(
                    hasShortcut
                        ? LocalizedStringKey(
                            "Press the shortcut to start recording, then press it again to stop. You can change it anytime in Settings."
                        )
                        : LocalizedStringKey("Choose a shortcut to get started.")
                )
            }
        }
    }

    private var practicePage: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                secondaryTitle: onSkipSetup == nil ? nil : "Skip Setup",
                onSecondary: onSkipSetup,
                onBack: onBackFromPractice,
                isPrimaryEnabled: isReady && isComplete,
                onPrimary: onAdvance
            )
        ) {
            header
        } content: {
            OnboardingPracticeSection(
                step: step,
                shortcutAction: shortcutAction,
                hasShortcut: hasShortcut,
                text: $text,
                onShortcutChanged: onShortcutChanged
            )
        }
    }

    private var tint: Color {
        switch step.kind {
        case .dictation:
            return .blue
        case .enhance:
            return .purple
        case .email:
            return .indigo
        }
    }
}
