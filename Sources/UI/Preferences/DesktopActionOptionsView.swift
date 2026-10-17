import SwiftUI
import UniformTypeIdentifiers

struct DesktopActionOptionsView: View {
    @Binding var rule: GestureRule
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var desktopActions = DesktopActions.shared
    var body: some View {
        if rule.action == .spaceLeftInstant || rule.action == .spaceRightInstant {
            Toggle("Allow native animated fallback", isOn: $rule.desktopOptions.allowAnimatedFallback)
            Text("Instant switching depends on private macOS APIs. If macOS rejects it, this optional fallback uses your configured Mission Control shortcut.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if rule.action.isStageAction {
            if rule.action != .stageToggle && rule.action != .stageRecentToggle {
                Text("Cycles through recent stages on the display containing the focused window. Each display keeps its own cycle order. With no focused window, uses the pointer's display.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    Button("Test Action") {
                        desktopActions.performStage(rule.action, options: rule.desktopOptions)
                    }
                    Text(desktopActions.stageStatus)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if rule.action == .stagePosition {
                Stepper("Stage position: \(rule.desktopOptions.stagePosition)", value: $rule.desktopOptions.stagePosition, in: 1...32)
            }
            if rule.action == .stageMatching {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target apps").font(.headline)
                        Spacer()
                        Menu("Add running app") {
                            ForEach(store.runningApps()) { app in
                                Button(app.name) {
                                    rule.desktopOptions.stageApps = Array(Set(rule.desktopOptions.stageApps + [app.bundleID])).sorted()
                                }
                            }
                        }
                        Button("Choose Apps…") { chooseApps() }
                    }
                    ForEach(rule.desktopOptions.stageApps, id: \.self) { id in
                        HStack {
                            Text(store.appFilterLabel(for: id))
                            Spacer()
                            Button { rule.desktopOptions.stageApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Remove target app")
                        }
                    }
                    TextField("Window title contains (optional)", text: $rule.desktopOptions.windowTitle)
                        .textFieldStyle(.roundedBorder)
                    Text("Matches a visible stage containing all selected app names and the optional window-title text. These are action targets, separate from Conditions → Apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add Apps"
        guard panel.runModal() == .OK else { return }
        rule.desktopOptions.stageApps = Array(Set(rule.desktopOptions.stageApps + panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })).sorted()
    }
}
