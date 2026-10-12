import SwiftUI

/// A step as the onboarding sidebar lists it.
enum OnboardingSidebarItem: Hashable {
    case permissions
    case microphone
    case transcription
    case aiEnhancement
    case experience(OnboardingExperienceKind)
    case modes
    case privacy

    var title: LocalizedStringKey {
        switch self {
        case .permissions:
            return "Permissions"
        case .microphone:
            return "Microphone"
        case .transcription:
            return "Transcription"
        case .aiEnhancement:
            return "AI Enhancement"
        case .experience(.dictation):
            return "Dictation"
        case .experience(.enhance):
            return "Enhancement"
        case .experience(.email):
            return "Email"
        case .modes:
            return "Modes"
        case .privacy:
            return "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .permissions:
            return "hand.raised"
        case .microphone:
            return "mic"
        case .transcription:
            return "waveform"
        case .aiEnhancement:
            return "sparkles"
        case .experience(.dictation):
            return "text.cursor"
        case .experience(.enhance):
            return "wand.and.sparkles"
        case .experience(.email):
            return "envelope"
        case .modes:
            return "sparkles.rectangle.stack"
        case .privacy:
            return "lock.shield"
        }
    }

    fileprivate var isPractice: Bool {
        switch self {
        case .experience, .modes:
            return true
        default:
            return false
        }
    }
}

/// The steps of onboarding in a sidebar, like the macOS Installer: done steps carry a checkmark, and later ones stay
/// dimmed until the user gets there.
struct OnboardingSidebar: View {
    let items: [OnboardingSidebarItem]
    let current: OnboardingSidebarItem

    var body: some View {
        // The selection only follows the flow; steps open through the page buttons.
        List(selection: .constant(Optional(current))) {
            Section("Set Up") {
                ForEach(items.filter { !$0.isPractice && $0 != .privacy }, id: \.self, content: row)
            }

            Section("Try It Out") {
                ForEach(items.filter(\.isPractice), id: \.self, content: row)
            }

            Section {
                row(.privacy)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: OnboardingSidebarItem) -> some View {
        let position = items.firstIndex(of: item) ?? 0
        let currentPosition = items.firstIndex(of: current) ?? 0

        return HStack(spacing: 6) {
            Label(item.title, systemImage: item.systemImage)

            Spacer(minLength: 0)

            if position < currentPosition {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Done")
            }
        }
        .foregroundStyle(position > currentPosition ? .secondary : .primary)
        // Sidebar icons take the list item tint rather than the foreground style.
        .listItemTint(position > currentPosition ? .monochrome : nil)
        .tag(item)
    }
}
