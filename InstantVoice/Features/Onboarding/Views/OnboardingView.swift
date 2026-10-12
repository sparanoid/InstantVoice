import AppKit
import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboardingV2: Bool
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var enhancementService: AIEnhancementService
    @StateObject private var coordinator = OnboardingCoordinator()

    var body: some View {
        let isTranscriptionModelDownloaded = coordinator.isTranscriptionModelDownloaded(
            using: fluidAudioModelManager
        )
        let isTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
        )

        NavigationSplitView {
            // The width modifier must come last, or the split view ignores it.
            OnboardingSidebar(items: coordinator.sidebarItems, current: coordinator.currentSidebarItem)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: OnboardingLayout.sidebarWidth,
                    ideal: OnboardingLayout.sidebarWidth,
                    max: OnboardingLayout.sidebarWidth
                )
        } detail: {
            page(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded,
                isTranscriptionSetupReady: isTranscriptionSetupReady
            )
            .id(coordinator.currentSidebarItem)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.22), value: coordinator.currentSidebarItem)
        .onAppear {
            coordinator.flow.ensureDefaultOnboardingTranscriptionProvider()
            coordinator.flow.refreshTranscriptionSetupVerification()
            coordinator.flow.ensureDefaultOnboardingProvider()
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.refreshAPIVerification()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
            let refreshedTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
            )
            coordinator.flow.reconcileStage(
                isTranscriptionSetupReady: refreshedTranscriptionSetupReady,
                enhancementService: enhancementService
            )
        }
        .onDisappear {
            coordinator.permissions.cancelRefreshTask()
        }
        .onReceive(LifecycleObserver.shared.publisher(for: .applicationDidBecomeActive)) { _ in
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.refreshTranscriptionSetupVerification()
            let refreshedTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
            )
            coordinator.flow.reconcileStage(
                isTranscriptionSetupReady: refreshedTranscriptionSetupReady,
                enhancementService: enhancementService
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            coordinator.flow.refreshAPIVerification()
            coordinator.flow.refreshTranscriptionSetupVerification()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let action = notification.object as? ShortcutAction,
                action == coordinator.experienceShortcutAction
            else {
                return
            }

            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modeConfigurationsDidChange)) { _ in
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onChange(of: coordinator.stage) { _, _ in
            coordinator.flow.activateExperienceModeForDemo()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
    }

    @ViewBuilder
    private func page(isTranscriptionModelDownloaded: Bool, isTranscriptionSetupReady: Bool) -> some View {
        switch coordinator.stage {
        case .permissions:
            OnboardingPermissionsScreen(
                isComplete: coordinator.requiredPermissionsGranted,
                activePermission: coordinator.activePermission,
                hasRequestedScreenRecording: coordinator.hasRequestedScreenRecording,
                status: { coordinator.permissions.status(for: $0) },
                isLocked: { coordinator.permissions.isLocked($0) },
                actionTitle: { coordinator.permissions.actionTitle(for: $0) },
                onAction: coordinator.permissions.performAction,
                onQuit: {
                    NSApplication.shared.terminate(nil)
                },
                onRecheck: coordinator.permissions.refreshPermissionStatuses,
                onContinue: coordinator.flow.goToMicrophoneStep
            )
        case .microphone:
            OnboardingMicrophoneScreen(
                onBack: coordinator.flow.goToPermissionsStep,
                onContinue: coordinator.flow.goToModelStep
            )
        case .model:
            OnboardingModelScreen(
                localModel: coordinator.requiredTranscriptionModel,
                setupKind: coordinator.transcriptionSetupKind,
                providerOptions: coordinator.onboardingTranscriptionProviderOptions,
                selectedProviderKey: coordinator.selectedOnboardingTranscriptionProviderKeyBinding(),
                isLocalDownloaded: isTranscriptionModelDownloaded,
                isLocalDownloading: coordinator.requiredTranscriptionModel.map {
                    fluidAudioModelManager.isFluidAudioModelDownloading($0)
                } ?? false,
                localDownloadStatus: coordinator.requiredTranscriptionModel.flatMap {
                    fluidAudioModelManager.downloadStatus(for: $0)
                },
                isSetupReady: isTranscriptionSetupReady,
                onSelectSetupKind: coordinator.flow.selectOnboardingTranscriptionSetup,
                onDownload: {
                    coordinator.flow.downloadTranscriptionModel(
                        $0,
                        modelManager: fluidAudioModelManager
                    )
                },
                onCancelDownload: {
                    fluidAudioModelManager.cancelDownload($0)
                },
                onVerificationChanged: coordinator.flow.refreshTranscriptionSetupVerification,
                onBack: coordinator.flow.goToMicrophoneStep,
                onContinue: {
                    coordinator.flow.goToAPIStep(
                        isTranscriptionSetupReady: isTranscriptionSetupReady,
                        aiService: aiService
                    )
                }
            )
        case .api:
            OnboardingAPIScreen(
                aiService: aiService,
                providerOptions: coordinator.onboardingProviderOptions,
                selectedProvider: coordinator.selectedOnboardingProviderBinding(aiService: aiService),
                isSelectedProviderVerified: coordinator.isSelectedAPIProviderVerified,
                canContinue: coordinator.isReadyForExperience(
                    isTranscriptionSetupReady: isTranscriptionSetupReady
                ),
                isShowingSkipWarning: $coordinator.isShowingSkipAPISetupWarning,
                onVerificationChanged: coordinator.flow.refreshAPIVerification,
                onBack: coordinator.flow.goBackToModelStep,
                onContinue: {
                    coordinator.flow.goToExperienceStep(
                        isTranscriptionSetupReady: isTranscriptionSetupReady,
                        enhancementService: enhancementService
                    )
                },
                onRequestSkip: coordinator.flow.requestSkipAPISetup,
                onConfirmSkip: {
                    coordinator.flow.skipAPISetupAndContinue(
                        isTranscriptionSetupReady: isTranscriptionSetupReady,
                        enhancementService: enhancementService
                    )
                }
            )
        case .experience:
            OnboardingExperienceScreen(
                step: coordinator.experienceStep,
                isInIntroPhase: coordinator.isShowingExperienceIntroPhase,
                shortcutAction: coordinator.experienceShortcutAction,
                hasShortcut: coordinator.hasExperienceModeShortcut,
                text: coordinator.currentExperienceText,
                isReady: coordinator.isCurrentExperienceReady(
                    isTranscriptionSetupReady: isTranscriptionSetupReady
                ),
                isComplete: coordinator.isCurrentExperienceComplete,
                onSkipSetup: skipSetup,
                onBackFromIntro: {
                    coordinator.flow.goToPreviousExperienceStep(enhancementService: enhancementService)
                },
                onContinueIntro: coordinator.flow.goToExperiencePracticePhase,
                onBackFromPractice: {
                    coordinator.flow.goBackFromExperiencePractice(enhancementService: enhancementService)
                },
                onAdvance: {
                    coordinator.flow.advanceExperienceStep(
                        isTranscriptionSetupReady: isTranscriptionSetupReady,
                        enhancementService: enhancementService
                    )
                },
                onShortcutChanged: {
                    coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
                },
                onAppear: coordinator.flow.activateExperienceModeForDemo
            )
        case .contextAwareness:
            OnboardingContextAwarenessScreen(
                onSkipSetup: skipSetup,
                onBack: {
                    coordinator.flow.goToPreviousContextAwarenessStep(
                        enhancementService: enhancementService
                    )
                },
                onContinue: {
                    coordinator.flow.continueFromContextAwarenessStep(
                        enhancementService: enhancementService
                    )
                }
            )
        case .trust:
            OnboardingTrustScreen(
                onBack: {
                    coordinator.flow.goToPreviousTrustStep(
                        isTranscriptionSetupReady: isTranscriptionSetupReady,
                        enhancementService: enhancementService
                    )
                },
                onContinue: {
                    coordinator.flow.completeOnboarding(
                        isTranscriptionSetupReady: isTranscriptionSetupReady
                    ) {
                        hasCompletedOnboardingV2 = true
                    }
                }
            )
        }
    }

    /// Skipping is offered once the required permissions are in place, from the first try-it-out step on.
    private var skipSetup: (() -> Void)? {
        guard coordinator.requiredPermissionsGranted else { return nil }
        return {
            coordinator.flow.skipOnboarding {
                hasCompletedOnboardingV2 = true
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboardingV2: .constant(false))
}
