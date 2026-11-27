import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var preferencesStore: PreferencesStore
    @EnvironmentObject var engineBridge:  EngineBridge
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        Button("Settings…") {
            showPreferences()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Toggle("Enable Gestures", isOn: $engineBridge.isEnabled)

        // The same setting as the switch at the top of Preferences ▸ Edge Controls.
        Toggle("Enable Edge Controls", isOn: Binding(
            get: { preferencesStore.edgeControls.enabled },
            set: { value in preferencesStore.updateEdgeControls { $0.enabled = value } }
        ))

        if !preferencesStore.accessibilityGranted {
            Button("⚠️ Grant Accessibility Access…") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Text("\(preferencesStore.rules.filter(\.isActive).count) active gestures")
            .foregroundStyle(.secondary)

        Divider()

        updateItem

        Text("BetterGlideTool \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit BetterGlideTool") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Updates are downloaded and installed inside the app. Checking opens
    /// Settings › About; installing runs here and then offers a relaunch.
    @ViewBuilder
    private var updateItem: some View {
        switch updater.state {
        case .available(let update):
            Button("Install Update \(update.tag)…") {
                // Installs here; the menu then offers Relaunch to Finish Update.
                updater.downloadAndInstall(update)
            }

        case .installed:
            Button("Relaunch to Finish Update") {
                updater.relaunch()
            }

        case .downloading, .installing:
            Text("Updating BetterGlideTool…")
                .foregroundStyle(.secondary)

        case .idle, .checking, .upToDate, .failed, .manualInstall:
            Button("Check for Updates…") {
                // Settings › About shows the check and any update it finds.
                SettingsProcess.open(tab: .about, checkForUpdates: true)
            }
        }
    }

    private func showPreferences(tab: PrefsTab? = nil) {
        // Settings runs in its own process, which quits when its window closes.
        SettingsProcess.open(tab: tab)
    }
}
