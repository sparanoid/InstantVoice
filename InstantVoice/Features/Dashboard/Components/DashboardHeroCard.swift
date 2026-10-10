import AppKit
import Foundation
import SwiftUI

enum DashboardHeroHeadline {
    case calculatingProgress
    case startRecordingProgress
    case savedTime(String)
}

/// The dashboard's full-bleed banner. The artwork runs under the toolbar and, through the background
/// extension effect, continues beneath the floating sidebar before fading into the window background.
struct DashboardHero<Greeting: View>: View {
    private static var headlineFont: Font { .system(.title2, design: .rounded, weight: .semibold) }
    private static var highlightedHeadlineFont: Font { .system(.largeTitle, design: .rounded, weight: .heavy) }

    let isLocked: Bool
    let headline: DashboardHeroHeadline
    let subtext: String
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let canViewInsights: Bool
    let actionHelp: String
    let actionAccessibilityLabel: String
    let reviewCorrectionCount: Int?
    let onViewInsights: () -> Void
    let onReviewCorrections: () -> Void
    /// Taps outside the greeting, such as on the artwork or copy, end name editing.
    var onBackgroundTap: () -> Void = {}
    @ViewBuilder let greeting: () -> Greeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            greeting()

            Group {
                if isLocked {
                    lockedInsightsPrompt
                } else {
                    heroCopy
                }

                actions
                    .padding(.top, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onBackgroundTap)
        }
        .padding(.horizontal, DashboardLayout.pageHorizontalPadding + 8)
        .padding(.top, DashboardLayout.heroTopPadding)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, minHeight: DashboardLayout.heroMinimumHeight, alignment: .bottomLeading)
        .background {
            DashboardHeroBackground(isLocked: isLocked)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onViewInsights) {
                Label(actionTitle, systemImage: actionIcon)
            }
            .buttonStyle(.glassProminent)
            .tint(DashboardHeroPalette.accent)
            .controlSize(.large)
            .disabled(!canViewInsights)
            .help(actionHelp)
            .accessibilityLabel(Text(actionAccessibilityLabel))

            if let reviewCorrectionCount {
                Button(action: onReviewCorrections) {
                    Label("Review Corrections", systemImage: "text.book.closed")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(reviewCorrectionsHelp(count: reviewCorrectionCount))
                .accessibilityLabel("Review corrections")
                .accessibilityValue(
                    Text(
                        String(
                            format: String(localized: "%lld pending corrections"),
                            Int64(reviewCorrectionCount)
                        )
                    )
                )
            }
        }
    }

    private func reviewCorrectionsHelp(count: Int) -> String {
        String(
            format: String(localized: "Review %lld pending corrections"),
            Int64(count)
        )
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(styledHeadline)
                .frame(maxWidth: 720, alignment: .leading)
                .contentTransition(.numericText())

            Text(subtext)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var styledHeadline: AttributedString {
        let highlightedValue: String
        var text: AttributedString

        switch headline {
        case .calculatingProgress:
            highlightedValue = String(localized: "InstantVoice progress")
            text = AttributedString(localized: "Calculating \(highlightedValue).")
        case .startRecordingProgress:
            highlightedValue = String(localized: "InstantVoice progress")
            text = AttributedString(localized: "Start recording to build \(highlightedValue).")
        case .savedTime(let value):
            highlightedValue = value
            text = AttributedString(localized: "You have saved \(highlightedValue) with InstantVoice")
        }

        text.font = Self.headlineFont
        text.foregroundColor = .primary

        if let highlightedRange = text.range(of: highlightedValue) {
            text[highlightedRange].font = Self.highlightedHeadlineFont
            text[highlightedRange].foregroundColor = DashboardHeroPalette.accent
        }

        return text
    }

    private var lockedInsightsPrompt: some View {
        Label {
            Text("Continue using InstantVoice to unlock stats and insights.")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: 540, alignment: .leading)
        } icon: {
            Image(systemName: "lock.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DashboardHeroPalette.accent)
        }
    }
}

private struct DashboardHeroBackground: View {
    var isLocked = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                // Anchor the artwork's trailing edge so the sunrise stays in view at every width.
                Image("momentum-hero-bg")
                    .resizable()
                    .scaledToFill()
                    .saturation(isLocked ? 0.8 : 1)
            }
            .clipped()
            .overlay {
                if colorScheme == .dark {
                    Color.black.opacity(0.5)
                }
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: Color(nsColor: .windowBackgroundColor), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .backgroundExtensionEffect()
            .accessibilityHidden(true)
    }
}

enum DashboardHeroPalette {
    /// Burnt orange that holds contrast on the light artwork, lifted for the dimmed dark-mode artwork.
    static let accent = Color(
        nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.32, alpha: 1)
                : NSColor(srgbRed: 0.76, green: 0.31, blue: 0.08, alpha: 1)
        })
}
