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

enum AppLaunchOptions {
    static var showOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        #else
        false
        #endif
    }
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
        if bringMainWindowToFront() { return }

        openWindow(id: "dashboard")
        bringMainWindowToFront()

        // A closed window is inserted on the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    @discardableResult
    private func bringMainWindowToFront() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows.first { $0.identifier?.rawValue == "dashboard" }
            ?? NSApp.windows.first { $0.title == "Token Meter" && $0.canBecomeKey }
        window?.makeKeyAndOrderFront(nil)
        return window != nil
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
    private var firstRunWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Begin ingesting immediately: the app must work with no window ever opened.
        Task { @MainActor in
            await UsageMonitor.shared.start()
        }

        if !AppSettings.shared.hasCompletedSetup || AppLaunchOptions.showOnboarding {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            // LSUIElement apps do not reliably create their Window scene on first
            // launch. If SwiftUI has not made it after startup settles, provide the
            // same content in a normal NSWindow so onboarding is never invisible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "dashboard" }) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                self?.showFirstRunWindow()
            }
        }
    }

    @MainActor
    private func showFirstRunWindow() {
        let content = MainWindowView(monitor: UsageMonitor.shared)
            .environment(UsageMonitor.shared)
            .frame(minWidth: 760, minHeight: 540)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("dashboard")
        window.title = "Token Meter"
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        firstRunWindow = window
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
        Group {
            if !shouldShowOnboarding {
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
            } else {
                OnboardingView(monitor: monitor)
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        AppLaunchOptions.showOnboarding || !settings.hasCompletedSetup
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
        let values = monitor.menuBarProviderValues
        let reset = monitor.menuBarResetTitle
        let hasCompactContent = !values.isEmpty || reset != nil

        Group {
            if settings.menuBarStyle == .compact {
                let includeMeterIcon = settings.showMenuBarIcon || !hasCompactContent
                if let image = MenuBarCompactImage.make(
                    values: values.map { ($0.providerID, $0.compactValue) },
                    reset: reset,
                    includeMeterIcon: includeMeterIcon
                ) {
                    // MenuBarExtra's AppKit bridge only preserves the first
                    // image/text pair. A single composed image keeps every pair.
                    Image(nsImage: image)
                        .renderingMode(.template)
                } else if !title.isEmpty {
                    Text(title)
                } else {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                }
            } else {
                HStack(spacing: 4) {
                    if settings.showMenuBarIcon
                        || settings.menuBarStyle == .iconOnly
                        || title.isEmpty {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    }

                    if !title.isEmpty {
                        Text(title)
                    }
                }
            }
        }
        .accessibilityLabel(title.isEmpty ? "Token Meter" : "Token Meter: \(title)")
    }
}
