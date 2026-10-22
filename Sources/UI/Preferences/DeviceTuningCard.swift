import SwiftUI

struct DeviceTuningCard: View {
    /// The groups of controls this card shows, so each Tuning tab can carry
    /// only its own.
    enum Part { case sensitivity, tipTapTiming, pointer }
    let device: GestureDevice
    var parts: Set<Part> = [.sensitivity, .tipTapTiming, .pointer]
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var pointer = NativePointerSpeed.shared
    private var mouse: Bool { device == .magicMouse }
    private var sensitivity: Binding<Double> {
        Binding(get: { mouse ? store.deviceTuning.mouseSensitivity : store.deviceTuning.trackpadSensitivity },
                set: { value in store.updateDeviceTuning { if mouse { $0.mouseSensitivity = value } else { $0.trackpadSensitivity = value } } })
    }
    private var speed: Binding<Double> {
        Binding(get: { mouse ? store.deviceTuning.mousePointerSpeed : store.deviceTuning.trackpadPointerSpeed },
                set: { value in store.updateDeviceTuning { if mouse { $0.mousePointerSpeed = value } else { $0.trackpadPointerSpeed = value } } })
    }
    private var tipMinimum: Binding<Double> {
        Binding(get: { mouse ? store.deviceTuning.mouseTipTapMinimum : store.deviceTuning.trackpadTipTapMinimum },
                set: { value in store.updateDeviceTuning { if mouse { $0.mouseTipTapMinimum = value } else { $0.trackpadTipTapMinimum = value } } })
    }
    private var tipAnchor: Binding<Double> {
        Binding(get: { mouse ? store.deviceTuning.mouseTipTapAnchor : store.deviceTuning.trackpadTipTapAnchor },
                set: { value in store.updateDeviceTuning { if mouse { $0.mouseTipTapAnchor = value } else { $0.trackpadTipTapAnchor = value } } })
    }
    var body: some View {
        TuningSection(title: parts == [.tipTapTiming] ? "TipTap Timing" : (mouse ? "Magic Mouse" : "Trackpad & Magic Trackpad"),
                      icon: parts == [.tipTapTiming] ? "timer" : (mouse ? "magicmouse" : "rectangle.and.hand.point.up.left")) {
            HStack(alignment: .center, spacing: 20) {
                Image(systemName: mouse ? "magicmouse.fill" : "rectangle.fill")
                    .font(.system(size: 42)).foregroundStyle(.secondary)
                    .frame(width: 62)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 24) {
                    if parts.contains(.sensitivity) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gesture sensitivity").font(.headline)
                        HStack {
                            Text("Easier to trigger").font(.caption)
                            Slider(value: sensitivity, in: 0...1).accessibilityLabel("Gesture sensitivity")
                            Text("Harder to trigger").font(.caption)
                        }
                        Text("Adjusts swipe distance and tap tolerance. The midpoint keeps your existing tuning.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    if parts.contains(.tipTapTiming) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TipTap timing").font(.headline)
                        HStack { Text("Fixed finger rest time"); Spacer(); Text(String(format: "%.0f ms", tipAnchor.wrappedValue * 1000)).monospacedDigit() }
                        Slider(value: tipAnchor, in: 0.12...0.6, step: 0.01).accessibilityLabel("TipTap fixed finger rest time")
                        HStack { Text("Minimum tap duration"); Spacer(); Text(String(format: "%.0f ms", tipMinimum.wrappedValue * 1000)).monospacedDigit() }
                        Slider(value: tipMinimum, in: 0.04...0.2, step: 0.01).accessibilityLabel("TipTap minimum tap duration")
                        Text("Increase these times to reject quick accidental touches. The action fires after the tapping finger lifts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    if parts.contains(.pointer) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pointer speed").font(.headline)
                        HStack {
                            Slider(value: speed, in: 0.2...4, step: 0.1).accessibilityLabel("Pointer speed")
                            TextField("Multiplier", value: speed, format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder).frame(width: 58)
                                .accessibilityLabel("Pointer speed multiplier")
                            Text("×")
                            Button("Reset") { speed.wrappedValue = 1 }
                                .disabled(speed.wrappedValue == 1)
                        }
                        Text(mouse ? "Native Magic Mouse tracking. Effect varies with movement speed. 1× restores the original speed." : "Keeps native macOS acceleration. Effect varies with movement speed. 1× restores the original speed.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(mouse ? pointer.mouseStatus : pointer.trackpadStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }
            }.padding(16)
        }
    }
}
