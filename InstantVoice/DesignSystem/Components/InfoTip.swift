import SwiftUI

/// A reusable info tip component that displays helpful information in a popover
struct InfoTip: View {
    // Content configuration
    var message: LocalizedStringKey
    var learnMoreLink: URL?

    // Appearance customization
    var iconName: String = "info.circle"
    var iconSize: Image.Scale = .medium
    var iconColor: Color = .primary
    var width: CGFloat = 280

    // State
    @State private var isShowingTip: Bool = false

    var body: some View {
        Button {
            isShowingTip.toggle()
        } label: {
            Image(systemName: iconName)
                .imageScale(iconSize)
                .foregroundStyle(iconColor)
                .fontWeight(.semibold)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Info")
        .accessibilityHint(Text(message))
        .popover(isPresented: $isShowingTip) {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let learnMoreLink {
                    Link("Learn more", destination: learnMoreLink)
                        .font(.callout)
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(14)
        }
    }
}

// MARK: - Convenience initializers

extension InfoTip {
    /// Creates an InfoTip with just a message
    init(_ message: LocalizedStringKey) {
        self.message = message
        self.learnMoreLink = nil
    }

    /// Creates an InfoTip with a dynamic string message
    init(_ message: String) {
        self.message = LocalizedStringKey(message)
        self.learnMoreLink = nil
    }

    /// Creates an InfoTip with a learn more link
    init(_ message: LocalizedStringKey, learnMoreURL: String) {
        self.message = message
        self.learnMoreLink = URL(string: learnMoreURL)
    }

    /// Creates an InfoTip with a dynamic string message and learn more link
    init(_ message: String, learnMoreURL: String) {
        self.message = LocalizedStringKey(message)
        self.learnMoreLink = URL(string: learnMoreURL)
    }
}
