import SwiftUI
import TokenMeterCore

struct MenuBarContentView: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    private var visibleProviders: [UsageProviderID] {
        UsageProviderID.allCases.filter { settings.enabledProviders().contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let fatal = monitor.fatalError {
                ErrorBanner(message: fatal)
            } else if visibleProviders.isEmpty {
                Text("No providers enabled. Turn one on in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(visibleProviders) { id in
                    ProviderCard(
                        state: monitor.states[id],
                        providerID: id,
                        onRefresh: { Task { await monitor.refresh(reason: .manual) } }
                    )
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Label("Token Meter", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline)
            Spacer()
            Button {
                Task { await monitor.refresh(reason: .manual) }
            } label: {
                if monitor.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(monitor.isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
        }
    }

    private var footer: some View {
        HStack {
            Button("Dashboard") {
                MainWindowRouter.shared.show(.dashboard, using: openWindow)
            }
                .buttonStyle(.borderless)

            Spacer()

            Button {
                MainWindowRouter.shared.show(.settings, using: openWindow)
            } label: {
                Image(systemName: "gearshape")
            }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.callout)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
