import SwiftUI
import AppKit
import CoreServices

/// Every macOS permission BetterGlideTool uses, its current state, and a
/// button to grant it or open the matching pane of System Settings.
///
/// macOS stays the authority: states are read fresh every second while the
/// page is visible and whenever the app comes forward, never remembered.
struct PermissionsTab: View {
    /// Only the real Settings app may start System Events to read its state;
    /// tests that host this page must not.
    private var isLiveApp: Bool { AppMode.isSettings }
    @StateObject private var model = PermissionsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CardSection(title: "Accessibility", icon: "accessibility") {
                    PermissionRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        subtitle: "Detects trackpad and Magic Mouse gestures and controls windows.",
                        status: model.accessibility,
                        actionTitle: model.accessibility == .granted ? "Open…" : "Grant Access…",
                        action: model.grantAccessibility)
                }
                if model.accessibility != .granted {
                    CardFootnote("Already enabled? Quit other copies. After replacing an ad-hoc build, remove its old Accessibility entry and add the running app again, then relaunch. macOS must approve the new build.")
                        .padding(.top, -16)
                }

                CardSection(title: "Automation", icon: "gearshape.2") {
                    PermissionRow(
                        icon: "menubar.rectangle",
                        title: "System Events",
                        subtitle: "Lists an app's menu items when you choose a Menu Item action, and clicks them when Accessibility can't. Only needed for Menu Item actions.",
                        isOptional: true,
                        status: model.systemEvents,
                        actionTitle: model.systemEvents == .notAsked ? "Grant Access…" : "Open…",
                        action: { model.grantAutomation(.systemEvents) })
                    Divider().padding(.leading, 60)
                    PermissionRow(
                        icon: "trash.fill",
                        title: "Finder",
                        subtitle: "Empties the Trash for the Empty Trash action. Only needed for that action.",
                        isOptional: true,
                        status: model.finder,
                        actionTitle: model.finder == .notAsked ? "Grant Access…" : "Open…",
                        action: { model.grantAutomation(.finder) })
                }
                CardFootnote("Gestures work without these. If you don't grant them now, macOS asks the first time one of these features runs. AppleScript actions you write can ask to control other apps; those appear in the same Automation list.")
                    .padding(.top, -16)
            }
            .padding()
        }
        .onAppear { model.start(mayLaunchSystemEvents: isLiveApp) }
        .onDisappear { model.stop() }
        .onChange(of: model.accessibility) { _ in
            // Starts or stops the engine to match, as the old Recheck button did.
            EngineBridge.shared.recheckAccessibilityPermission()
        }
    }
}

// MARK: - State

enum PermissionStatus: Equatable {
    case checking, granted, denied, notAsked

    var label: LocalizedStringKey {
        switch self {
        case .checking: return "Checking…"
        case .granted:  return "Granted"
        case .denied:   return "Not granted"
        case .notAsked: return "Not asked yet"
        }
    }

    var symbol: String {
        switch self {
        case .checking: return "ellipsis.circle.fill"
        case .granted:  return "checkmark.circle.fill"
        case .denied:   return "exclamationmark.triangle.fill"
        case .notAsked: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .granted:  return .green
        case .denied:   return .orange
        case .checking, .notAsked: return .secondary
        }
    }
}

enum AutomationTarget: String {
    case systemEvents = "com.apple.systemevents"
    case finder = "com.apple.finder"

    /// System Events only runs while something uses it; it has to be running
    /// for macOS to report its Automation state.
    var launchURL: URL? {
        self == .systemEvents ? URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app") : nil
    }

    /// Asks macOS whether this app may send Apple Events to the target. With
    /// `ask`, macOS shows its consent prompt if the user hasn't decided yet; that
    /// call blocks until they answer, so never make it on the main thread.
    func permission(ask: Bool) -> PermissionStatus? {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: rawValue)
        guard let desc = descriptor.aeDesc else { return nil }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) {
        case noErr:                                      return .granted
        case OSStatus(errAEEventNotPermitted):           return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default:                                         return nil   // e.g. procNotFound: not running
        }
    }
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var accessibility: PermissionStatus = AccessibilityPermission.isGranted ? .granted : .denied
    @Published private(set) var systemEvents: PermissionStatus = .checking
    @Published private(set) var finder: PermissionStatus = .checking

    private var timer: Timer?
    private var activation: NSObjectProtocol?
    private var launchedSystemEvents = false
    private var mayLaunchSystemEvents = false

    func start(mayLaunchSystemEvents: Bool) {
        self.mayLaunchSystemEvents = mayLaunchSystemEvents
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activation { NotificationCenter.default.removeObserver(activation) }
        activation = nil
    }

    func refresh() {
        let granted = AccessibilityPermission.isGranted
        if (accessibility == .granted) != granted { accessibility = granted ? .granted : .denied }
        Task { await refreshAutomation(.systemEvents) }
        Task { await refreshAutomation(.finder) }
    }

    func grantAccessibility() {
        if accessibility != .granted, !UserDefaults.standard.bool(forKey: "accessibilityPromptRequested") {
            AccessibilityPermission.request()
        } else {
            AccessibilityPermission.openSettings()
        }
    }

    func grantAutomation(_ target: AutomationTarget) {
        guard status(of: target) == .notAsked else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        Task {
            let result = await Task.detached { target.permission(ask: true) }.value
            if let result { set(result, for: target) }
        }
    }

    private func refreshAutomation(_ target: AutomationTarget) async {
        var result = await Task.detached { target.permission(ask: false) }.value
        if result == nil, let url = target.launchURL, mayLaunchSystemEvents, !launchedSystemEvents {
            // Start System Events in the background once so its state can be read.
            launchedSystemEvents = true
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            result = await Task.detached { target.permission(ask: false) }.value
        }
        // Unreadable (target not running): keep what was last seen.
        let current = status(of: target)
        set(result ?? (current == .checking ? .notAsked : current), for: target)
    }

    private func status(of target: AutomationTarget) -> PermissionStatus {
        target == .systemEvents ? systemEvents : finder
    }

    private func set(_ value: PermissionStatus, for target: AutomationTarget) {
        switch target {
        case .systemEvents: if systemEvents != value { systemEvents = value }
        case .finder:       if finder != value { finder = value }
        }
    }
}

// MARK: - Layout

/// A titled group on the Permissions and About pages, drawn like the
/// General page's sections so every page reads the same.
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(spacing: 0) { content() }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var isOptional = false
    let status: PermissionStatus
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SidebarIconTile(systemImage: icon, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.body)
                    if isOptional {
                        Text("Optional")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Label { Text(status.label) } icon: { Image(systemName: status.symbol) }
                .font(.callout.weight(.medium))
                .foregroundStyle(status.color)
                .fixedSize()
            Button(actionTitle, action: action)
                .controlSize(.large)
                .fixedSize()
                .disabled(status == .checking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

struct CardFootnote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
