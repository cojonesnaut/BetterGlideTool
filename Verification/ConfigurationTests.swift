import Foundation

@main
struct ConfigurationTests {
    static func main() {
        var config = GlideConfig()
        config.magicMouse.enabled = false
        config.magicMouse.tapDuration = 0.31
        config.magicMouse.tapMovement = 0.04
        config.magicMouse.swipeDistance = 0.27
        for gesture in MagicMouseGesture.allCases { config.magicMouse.bindings[gesture] = .volumeDown }
        config.magicMouse.bindings[.twoFingerTap] = MagicMouseAction.none
        let serialized = GlideConfigSerializer.serialize(config)
        guard let decoded = GlideConfigParser.parse(yaml: serialized) else { fatalError("Cannot decode exported configuration") }
        precondition(decoded.magicMouse == config.magicMouse, "Mouse settings do not round-trip")
        Settings.shared.apply(decoded)
        precondition(GlideConfig.fromSettings().magicMouse == config.magicMouse, "Settings bridge lost mouse configuration")
        guard let legacy = GlideConfigParser.parse(yaml: "touchpad:\n  preferences:\n    haptic_feedback: false\n") else { fatalError("Legacy config failed") }
        precondition(legacy.magicMouse == MagicMouseSettings(), "Legacy configs need defaults")
        let unknown = GlideConfigParser.parse(yaml: "touchpad:\n  magic_mouse:\n    two_finger_tap: Unknown Action\n    swipe_distance: -8\n")!
        precondition(unknown.magicMouse.action(for: .twoFingerTap) == .none)
        precondition(unknown.magicMouse.swipeDistance == 0.1)
        let reordered = GlideConfigParser.parse(yaml: "touchpad:\n  magic_mouse:\n    enabled: false\n  edge_controls:\n    enabled: false\n")!
        precondition(!reordered.magicMouse.enabled && !reordered.edgeControls.enabled)
        precondition(MemoryLayout<GLDMTTouch>.stride == 96, "Unexpected multitouch ABI layout")
        precondition(MemoryLayout<GLDMTTouch>.offset(of: \.normalized) == 32)
        print("PASS: configuration round-trip, legacy import, unknown actions, normalization, reordered sections, shared ABI")
    }
}
