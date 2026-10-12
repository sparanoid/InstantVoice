import SwiftUI

struct OnboardingAPIScreen: View {
    @ObservedObject var aiService: AIService

    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider
    let isSelectedProviderVerified: Bool
    let canContinue: Bool
    @Binding var isShowingSkipWarning: Bool
    let onVerificationChanged: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void
    let onRequestSkip: () -> Void
    let onConfirmSkip: () -> Void

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                secondaryTitle: isSelectedProviderVerified ? nil : "Set It Up Later",
                onSecondary: onRequestSkip,
                onBack: onBack,
                isPrimaryEnabled: canContinue && isSelectedProviderVerified,
                onPrimary: onContinue
            )
        ) {
            OnboardingPageHeader(
                systemImage: OnboardingStage.api.systemImage,
                tint: OnboardingStage.api.tint,
                title: OnboardingStage.api.title,
                subtitle: OnboardingStage.api.subtitle
            )
        } content: {
            AIProviderVerificationSection(
                aiService: aiService,
                providerOptions: providerOptions,
                selectedProvider: $selectedProvider,
                onVerificationChanged: onVerificationChanged
            )
        }
        .alert("Set up AI enhancement later?", isPresented: $isShowingSkipWarning) {
            Button("Go Back", role: .cancel) {}
            Button("Set It Up Later") {
                onConfirmSkip()
            }
        } message: {
            Text("Enhancement modes and AI actions will stay off until you add a key. You can set this up anytime from Settings.")
        }
    }
}
