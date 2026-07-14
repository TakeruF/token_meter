import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle for the lifetime of the process. Sparkle performs scheduled checks,
/// presents the update notification, verifies the download, and replaces the app.
final class AppUpdater {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController
    var updater: SPUUpdater { controller.updater }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

/// Keeps SwiftUI buttons in sync while Sparkle is checking or installing.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// Sparkle persists these properties in its own UserDefaults keys. Local state is
/// only a UI mirror and is written back exclusively after a user-initiated change.
struct UpdaterSettingsView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
            .onChange(of: automaticallyChecksForUpdates) { _, enabled in
                updater.automaticallyChecksForUpdates = enabled
            }

        Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
            .disabled(!automaticallyChecksForUpdates)
            .onChange(of: automaticallyDownloadsUpdates) { _, enabled in
                updater.automaticallyDownloadsUpdates = enabled
            }

        CheckForUpdatesView(updater: updater)
    }
}
