import SwiftUI

/// A privacy permission as a form row, in the style of System Settings › Privacy & Security.
struct PermissionStepRow: View {
    let permission: OnboardingPermissionKind
    let status: OnboardingPermissionStatus
    let isNext: Bool
    let isLocked: Bool
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            OnboardingIconTile(systemImage: permission.systemImage, tint: permission.tint, size: 30)
                .saturation(isLocked ? 0 : 1)
                .opacity(isLocked ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(permission.descriptor.title))
                        .font(.system(size: 13, weight: .medium))

                    if !permission.isRequired {
                        Text("Optional")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(LocalizedStringKey(permission.descriptor.subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isLocked ? 0.6 : 1)

            Spacer(minLength: 12)

            trailingControl
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var trailingControl: some View {
        // Both titles arrive localized.
        if status.isGranted {
            Label(status.label, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        } else if isNext {
            Button(actionTitle, action: onAction)
                .buttonStyle(.borderedProminent)
        } else {
            Button(actionTitle, action: onAction)
                .disabled(isLocked)
        }
    }
}
