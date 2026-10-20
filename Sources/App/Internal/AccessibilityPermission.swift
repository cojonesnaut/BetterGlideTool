import AppKit
import ApplicationServices

/// macOS remains the authority. A previous user choice never substitutes for a
/// fresh trust check, and automatic launch prompts are shown at most once.
enum AccessibilityPermission {
    private static let requestedKey = "accessibilityPromptRequested"
    static var isGranted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }
    static func shouldAutomaticallyRequest(granted: Bool, previouslyRequested: Bool) -> Bool {
        !granted && !previouslyRequested
    }
    static func requestAutomaticallyIfNeeded() {
        guard shouldAutomaticallyRequest(granted: isGranted, previouslyRequested: UserDefaults.standard.bool(forKey: requestedKey)) else { return }
        request()
    }
    static func request() {
        guard !isGranted else { return }
        UserDefaults.standard.set(true, forKey: requestedKey)
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
