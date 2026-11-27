import SwiftUI
import AppKit

// ─────────────────────────────────────────────
// MARK: - Two modes, one executable
//
// The menu bar app launches its own bundle a second time with `--settings` to
// show Settings. That process draws the Preferences window and quits when it
// closes, so the framework memory Settings costs (~65 MB) goes with it instead
// of staying in the menu bar app for the rest of the session.
// See docs/settings-process-plan.md.
// ─────────────────────────────────────────────

enum AppMode {
    static let settingsFlag = "--settings"

    /// True in the short-lived Settings process. It never starts the gesture
    /// engine, hotkeys, the menu bar item or onboarding at launch.
    static let isSettings = CommandLine.arguments.contains(settingsFlag)

    /// The menu bar app that launched this Settings process.
    static var parentPID: pid_t? {
        argument("parent-pid").flatMap(pid_t.init).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Sends a message to the menu bar app that launched this Settings process.
    @discardableResult
    static func tellMenuBarApp(_ message: LinkMessage) -> Bool {
        guard isSettings, let pid = parentPID else { return false }
        return EngineLink.send(message, to: EngineLink.menuBarPortName(pid: pid))
    }

    /// The value of a `--name=value` launch argument.
    static func argument(_ name: String) -> String? {
        let prefix = "--\(name)="
        return CommandLine.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

// MARK: - Settings process

struct SettingsApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) var appDelegate

    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var engineBridge = EngineBridge.shared

    init() {
        // Each launch starts fresh: no window state carried over from the last
        // Settings session (see SettingsAppDelegate's restoration methods).
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        GlideConfigStore.shared.load()
        _preferencesStore = StateObject(wrappedValue: PreferencesStore.shared)

        let navigator = PreferencesNavigator.shared
        if let device = AppMode.argument("device").flatMap(PreferencesDevice.fromLaunchArgument) {
            navigator.device = device
        }
        if let tab = AppMode.argument("tab").flatMap(PrefsTab.fromLaunchArgument) {
            navigator.tab = tab
        }
    }

    var body: some Scene {
        Window("BetterGlideTool Settings", id: "preferences") {
            PreferencesWindow()
                .environmentObject(preferencesStore)
                .environmentObject(engineBridge)
                // This process is a regular app for its whole life; the window
                // must not switch it to an accessory app when it closes.
                .environment(\.preferencesManagesActivationPolicy, false)
                .background(SettingsWindowSizeGuard())
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            // One window only: no File › New, and ⌘, has nothing else to open.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private var parentWatch: DispatchSourceProcess?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist marks the bundle as an agent (LSUIElement) for the menu
        // bar app; Settings gets a Dock icon and a menu bar of its own.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        watchParent()
        MainActor.assumeIsolated {
            // Pick up edits the menu bar app saves while Settings is open.
            ConfigSync.start()
            EngineLink.listen(on: EngineLink.settingsPortName(pid: getpid())) { message in
                MainActor.assumeIsolated { Self.handle(message) }
            }
            if CommandLine.arguments.contains("--check-updates") { UpdateChecker.shared.check() }
        }
    }

    @MainActor
    private static func handle(_ message: LinkMessage) {
        guard case let .show(tab, device, checkForUpdates) = message else {
            LiveStreamClient.shared.handle(message)
            return
        }
        let navigator = PreferencesNavigator.shared
        if let device = device.flatMap(PreferencesDevice.fromLaunchArgument) { navigator.device = device }
        if let tab = tab.flatMap(PrefsTab.fromLaunchArgument) { navigator.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        if checkForUpdates { UpdateChecker.shared.check() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Window restoration off. With it on, a launch after the window had been
    // closed restored that closed window as a 135×149 sliver instead of
    // opening Settings normally.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func application(_ app: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        GlideConfigStore.shared.flushPendingSave()
    }

    /// Quits when the menu bar app that launched this process goes away, so a
    /// Settings window never outlives the app it configures.
    private func watchParent() {
        guard let pid = AppMode.parentPID else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        parentWatch = source
        // The parent may have exited before the watch started.
        if kill(pid, 0) != 0, errno == ESRCH { NSApp.terminate(nil) }
    }
}

/// Makes sure the Settings window opens at a usable size and isn't restored
/// from a saved frame smaller than the page's minimum.
private struct SettingsWindowSizeGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ view: GuardView, context: Context) {}

    final class GuardView: NSView {
        static let minimum = NSSize(width: 760, height: 520)
        static let preferred = NSSize(width: 820, height: 600)

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isRestorable = false
            window.contentMinSize = Self.minimum
            let size = window.contentRect(forFrameRect: window.frame).size
            if size.width < Self.minimum.width || size.height < Self.minimum.height {
                window.setContentSize(Self.preferred)
                window.center()
            }
        }
    }
}

// MARK: - Launching it from the menu bar app

@MainActor
enum SettingsProcess {
    private static var running: NSRunningApplication?
    private static var isLaunching = false

    /// Brings the Settings process forward on `tab`, launching it if it isn't
    /// running. With `checkForUpdates`, Settings also checks for an update.
    static func open(tab: PrefsTab? = nil, checkForUpdates: Bool = false) {
        if let app = running, !app.isTerminated {
            let delivered = EngineLink.send(
                .show(tab: tab?.launchArgument,
                      device: PreferencesNavigator.shared.device.launchArgument,
                      checkForUpdates: checkForUpdates),
                to: EngineLink.settingsPortName(pid: app.processIdentifier))
            if !delivered { AppLogger.debug("[Settings] Couldn't reach the running Settings process") }
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return
        }
        guard !isLaunching else { return }
        isLaunching = true

        var arguments = [AppMode.settingsFlag, "--parent-pid=\(getpid())",
                         "--device=\(PreferencesNavigator.shared.device.launchArgument)"]
        if let tab { arguments.append("--tab=\(tab.launchArgument)") }
        if checkForUpdates { arguments.append("--check-updates") }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.arguments = arguments
        // Keep a sandboxed config (tests, harnesses) sandboxed in the child too.
        if let override = ProcessInfo.processInfo.environment["BETTERGLIDETOOL_CONFIG_PATH"], !override.isEmpty {
            configuration.environment = ["BETTERGLIDETOOL_CONFIG_PATH": override]
        }

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                isLaunching = false
                running = app
                if let error {
                    AppLogger.debug("[Settings] Launch failed: \(error.localizedDescription)")
                    reportLaunchFailure(error)
                }
            }
        }
    }
}

extension SettingsProcess {
    /// There's no Settings window inside the menu bar app to fall back on, so a
    /// failed launch is said out loud instead of doing nothing.
    static func reportLaunchFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Couldn't open Settings")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Launch arguments

extension PrefsTab {
    /// Stable, space-free name for a launch argument.
    var launchArgument: String { String(describing: self) }
    static func fromLaunchArgument(_ value: String) -> PrefsTab? {
        allCases.first { $0.launchArgument == value }
    }
}

extension PreferencesDevice {
    var launchArgument: String { String(describing: self) }
    static func fromLaunchArgument(_ value: String) -> PreferencesDevice? {
        allCases.first { $0.launchArgument == value }
    }
}
