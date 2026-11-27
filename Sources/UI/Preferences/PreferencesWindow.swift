import SwiftUI
import AppKit

enum PrefsTab: String, CaseIterable, Identifiable {
    case gestures      = "Gestures"
    case keyboard      = "Keyboard"
    case edgeControls  = "Edge Controls"
    case tuning        = "Tuning"
    case inputMonitoring = "Input Monitoring"
    case general       = "General"
    case permissions   = "Permissions"
    case configuration = "Backup"
    case about         = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .edgeControls:  return "rectangle.inset.filled"
        case .gestures:      return "hand.draw.fill"
        case .keyboard:      return "keyboard.fill"
        case .tuning:        return "slider.horizontal.3"
        case .inputMonitoring: return "waveform"
        case .general:       return "gearshape.fill"
        case .permissions:   return "lock.shield.fill"
        case .configuration: return "externaldrive.fill"
        case .about:         return "info.circle.fill"
        }
    }
}

enum PreferencesDevice: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad"
    case magicMouse = "Magic Mouse"
    var id: String { rawValue }
    var icon: String { self == .trackpad ? "rectangle.and.hand.point.up.left" : "magicmouse" }
    var tabs: [PrefsTab] {
        self == .trackpad ? [.gestures, .edgeControls, .tuning, .inputMonitoring] : [.gestures, .tuning, .inputMonitoring]
    }
}

/// Lets other parts of the app decide which tab the Preferences window opens on.
///
/// Held outside the view so callers can set it *before* the window exists —
/// posting a notification at a window that hasn't been created yet would land
/// on nothing.
@MainActor
final class PreferencesNavigator: ObservableObject {
    static let shared = PreferencesNavigator()
    private init() {}

    @Published var tab: PrefsTab = .gestures
    @Published var device: PreferencesDevice = .trackpad
    /// Whether the Preferences window's contents exist. SwiftUI keeps a closed
    /// window's whole view graph alive (about 65 MB once every tab has been
    /// visited), so the window shows an empty placeholder while closed and
    /// builds the real contents again when it opens.
    @Published var isPresented = false

    /// Call before `openWindow(id: "preferences")`.
    func present(tab: PrefsTab? = nil) {
        if let tab { self.tab = tab }
        isPresented = true
    }
}

/// Root of the Preferences window scene: the real contents while the window is
/// open, an empty view of the same minimum size while it is closed.
struct PreferencesWindowRoot: View {
    @ObservedObject private var navigator = PreferencesNavigator.shared

    var body: some View {
        Group {
            if navigator.isPresented {
                PreferencesWindow()
            } else {
                Color.clear.frame(minWidth: 760, minHeight: 520)
            }
        }
        .background(WindowLifecycleObserver(
            onOpen: { navigator.isPresented = true },
            onClose: {
                // After the window has gone, so the swap is never seen.
                DispatchQueue.main.async {
                    navigator.isPresented = false
                    MemoryRelief.returnFreedMemory(after: 1.5)
                }
            }))
    }
}

/// Reports when the hosting window becomes key (opened or brought back) and
/// when it closes.
private struct WindowLifecycleObserver: NSViewRepresentable {
    var onOpen: () -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOpen = onOpen
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onOpen: () -> Void = {}
        var onClose: () -> Void = {}
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                             object: window, queue: .main) { [weak self] _ in self?.onOpen() })
            tokens.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                             object: window, queue: .main) { [weak self] _ in self?.onClose() })
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// Hands memory the app has freed back to macOS. Without it the allocator keeps
/// freed pages for reuse, and the app's footprint stays at its peak.
enum MemoryRelief {
    static func returnFreedMemory(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Only while Settings is still closed.
            guard !PreferencesNavigator.shared.isPresented else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}

/// Whether opening Preferences turns BetterGlideTool into a regular app with a
/// Dock icon (and back when it closes). Always true in the app; tests that host
/// the window offscreen turn it off so their process never gets a Dock tile.
private struct ManagesActivationPolicyKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var preferencesManagesActivationPolicy: Bool {
        get { self[ManagesActivationPolicyKey.self] }
        set { self[ManagesActivationPolicyKey.self] = newValue }
    }
}

struct PreferencesWindow: View {
    @Environment(\.preferencesManagesActivationPolicy) private var managesActivationPolicy
    @ObservedObject private var navigator = PreferencesNavigator.shared
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge: EngineBridge

    private var selectedTab: PrefsTab { navigator.tab }

    var body: some View {
        NavigationSplitView {
            // No `selection:` — the system would paint the chosen row with the
            // accent colour. Rows are buttons and the chosen one sits on glass.
            List {
                Section(L(navigator.device.rawValue)) {
                    ForEach(navigator.device.tabs) { tab in sidebarRow(tab) }
                }
                Section("Keyboard") {
                    sidebarRow(.keyboard)
                }
                Section("General") {
                    ForEach([PrefsTab.general, .permissions]) { tab in sidebarRow(tab) }
                }
                Section("Advanced") {
                    ForEach([PrefsTab.configuration, .about]) { tab in sidebarRow(tab) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .safeAreaInset(edge: .top) {
                Picker("Input device", selection: Binding(
                    get: { navigator.device },
                    set: { navigator.device = $0; navigator.tab = .gestures }
                )) {
                    ForEach(PreferencesDevice.allCases) { device in
                        Label(L(device.rawValue), systemImage: device.icon).tag(device)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.large)
                .padding(12)
                .accessibilityLabel("Input device")

            }
        } detail: {
            Group {
                switch selectedTab {
                case .edgeControls:  EdgeControlsTab()
                case .gestures:
                    GesturesTab(device: navigator.device == .trackpad ? .trackpad : .magicMouse)
                        .id(navigator.device)
                case .keyboard:      KeyboardTab()
                case .tuning:
                    if navigator.device == .magicMouse { MagicMouseTab() } else { TuningTab() }
                case .inputMonitoring:
                    InputMonitoringTab(device: navigator.device == .trackpad ? .trackpad : .magicMouse)
                        .id(navigator.device)
                case .general:       GeneralTab()
                case .permissions:   PermissionsTab()
                case .configuration: ConfigurationTab()
                case .about:         AboutTab()
                }
            }
            .navigationTitle(selectedTab == .gestures ? L("%@ Gestures", L(navigator.device.rawValue)) : L(selectedTab.rawValue))
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: navigator.tab) { tab in
            if tab == .edgeControls { navigator.device = .trackpad }
        }
        .onAppear { IconAppearanceMonitor.shared.startWatching() }
        .onDisappear { IconAppearanceMonitor.shared.stopWatching() }
        .onAppear {
            guard managesActivationPolicy else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            engineBridge.recheckAccessibilityPermission()
        }
        .onDisappear {
            guard managesActivationPolicy else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func sidebarRow(_ tab: PrefsTab) -> some View {
        let isOn = navigator.tab == tab
        return Button { navigator.tab = tab } label: {
            Label { Text(L(tab.rawValue)) } icon: { SidebarIconTile(systemImage: tab.systemImage) }
                .fontWeight(isOn ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSelection(isOn, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
