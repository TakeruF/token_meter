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
        Group {
            // Copilot ships no bundled brand asset, so it falls back to an SF Symbol.
            if providerID == .copilotCli {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .padding(size * 0.08)
            } else {
                Image(providerID == .claudeCode ? "ClaudeLogo" : "CodexLogo")
                    .renderingMode(providerID == .claudeCode ? .template : .original)
                    .resizable()
                    .scaledToFit()
            }
        }
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

    static let logicalSize = NSSize(width: 12, height: 12)

    var body: some View {
        Group {
            if let image = Self.statusBarImage(for: providerID) {
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

    static func statusBarImage(for providerID: UsageProviderID) -> NSImage? {
        let source: NSImage?
        if providerID == .copilotCli {
            // No bundled brand asset — use an SF Symbol mark instead.
            source = NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: nil
            )
        } else {
            source = NSImage(named: providerID == .claudeCode ? "ClaudeLogo" : "CodexLogo")
        }
        guard let source, let image = source.copy() as? NSImage else { return nil }

        image.size = Self.logicalSize
        image.isTemplate = true
        return image
    }
}

/// `MenuBarExtra` bridges its label to a single AppKit status-bar button. When
/// several image/text pairs are supplied, AppKit keeps only the first pair. Draw
/// compact mode into one template image so every enabled provider survives that
/// bridge and remains appearance-aware.
@MainActor
enum MenuBarCompactImage {
    private static let height: CGFloat = 16
    private static let pairSpacing: CGFloat = 5
    private static let iconValueSpacing: CGFloat = 2
    private static let resetSpacing: CGFloat = 4

    static func make(
        values: [(UsageProviderID, String)],
        reset: String?,
        includeMeterIcon: Bool
    ) -> NSImage? {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]

        var parts: [Part] = []
        if includeMeterIcon, let meter = meterImage() {
            parts.append(.image(meter, size: NSSize(width: 14, height: 14)))
        }

        for (index, value) in values.enumerated() {
            if !parts.isEmpty {
                parts.append(.space(index == 0 ? resetSpacing : pairSpacing))
            }
            let icon = MenuBarProviderIcon.statusBarImage(for: value.0)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
            if let icon {
                parts.append(.image(icon, size: MenuBarProviderIcon.logicalSize))
                parts.append(.space(iconValueSpacing))
            }
            parts.append(.text(value.1, attributes: attributes))
        }

        if let reset {
            if !parts.isEmpty {
                parts.append(.space(resetSpacing))
                parts.append(.text("·", attributes: attributes))
                parts.append(.space(resetSpacing))
            }
            parts.append(.text(reset, attributes: attributes))
        }

        guard !parts.isEmpty else { return nil }
        let width = ceil(parts.reduce(0) { $0 + $1.width })
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(at: &x, canvasHeight: height)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func meterImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: nil
        )
        return image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
    }

    private enum Part {
        case image(NSImage, size: NSSize)
        case text(String, attributes: [NSAttributedString.Key: Any])
        case space(CGFloat)

        var width: CGFloat {
            switch self {
            case .image(_, let size): size.width
            case .text(let text, let attributes):
                ceil((text as NSString).size(withAttributes: attributes).width)
            case .space(let width): width
            }
        }

        func draw(at x: inout CGFloat, canvasHeight: CGFloat) {
            switch self {
            case .image(let image, let size):
                image.draw(
                    in: NSRect(
                        x: x,
                        y: (canvasHeight - size.height) / 2,
                        width: size.width,
                        height: size.height
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            case .text(let text, let attributes):
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(
                    at: NSPoint(x: x, y: (canvasHeight - size.height) / 2),
                    withAttributes: attributes
                )
            case .space:
                break
            }
            x += width
        }
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
