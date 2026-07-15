import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle for the lifetime of the process. Sparkle performs scheduled checks,
/// presents the update notification, verifies the download, and replaces the app.
@MainActor
final class AppUpdater: NSObject, @MainActor SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    private(set) var controller: SPUStandardUpdaterController!
    var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }

        // Scheduled checks run while this menu bar app is in the background. Bring
        // Sparkle's update alert forward so a newly available version is visible.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.controller.userDriver.showUpdateInFocus()
        }
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
