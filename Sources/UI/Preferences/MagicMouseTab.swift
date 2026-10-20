import SwiftUI

struct MagicMouseTab: View {
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var input = MagicMouseInput.shared
    private var settings: MagicMouseSettings { store.magicMouse }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TuningSection(title: "Connection", icon: "magicmouse") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable Magic Mouse gestures", isOn: Binding(
                            get: { settings.enabled }, set: { value in store.updateMagicMouse { $0.enabled = value } }))
                        HStack {
                            Label(input.status, systemImage: input.connectedCount > 0 ? "checkmark.circle" : "info.circle")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reconnect") { input.reconnect() }
                                .disabled(!settings.enabled)
                        }
                        Text("Lift your fingers, then tap lightly without pressing the mouse button. Two-finger tap clicks the middle button by default; three-finger tap opens Mission Control. Unassigned physical clicks keep working normally. Unassigned swipes keep native scrolling.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(12)
                }
                DeviceTuningCard(device: .magicMouse)
                TipTapTuningCard(device: .magicMouse)
                TuningSection(title: "Scrolling", icon: "scroll") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Invert vertical scrolling", isOn: Binding(
                            get: { settings.invertVerticalScrolling }, set: { value in store.updateMagicMouse { $0.invertVerticalScrolling = value } }))
                        Divider()
                        Toggle("Invert horizontal scrolling", isOn: Binding(
                            get: { settings.invertHorizontalScrolling }, set: { value in store.updateMagicMouse { $0.invertHorizontalScrolling = value } }))
                        Divider()
                        Text("Reverses the current macOS direction for Magic Mouse only, including momentum. Trackpad scrolling keeps its macOS setting. Enable Magic Mouse gestures above to use these options.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                }
                if settings.enabled {
                    Text("Swipes start off. A single-finger swipe shares the mouse's scrolling surface; assign it only if you want that motion to trigger an action. Turn off overlapping gestures in System Settings → Mouse → More Gestures.")
                        .font(.callout).foregroundStyle(.secondary)
                    TuningSection(title: "Touch sensitivity", icon: "slider.horizontal.3") {
                        VStack(alignment: .leading, spacing: 14) {
                            slider("Maximum tap duration", value: binding(\.tapDuration), range: 0.10...0.45,
                                   display: String(format: "%.2f s", settings.tapDuration))
                            slider("Tap movement tolerance", value: binding(\.tapMovement), range: 0.01...0.08,
                                   display: String(format: "%.1f%%", settings.tapMovement * 100))
                            slider("Swipe distance", value: binding(\.swipeDistance), range: 0.10...0.45,
                                   display: String(format: "%.0f%%", settings.swipeDistance * 100))
                            Text("Smaller tap tolerance rejects more accidental taps. Longer swipe distance requires a more deliberate movement.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(12)
                    }
                    Text("Edge sliders and force-click remain trackpad features. Magic Mouse has no pressure sensor or haptic motor.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Reset Connection & Sensitivity") {
                        store.updateMagicMouse { $0 = MagicMouseSettings() }
                        store.updateDeviceTuning { $0.mouseSensitivity = 0.5; $0.mouseTipTapMinimum = 0.08; $0.mouseTipTapAnchor = 0.25 }
                    }
                }
            }.padding()
        }
    }

    private func binding(_ key: WritableKeyPath<MagicMouseSettings, Double>) -> Binding<Double> {
        Binding(get: { settings[keyPath: key] }, set: { value in store.updateMagicMouse { $0[keyPath: key] = value } })
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(display).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
