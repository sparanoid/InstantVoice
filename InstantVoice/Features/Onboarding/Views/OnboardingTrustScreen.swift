import AppKit
import SwiftUI

struct OnboardingTrustScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                onBack: onBack,
                primaryTitle: "Get Started",
                onPrimary: onContinue
            )
        ) {
            OnboardingPageHeader(
                title: "InstantVoice is Private by Default",
                subtitle: "Your data never has to leave your device."
            ) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    // The artwork fills about 80% of an app icon's canvas, so this matches the other pages' tiles
                    // while taking the same space, which keeps every title in the same place.
                    .frame(width: 80, height: 80)
                    .frame(width: 64, height: 64)
            }
        } content: {
            Section {
                row(
                    systemImage: "internaldrive.fill",
                    tint: .gray,
                    title: "Local Storage",
                    detail: "Transcripts, recordings, and your dictionary stay on this Mac."
                )
                row(
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    tint: .indigo,
                    title: "Open Source",
                    detail: "InstantVoice is also open source, so you can inspect every single line of code."
                )
                row(
                    systemImage: "slider.horizontal.3",
                    tint: .blue,
                    title: "You Control It",
                    detail: "Each mode uses only the models and providers you choose."
                )
            }
        }
    }

    private func row(systemImage: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey)
        -> some View
    {
        HStack(spacing: 12) {
            OnboardingIconTile(systemImage: systemImage, tint: tint, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
