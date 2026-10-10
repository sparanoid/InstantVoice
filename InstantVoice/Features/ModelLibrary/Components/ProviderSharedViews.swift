import AppKit
import SwiftUI

struct ProviderBrandIcon: View {
    let descriptor: ProviderDescriptor
    let fallbackSystemImage: String
    let isSelected: Bool
    let size: CGFloat
    let iconSize: CGFloat

    private var hasBrandAsset: Bool {
        descriptor.brandAssetName != nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(7, size * 0.25), style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: max(7, size * 0.25), style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            if let assetName = descriptor.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .padding(size * 0.24)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.Accent.primary : Color.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        if hasBrandAsset {
            return Color.white.opacity(isSelected ? 0.96 : 0.9)
        }
        return AppTheme.Surface.control
    }

    private var borderColor: Color {
        if isSelected {
            return AppTheme.Accent.border
        }
        return AppTheme.Border.control.opacity(hasBrandAsset ? 0.45 : 0.2)
    }
}

struct ProviderSectionHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ProviderConfigurationGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }
}

struct ProviderModelListSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(ProviderSurface(cornerRadius: 10))
        }
    }
}

struct ProviderSurface: View {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        AppMaterialCardBackground(isSelected: isActive, cornerRadius: cornerRadius)
    }
}

struct ProviderStatusBadge: View {
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The download control on model cards: a prominent Download, or Cancel while a download runs.
struct ModelDownloadButton: View {
    let isDownloading: Bool
    var downloadTitle: LocalizedStringKey = "Download"
    let action: () -> Void

    var body: some View {
        if isDownloading {
            Button(action: action) {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.Status.error)
            .controlSize(.small)
        } else {
            Button(action: action) {
                Label(downloadTitle, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
