import SwiftUI

struct TipTapTuningCard: View {
    let device: GestureDevice
    @EnvironmentObject var store: PreferencesStore
    private var mouse: Bool { device == .magicMouse }
    private var tuning: TipTapTuning { mouse ? store.deviceTuning.mouseTipTap : store.deviceTuning.trackpadTipTap }
    private func binding<T>(_ key: WritableKeyPath<TipTapTuning, T>) -> Binding<T> {
        Binding(get: { tuning[keyPath: key] }, set: { value in
            store.updateDeviceTuning {
                if mouse { $0.mouseTipTap[keyPath: key] = value }
                else { $0.trackpadTipTap[keyPath: key] = value }
            }
        })
    }
    var body: some View {
        TuningSection(title: "TipTaps", icon: "hand.tap") {
            VStack(alignment: .leading, spacing: 18) {
                slider(mouse ? "Magic Mouse TipTap sensitivity" : "TipTap sensitivity", key: \.sensitivity, range: 0.05...1, low: "Lighter Touch", high: "Harder Touch")
                if !mouse {
                    Toggle("1 Finger TipTap: Allow Finger Movement", isOn: binding(\.allowFingerMovement))
                }
                Divider()
                slider(mouse ? "Magic Mouse Two Finger TipTap sensitivity" : "Two Finger TipTap sensitivity", key: \.twoFingerSensitivity, range: 0.05...1, low: "Lighter Touch", high: "Harder Touch")
                if mouse {
                    Toggle("Allow sensitive TipTaps", isOn: binding(\.allowSensitiveTipTaps))
                    Text("Uncheck if TipTaps are too sensitive or often trigger accidentally.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("TipTap spacing") {
                        VStack(alignment: .leading, spacing: 16) {
                            slider("Minimum spacing with one resting finger", key: \.twoFingerMinimumDistance, range: 0.01...min(0.3, tuning.maximumDistance), low: "Close Together", high: "Far Apart")
                            slider("Minimum spacing with two resting fingers", key: \.threeFingerMinimumDistance, range: 0.01...min(0.3, tuning.maximumDistance), low: "Close Together", high: "Far Apart")
                            slider("Maximum gap to nearest resting finger", key: \.maximumDistance, range: 0.05...1, low: "Close", high: "Far Apart")
                            Text("Mouse spacing measures sideways gaps across the mouse width. The maximum applies to the nearest resting finger, not the full three-finger spread. Timing and movement limits still apply.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    }
                } else {
                    slider("Two Finger Tip Taps minimum required distance between fingers", key: \.twoFingerMinimumDistance, range: 0.01...min(0.3, tuning.maximumDistance), low: "Close Together", high: "Far Apart")
                    Divider()
                    slider("Three Finger TipTap sensitivity", key: \.threeFingerSensitivity, range: 0.05...1, low: "Lighter Touch", high: "Harder Touch")
                    slider("Three Finger Tip Taps minimum required distance between fingers", key: \.threeFingerMinimumDistance, range: 0.01...min(0.3, tuning.maximumDistance), low: "Close Together", high: "Far Apart")
                    Divider()
                    slider("Maximum allowed distance between fingers", key: \.maximumDistance, range: 0.05...1, low: "Close", high: "Far Apart")
                    Text("Trackpad spacing includes vertical separation, so fingers can be staggered instead of lined up horizontally.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Sensitivity uses the tapping finger’s contact size reported by the device. Higher values reject lighter touches. " + (mouse ? "The two controls apply with one and two resting fingers respectively. " : "The three controls apply with one, two and three resting fingers respectively. ") + "Timing above still applies.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Reset to Defaults…") {
                        store.updateDeviceTuning {
                            if mouse { $0.mouseTipTap = .mouseDefaults }
                            else { $0.trackpadTipTap = .trackpadDefaults }
                        }
                    }.disabled(tuning == (mouse ? .mouseDefaults : .trackpadDefaults))
                }
            }.padding(16)
        }
    }
    private func slider(_ title: String, key: WritableKeyPath<TipTapTuning, Double>, range: ClosedRange<Double>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            HStack {
                Slider(value: binding(key), in: range, step: 0.01).accessibilityLabel(title)
                Text(tuning[keyPath: key], format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack { Text(low); Spacer(); Text(high) }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
