import SwiftUI

enum OnboardingLayout {
    static let sidebarWidth: CGFloat = 220
    static let headerMaxWidth: CGFloat = 470
}

/// A rounded, colored icon in the style of System Settings.
struct OnboardingIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A page's centered introduction, like the top of a System Settings pane.
struct OnboardingPageHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    let icon: Icon

    init(title: String, subtitle: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon()
    }

    var body: some View {
        VStack(spacing: 12) {
            icon
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: OnboardingLayout.headerMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

extension OnboardingPageHeader where Icon == OnboardingIconTile {
    init(systemImage: String, tint: Color, title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            OnboardingIconTile(systemImage: systemImage, tint: tint, size: 64)
        }
    }
}

/// The buttons along the bottom of a page: an optional secondary action on the leading edge, then Back and the
/// primary action, which also answers the Return key.
struct OnboardingNavigationBar: View {
    var secondaryTitle: LocalizedStringKey? = nil
    var onSecondary: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var primaryTitle: LocalizedStringKey = "Continue"
    var isPrimaryEnabled = true
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let secondaryTitle, let onSecondary {
                Button(secondaryTitle, action: onSecondary)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let onBack {
                Button("Back", action: onBack)
                    .controlSize(.large)
            }

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!isPrimaryEnabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

/// One onboarding page: a header above native grouped sections, with the navigation buttons pinned below.
struct OnboardingPage<Header: View, Content: View>: View {
    let header: Header
    let navigation: OnboardingNavigationBar
    let content: Content

    init(
        navigation: OnboardingNavigationBar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.navigation = navigation
        self.header = header()
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
            } header: {
                header
            }

            content
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            navigation
        }
    }
}
