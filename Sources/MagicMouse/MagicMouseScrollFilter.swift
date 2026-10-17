import CoreGraphics

/// Reserve only the axes assigned to custom swipes. Mixed-axis events retain
/// native motion on the other axis, including its precision and phase fields.
enum MagicMouseScrollFilter {
    private static let vertical: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1
    ]
    private static let horizontal: [CGEventField] = [
        .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2
    ]
    private static let depth: [CGEventField] = [
        .scrollWheelEventDeltaAxis3, .scrollWheelEventFixedPtDeltaAxis3, .scrollWheelEventPointDeltaAxis3
    ]
    private static func hasMotion(_ event: CGEvent, fields: [CGEventField]) -> Bool {
        fields.contains { event.getDoubleValueField($0) != 0 }
    }

    /// Transform every representation of the selected axis in place; native
    /// momentum/phase metadata and the other axes remain untouched.
    static func invert(_ event: CGEvent, vertical invertVertical: Bool, horizontal invertHorizontal: Bool) {
        let axes = (invertVertical ? [vertical] : []) + (invertHorizontal ? [horizontal] : [])
        for axis in axes {
            // CGEvent's line setter recomputes fixed-point and pixel values.
            // Capture all originals first, then restore precision in this order.
            let lines = event.getIntegerValueField(axis[0])
            let fixed = event.getDoubleValueField(axis[1])
            let pixels = event.getIntegerValueField(axis[2])
            event.setIntegerValueField(axis[0], value: lines == .min ? .max : -lines)
            event.setDoubleValueField(axis[1], value: -fixed)
            event.setIntegerValueField(axis[2], value: pixels == .min ? .max : -pixels)
        }
    }

    /// Returns true only when all motion in this event was reserved. Phase-only
    /// events still pass so a native scroll sequence can end normally.
    static func filter(_ event: CGEvent, reserving axes: MouseScrollAxes) -> Bool {
        guard !axes.isEmpty else { return false }
        let reserved = (axes.contains(.vertical) ? vertical : []) + (axes.contains(.horizontal) ? horizontal : [])
        let consumedMotion = hasMotion(event, fields: reserved)
        for field in reserved { event.setDoubleValueField(field, value: 0) }
        return consumedMotion && !hasMotion(event, fields: vertical + horizontal + depth)
    }
}
