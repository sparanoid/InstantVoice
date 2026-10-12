import SwiftUI

struct OnboardingContextAwarenessScreen: View {
    let onSkipSetup: (() -> Void)?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                secondaryTitle: onSkipSetup == nil ? nil : "Skip Setup",
                onSecondary: onSkipSetup,
                onBack: onBack,
                onPrimary: onContinue
            )
        ) {
            OnboardingPageHeader(
                systemImage: OnboardingStage.contextAwareness.systemImage,
                tint: OnboardingStage.contextAwareness.tint,
                title: OnboardingStage.contextAwareness.title,
                subtitle: OnboardingStage.contextAwareness.subtitle
            )
        } content: {
            Section {
                ForEach(StarterModeCatalog.templates) { template in
                    HStack(spacing: 12) {
                        OnboardingIconTile(systemImage: template.icon.value, tint: tint(for: template.kind), size: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(template.name))
                                .font(.system(size: 13, weight: .medium))

                            Text(template.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("Modes")
            } footer: {
                Text("Press Option 1–9 while recording to switch modes.")
            }
        }
    }

    private func tint(for kind: StarterModeKind) -> Color {
        switch kind {
        case .clean:
            return .blue
        case .enhance:
            return .purple
        case .email:
            return .indigo
        case .rewrite:
            return .teal
        case .assistant:
            return .orange
        }
    }
}
