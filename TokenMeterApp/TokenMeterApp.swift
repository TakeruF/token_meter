import SwiftUI
import Observation
import TokenMeterCore

@main
struct TokenMeterApp: App {
    /// Shared, not window-owned: a menu bar app may never open a window, so the
    /// monitor has to be startable from the app delegate.
    @State private var monitor = UsageMonitor.shared
    @State private var settings = AppSettings.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appUpdater = AppUpdater.shared

    var body: some Scene {
        // `isInserted` lets the user remove the menu bar item entirely.
        MenuBarExtra(isInserted: $settings.showMenuBarExtra) {
            MenuBarContentView(monitor: monitor)
                .environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Token Meter", id: "dashboard") {
            MainWindowView(monitor: monitor)
                .environment(monitor)
                .frame(minWidth: 760, minHeight: 540)
                // Without a menu bar item the app must keep a Dock icon, or there
                // would be no way left to reopen this window.
                .onChange(of: settings.showMenuBarExtra, initial: true) { _, shown in
                    NSApp.setActivationPolicy(shown ? .accessory : .regular)
                }
        }
        .defaultSize(width: 940, height: 680)
        .handlesExternalEvents(matching: ["dashboard"])
        .commands {
            MainWindowCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appUpdater.updater)
            }
        }
    }
}

enum MainWindowTab: Hashable {
    case dashboard, setup, settings
}

/// A single routing point for menu-bar buttons and the standard Settings command.
/// Opening a SwiftUI window does not necessarily activate an accessory app, so the
/// router explicitly activates it and raises the requested window as well.
@Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    var selection: MainWindowTab = AppSettings.shared.hasCompletedSetup ? .dashboard : .setup

    private init() {}

    func show(_ tab: MainWindowTab, using openWindow: OpenWindowAction) {
        selection = tab
        openWindow(id: "dashboard")
        bringMainWindowToFront()

        // A closed window is inserted on the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows.first { $0.identifier?.rawValue == "dashboard" }
            ?? NSApp.windows.first { $0.title == "Token Meter" && $0.canBecomeKey }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                MainWindowRouter.shared.show(.settings, using: openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Opens the window on first launch (there is nothing else to show yet) and keeps
/// the app alive when its last window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Begin ingesting immediately: the app must work with no window ever opened.
        Task { @MainActor in
            await UsageMonitor.shared.start()
        }

        if !AppSettings.shared.hasCompletedSetup {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // A menu bar app outlives its windows.
        !AppSettings.shared.showMenuBarExtra ? true : false
    }
}

/// The main window: Setup leads on first launch, Dashboard afterwards.
struct MainWindowView: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared
    @State private var router = MainWindowRouter.shared

    var body: some View {
        TabView(selection: $router.selection) {
            DashboardView(monitor: monitor)
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }
                .tag(MainWindowTab.dashboard)

            SetupView(monitor: monitor)
                .tabItem { Label("Setup", systemImage: "checklist") }
                .tag(MainWindowTab.setup)
                .badge(needsAttentionCount)

            SettingsView(monitor: monitor)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainWindowTab.settings)
        }
        .onAppear { settings.hasCompletedSetup = true }
    }

    /// Providers the user has enabled but that are not actually connected.
    private var needsAttentionCount: Int {
        UsageProviderID.allCases
            .filter { settings.enabledProviders().contains($0) }
            .filter { monitor.states[$0]?.availability.isAvailable == false }
            .count
    }
}

/// The menu bar item itself: SF Symbol plus text, legible in both appearances and
/// readable by VoiceOver.
struct MenuBarLabel: View {
    let monitor: UsageMonitor
    @State private var settings = AppSettings.shared

    var body: some View {
        let title = monitor.menuBarTitle
        HStack(spacing: 4) {
            if settings.showMenuBarIcon || title.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
            }
            if !title.isEmpty {
                Text(title)
            }
        }
        .accessibilityLabel(title.isEmpty ? "Token Meter" : "Token Meter: \(title)")
    }
}
