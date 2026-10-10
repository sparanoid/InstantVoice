import Foundation
import SwiftUI

/// A circular icon-only button in the system bordered style, used for panel close buttons and inline tools.
struct AppIconButton: View {
    let systemName: String
    let help: LocalizedStringResource
    var size: CGFloat = 40
    var iconSize: CGFloat = 18
    var cornerRadius: CGFloat = AppTheme.Radius.pill
    var isDisabled = false
    let action: () -> Void

    init(
        systemName: String,
        help: LocalizedStringResource,
        size: CGFloat = 40,
        iconSize: CGFloat = 18,
        cornerRadius: CGFloat = AppTheme.Radius.pill,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(help)
            } icon: {
                Image(systemName: systemName)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(controlSize)
        .disabled(isDisabled)
        .help(Text(help))
    }

    private var controlSize: ControlSize {
        switch size {
        case ..<30: return .small
        case ..<38: return .regular
        default: return .large
        }
    }
}

enum AppActionButtonKind: Equatable {
    case secondary
    case primary
    case destructive
}

struct AppActionButton: View {
    let title: LocalizedStringKey
    var kind: AppActionButtonKind = .secondary
    var minWidth: CGFloat?
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        kind: AppActionButtonKind = .secondary,
        minWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.minWidth = minWidth
        self.action = action
    }

    var body: some View {
        styledButton
            .controlSize(.large)
    }

    @ViewBuilder
    private var styledButton: some View {
        switch kind {
        case .primary:
            button.buttonStyle(.borderedProminent)
        case .secondary:
            button.buttonStyle(.bordered)
        case .destructive:
            button
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Status.error)
        }
    }

    private var button: some View {
        Button(role: kind == .destructive ? .destructive : nil, action: action) {
            Text(title)
                .frame(minWidth: minWidth)
        }
    }
}

struct AppPanelHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .zIndex(1)
    }
}

/// A toolbar button that explains the current screen in a popover, with an optional link to documentation.
struct ScreenInfoButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var learnMoreURL: String?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: "info.circle")
        }
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let learnMoreURL, let url = URL(string: learnMoreURL) {
                    Link("Learn more", destination: url)
                        .font(.callout)
                }
            }
            .frame(width: 280, alignment: .leading)
            .padding(16)
        }
    }
}
