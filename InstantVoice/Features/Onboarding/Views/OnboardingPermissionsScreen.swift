import SwiftUI

struct OnboardingPermissionsScreen: View {
    let isComplete: Bool
    let activePermission: OnboardingPermissionKind
    let hasRequestedScreenRecording: Bool
    let status: (OnboardingPermissionKind) -> OnboardingPermissionStatus
    let isLocked: (OnboardingPermissionKind) -> Bool
    let actionTitle: (OnboardingPermissionKind) -> String
    let onAction: (OnboardingPermissionKind) -> Void
    let onQuit: () -> Void
    let onRecheck: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                secondaryTitle: "Recheck",
                onSecondary: onRecheck,
                isPrimaryEnabled: isComplete,
                onPrimary: onContinue
            )
        ) {
            OnboardingPageHeader(
                systemImage: OnboardingStage.permissions.systemImage,
                tint: OnboardingStage.permissions.tint,
                title: OnboardingStage.permissions.title,
                subtitle: OnboardingStage.permissions.subtitle
            )
        } content: {
            Section {
                ForEach(OnboardingPermissionKind.allCases) { permission in
                    PermissionStepRow(
                        permission: permission,
                        status: status(permission),
                        isNext: !isComplete && activePermission == permission,
                        isLocked: isLocked(permission),
                        actionTitle: actionTitle(permission),
                        onAction: { onAction(permission) }
                    )
                }
            } footer: {
                if showsScreenRecordingRestartHint {
                    HStack(spacing: 6) {
                        Text("Restart InstantVoice after enabling Screen Recording.")
                        Button("Quit", action: onQuit)
                            .buttonStyle(.link)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var showsScreenRecordingRestartHint: Bool {
        hasRequestedScreenRecording && !status(.screenRecording).isGranted
    }
}
