import SwiftUI

struct MagicMouseTab: View {
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var input = MagicMouseInput.shared
    private var settings: MagicMouseSettings { store.magicMouse }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TuningSection(title: "Magic Mouse", icon: "magicmouse") {
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
                        Text("Lift your fingers, then tap lightly without pressing the mouse button. Two-finger tap clicks the middle button by default; three-finger tap opens Mission Control. Physical clicks and one-finger scrolling keep working normally.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(12)
                }
                if settings.enabled {
                    TuningSection(title: "Tap actions", icon: "hand.tap") {
                        assignments(swipes: false)
                    }
                    TuningSection(title: "Two-finger swipes", icon: "arrow.left.and.right") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Swipes are off by default. Assign actions below to use both fingers together. Turn off overlapping gestures in System Settings → Mouse → More Gestures to avoid a second macOS action.")
                                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 12)
                            assignments(swipes: true)
                        }
                    }
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
                    Text("Trackpad gestures, TrackPoint, edge sliders, and force-click remain trackpad features. Magic Mouse has no pressure sensor or haptic motor.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Reset Magic Mouse to Defaults") {
                        store.updateMagicMouse { $0 = MagicMouseSettings() }
                    }
                }
            }.padding()
        }
    }

    private func binding(_ key: WritableKeyPath<MagicMouseSettings, Double>) -> Binding<Double> {
        Binding(get: { settings[keyPath: key] }, set: { value in store.updateMagicMouse { $0[keyPath: key] = value } })
    }
    private func assignments(swipes: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(MagicMouseGesture.allCases.filter { $0.isSwipe == swipes }) { gesture in
                HStack {
                    Text(gesture.title)
                    Spacer()
                    Picker(gesture.title, selection: Binding(
                        get: { settings.action(for: gesture) },
                        set: { action in store.updateMagicMouse { $0.bindings[gesture] = action } })) {
                            ForEach(MagicMouseAction.allCases) { action in Text(action.rawValue).tag(action) }
                        }.labelsHidden().frame(width: 230)
                }
            }
        }.padding(12)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(display).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
