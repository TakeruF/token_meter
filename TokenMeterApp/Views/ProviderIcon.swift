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
