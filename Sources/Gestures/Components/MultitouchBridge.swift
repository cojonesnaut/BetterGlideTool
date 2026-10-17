import Foundation

// ─────────────────────────────────────────────
// MARK: - MultitouchBridge
// ─────────────────────────────────────────────

final class MultitouchBridge {

    static let shared = MultitouchBridge()
    private init() {}

    private(set) var isRunning = false

    // MARK: Start

    func start(callback: @escaping GLDTFrameCallback) {
        guard !isRunning else { return }
        if GLDTStart(callback, nil) {
            isRunning = true
            AppLogger.debug("[MT] Started C-Bridge")
        } else {
            AppLogger.debug("[MT] Failed to start C-Bridge. Status: \(GLDTGetLastStartStatus())")
        }
    }

    // MARK: Stop

    func stop() {
        guard isRunning else { return }
        GLDTStop()
        isRunning = false
        AppLogger.debug("[MT] Stopped C-Bridge")
    }

    // MARK: Recovery

    /// Whether the trackpad is still actually feeding the bridge. `isRunning` only
    /// records that Glide asked for a device; this asks the device.
    var isDeviceRunning: Bool { GLDTIsDeviceRunning() }

    /// Acquires a new device. The old handle can outlive the hardware it stood for
    /// across a sleep/wake cycle, so recovery means replacing it rather than
    /// starting it again.
    func restart(callback: @escaping GLDTFrameCallback) {
        stop()
        start(callback: callback)
        AppLogger.debug("[MT] Rebuilt device (running: \(isDeviceRunning))")
    }

    // MARK: Frame gating

    /// Fewest contacts a frame must carry to reach Swift. Defaults to 3. Active low-finger rules, Edge Controls or Live
    /// Contacts lower it to 1; ordinary cursor work otherwise stays inside the C bridge.
    func setMinimumContactCount(_ count: Int) {
        GLDTSetMinimumContactCount(Int32(count))
    }

    /// Coordinates every low-contact feature's requirement so none overrides another.
    func updateMinimumContactCount() {
        let edgeControlsActive = Settings.shared.edgeControls.enabled && (
            Settings.shared.edgeControls.topEdge != .none ||
            Settings.shared.edgeControls.bottomEdge != .none ||
            Settings.shared.edgeControls.leftEdge != .none ||
            Settings.shared.edgeControls.rightEdge != .none
        )
        let lowFingerActive = LowFingerTrackpadInput.recognitionSettings(rules: Settings.shared.rules).enabled
        let liveContactsActive = LiveContactsMonitor.shared.isEnabled
        GLDTSetContactDetailsEnabled(lowFingerActive || liveContactsActive)
        setMinimumContactCount((edgeControlsActive || lowFingerActive || liveContactsActive) ? 1 : 3)
    }
}
