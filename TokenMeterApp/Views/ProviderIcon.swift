import AppKit
import SwiftUI
import TokenMeterCore

/// Provider marks shared across the app. Claude is an alpha-mask template so
/// `.primary` automatically flips between light and dark appearances. Codex
/// uses the light/dark variants stored in the shared asset catalog.
struct ProviderIcon: View {
    let providerID: UsageProviderID
    var size: CGFloat = 16

    var body: some View {
        Image(providerID == .claudeCode ? "ClaudeLogo" : "CodexLogo")
            .renderingMode(providerID == .claudeCode ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}

/// A status-item-safe provider mark. Asset-catalog PNGs have a 512-point
/// intrinsic size, and `MenuBarExtra` bridges its label through AppKit where
/// that intrinsic size can escape SwiftUI's layout proposal. Give AppKit a
/// copied image whose logical size is correct before it reaches the status bar.
@MainActor
struct MenuBarProviderIcon: View {
    let providerID: UsageProviderID

    private static let logicalSize = NSSize(width: 12, height: 12)

    var body: some View {
        Group {
            if let image = statusBarImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "questionmark")
            }
        }
        .frame(width: Self.logicalSize.width, height: Self.logicalSize.height)
        .accessibilityHidden(true)
    }

    private var statusBarImage: NSImage? {
        let name = providerID == .claudeCode ? "ClaudeLogo" : "CodexLogo"
        guard let source = NSImage(named: name),
              let image = source.copy() as? NSImage else { return nil }

        image.size = Self.logicalSize
        image.isTemplate = true
        return image
    }
}

struct ProviderLabel: View {
    let providerID: UsageProviderID
    var font: Font = .subheadline.weight(.semibold)
    var iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(providerID: providerID, size: iconSize)
            Text(providerID.displayName)
                .font(font)
        }
        .accessibilityElement(children: .combine)
    }
}
