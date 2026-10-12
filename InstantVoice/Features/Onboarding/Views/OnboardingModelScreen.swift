import SwiftUI

struct OnboardingModelScreen: View {
    let localModel: FluidAudioModel?
    let setupKind: OnboardingTranscriptionSetupKind
    let providerOptions: [any CloudProvider]
    @Binding var selectedProviderKey: String
    let isLocalDownloaded: Bool
    let isLocalDownloading: Bool
    let localDownloadStatus: FluidAudioDownloadStatus?
    let isSetupReady: Bool
    let onSelectSetupKind: (OnboardingTranscriptionSetupKind) -> Void
    let onDownload: (FluidAudioModel) -> Void
    let onCancelDownload: (FluidAudioModel) -> Void
    let onVerificationChanged: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                onBack: onBack,
                isPrimaryEnabled: isSetupReady && !(setupKind == .local && isLocalDownloading),
                onPrimary: onContinue
            )
        ) {
            OnboardingPageHeader(
                systemImage: OnboardingStage.model.systemImage,
                tint: OnboardingStage.model.tint,
                title: OnboardingStage.model.title,
                subtitle: OnboardingStage.model.subtitle
            )
        } content: {
            OnboardingTranscriptionSetupSection(
                localModel: localModel,
                setupKind: setupKind,
                providerOptions: providerOptions,
                selectedProviderKey: $selectedProviderKey,
                isLocalDownloaded: isLocalDownloaded,
                isLocalDownloading: isLocalDownloading,
                localDownloadStatus: localDownloadStatus,
                onSelectSetupKind: onSelectSetupKind,
                onDownloadLocalModel: onDownload,
                onCancelLocalModelDownload: onCancelDownload,
                onVerificationChanged: onVerificationChanged
            )
        }
    }
}
