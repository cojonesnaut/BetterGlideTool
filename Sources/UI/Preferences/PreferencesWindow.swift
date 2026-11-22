import SwiftUI
import AppKit

enum PrefsTab: String, CaseIterable, Identifiable {
    case gestures      = "Gestures"
    case keyboard      = "Keyboard"
    case edgeControls  = "Edge Controls"
    case tuning        = "Tuning"
    case inputMonitoring = "Input Monitoring"
    case general       = "General"
    case configuration = "Configuration"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .edgeControls:  return "rectangle.inset.filled"
        case .gestures:      return "hand.draw"
        case .keyboard:      return "keyboard"
        case .tuning:        return "slider.horizontal.3"
        case .inputMonitoring: return "waveform.path"
        case .general:       return "gearshape"
        case .configuration: return "doc.text"
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
            List(selection: $navigator.tab) {
                Section(L(navigator.device.rawValue)) {
                    ForEach(navigator.device.tabs) { tab in
                        Label(L(tab.rawValue), systemImage: tab.systemImage).tag(tab)
                    }
                }
                Section("Shared") {
                    ForEach([PrefsTab.keyboard, .general, .configuration]) { tab in
                        Label(L(tab.rawValue), systemImage: tab.systemImage).tag(tab)
                    }
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
            .safeAreaInset(edge: .bottom) { sidebarStatus }
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
                case .configuration: ConfigurationTab()
                }
            }
            .navigationTitle(selectedTab == .gestures ? L("%@ Gestures", L(navigator.device.rawValue)) : L(selectedTab.rawValue))
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: navigator.tab) { tab in
            if tab == .edgeControls { navigator.device = .trackpad }
        }
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

    /// Engine status pinned under the sidebar — visible from every tab.
    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Toggle(isOn: $engineBridge.isEnabled) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engineBridge.isEnabled && preferencesStore.accessibilityGranted ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(engineBridge.isEnabled
                         ? (preferencesStore.accessibilityGranted ? "Gestures active" : "Needs permission")
                         : "Gestures paused")
                        .font(.callout)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
