import Foundation

struct DeviceTuningSettings: Equatable {
    var trackpadTipTap = TipTapTuning.trackpadDefaults
    var mouseTipTap = TipTapTuning.mouseDefaults
    var trackpadSensitivity = 0.5
    var mouseSensitivity = 0.5
    var trackpadPointerSpeed = 1.0
    var mousePointerSpeed = 1.0
    var trackpadTipTapMinimum = 0.08
    var mouseTipTapMinimum = 0.08
    var trackpadTipTapAnchor = 0.25
    var mouseTipTapAnchor = 0.25

    static func normalized(_ value: Self) -> Self {
        var result = value
        result.trackpadTipTap = TipTapTuning.normalized(value.trackpadTipTap)
        result.mouseTipTap = TipTapTuning.normalized(value.mouseTipTap)
        func clamp(_ number: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
        }
        result.trackpadSensitivity = clamp(value.trackpadSensitivity, 0...1, 0.5)
        result.mouseSensitivity = clamp(value.mouseSensitivity, 0...1, 0.5)
        result.trackpadPointerSpeed = clamp(value.trackpadPointerSpeed, 0.2...4, 1)
        result.mousePointerSpeed = clamp(value.mousePointerSpeed, 0.2...4, 1)
        result.trackpadTipTapMinimum = clamp(value.trackpadTipTapMinimum, 0.04...0.2, 0.08)
        result.mouseTipTapMinimum = clamp(value.mouseTipTapMinimum, 0.04...0.2, 0.08)
        result.trackpadTipTapAnchor = clamp(value.trackpadTipTapAnchor, 0.12...0.6, 0.25)
        result.mouseTipTapAnchor = clamp(value.mouseTipTapAnchor, 0.12...0.6, 0.25)
        return result
    }
    func thresholdScale(for device: GestureDevice) -> Double {
        pow(2, ((device == .trackpad ? trackpadSensitivity : mouseSensitivity) - 0.5) * 2)
    }
    func applying(to settings: MagicMouseSettings, device: GestureDevice) -> MagicMouseSettings {
        var result = settings
        result.tipTapSpacingGeometry = device == .magicMouse ? .magicMouse : .surface
        result.tipTap = device == .trackpad ? trackpadTipTap : mouseTipTap
        result.tipTapMinimumDuration = device == .trackpad ? trackpadTipTapMinimum : mouseTipTapMinimum
        result.tipTapAnchorDuration = device == .trackpad ? trackpadTipTapAnchor : mouseTipTapAnchor
        let scale = thresholdScale(for: device)
        result.swipeDistance *= scale
        result.tapMovement /= scale
        result.tapDuration = min(0.6, max(0.08, result.tapDuration / sqrt(scale)))
        return result
    }
}
