import AppKit
import SwiftUI

// ─────────────────────────────────────────────
// MARK: - Live data between the menu bar app and Settings
//
// The engine runs only in the menu bar app, so what Settings shows live —
// finger contacts, the gesture log, input status lines, the active Edge
// Controls edge — is streamed to it over EngineLink while it's on screen.
// Settings subscribes to what its visible pages need; the menu bar app sends
// only what changed, at most 30 times a second, and stops the moment Settings
// unsubscribes, quits or can't be reached.
// ─────────────────────────────────────────────

struct LiveStreams: Codable, Equatable {
    var trackpadContacts = false
    var mouseContacts = false
    /// Status lines, Magic Mouse connection, pointer speed, Stage Manager result,
    /// Block Real Gesture Triggering and the active Edge Controls edge.
    var status = false

    var isEmpty: Bool { !trackpadContacts && !mouseContacts && !status }
    func contacts(_ device: GestureDevice) -> Bool { device == .trackpad ? trackpadContacts : mouseContacts }
}

enum LiveCommand: String, Codable {
    case startRecording, stopRecording, clearGestureLog, copyReadings, showFloatingPanel, reconnectMouse
}

struct LiveContactsSnapshot: Codable, Equatable {
    var frame: LiveContactFrame
    var transitions: [LiveContactTransition]
    var isRecording: Bool
    var recordedFrameCount: Int
    /// System uptime of the last frame; the same clock in both processes.
    var lastReceived: Double
    var gestures: [LiveGestureEvent]?
}

struct LiveStatus: Codable, Equatable {
    var trackpadLines: [String]
    var mouseLines: [String]
    var mouseConnected: Int
    var pointerMouse: String
    var pointerTrackpad: String
    var stageStatus: String
    var blockActions: Bool
    var activeEdge: TrackpadPhysicalEdge?
    var firedCorner: TrackpadCorner? = nil

    @MainActor static func current() -> LiveStatus {
        let pointer = NativePointerSpeed.shared
        return LiveStatus(trackpadLines: LowFingerTrackpadInput.shared.statusLines,
                          mouseLines: MagicMouseInput.shared.statusLines,
                          mouseConnected: MagicMouseInput.shared.connectedCount,
                          pointerMouse: pointer.mouseStatus, pointerTrackpad: pointer.trackpadStatus,
                          stageStatus: DesktopActions.shared.stageStatus,
                          blockActions: GestureActionBlock.shared.isOn,
                          activeEdge: EdgeControlsController.shared.activeEdge,
                          firedCorner: EdgeControlsController.shared.firedCorner)
    }

    @MainActor func apply() {
        LowFingerTrackpadInput.shared.applyRemote(statusLines: trackpadLines)
        MagicMouseInput.shared.applyRemote(statusLines: mouseLines, connectedCount: mouseConnected)
        NativePointerSpeed.shared.applyRemote(mouse: pointerMouse, trackpad: pointerTrackpad)
        DesktopActions.shared.applyRemote(stageStatus: stageStatus)
        GestureActionBlock.shared.applyRemote(blockActions)
        let controller = EdgeControlsController.shared
        if controller.activeEdge != activeEdge { controller.activeEdge = activeEdge }
        if controller.firedCorner != firedCorner { controller.firedCorner = firedCorner }
    }
}

// MARK: - Menu bar app side

@MainActor
final class LiveStreamServer {
    static let shared = LiveStreamServer()
    private init() {}

    /// The owner name this server uses on the menu bar app's monitors.
    static let monitorOwner = "settings-process"

    private var subscriber: pid_t?
    private var streams = LiveStreams()
    private var exitWatch: DispatchSourceProcess?
    private var timer: Timer?
    private var sentContacts: [GestureDevice: LiveContactsSnapshot] = [:]
    private var sentStatus: LiveStatus?

    var isStreaming: Bool { subscriber != nil && !streams.isEmpty }

    func handle(_ message: LinkMessage) {
        switch message {
        case let .subscribe(pid, wanted):
            subscribe(pid: pid, streams: wanted)
        case let .liveCommand(device, command):
            run(command, on: device)
        case let .setBlockActions(on):
            GestureActionBlock.shared.isOn = on
        case let .exportRecording(device, path):
            let result = LiveContactsMonitor.forDevice(device).exportRecording(to: URL(fileURLWithPath: path))
            reply(.liveResult(device: device, message: result ?? "Export failed."))
        default:
            break
        }
    }

    private func subscribe(pid: pid_t, streams wanted: LiveStreams) {
        if subscriber != pid { endSubscription() }
        guard !wanted.isEmpty, pid > 0 else { endSubscription(); return }
        if subscriber == nil {
            subscriber = pid
            watchExit(of: pid)
        }
        for device in GestureDevice.allCases {
            let monitor = LiveContactsMonitor.forDevice(device)
            if wanted.contacts(device) != streams.contacts(device) {
                monitor.setVisible(wanted.contacts(device), owner: Self.monitorOwner)
                sentContacts[device] = nil
            }
        }
        if wanted.status && !streams.status { sentStatus = nil }
        streams = wanted
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                MainActor.assumeIsolated { LiveStreamServer.shared.tick() }
            }
        }
        tick()
    }

    /// Stops streaming and hands the monitors back. Runs when Settings
    /// unsubscribes, quits or stops answering, so nothing it switched on (the
    /// monitors, and with them Block Real Gesture Triggering) outlives it.
    func endSubscription() {
        timer?.invalidate(); timer = nil
        exitWatch?.cancel(); exitWatch = nil
        for device in GestureDevice.allCases where streams.contacts(device) {
            LiveContactsMonitor.forDevice(device).setVisible(false, owner: Self.monitorOwner)
        }
        subscriber = nil
        streams = LiveStreams()
        sentContacts = [:]
        sentStatus = nil
    }

    private func watchExit(of pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { LiveStreamServer.shared.endSubscription() } }
        source.resume()
        exitWatch = source
        if kill(pid, 0) != 0, errno == ESRCH { endSubscription() }
    }

    private func tick() {
        guard subscriber != nil else { return }
        for device in GestureDevice.allCases where streams.contacts(device) {
            let monitor = LiveContactsMonitor.forDevice(device)
            let previous = sentContacts[device]
            let gesturesChanged = previous == nil || monitor.gestures != (previous?.gestures ?? [])
            var snapshot = monitor.snapshot(includingGestures: true)
            if let previous, snapshot.frame == previous.frame, snapshot.transitions == previous.transitions,
               snapshot.isRecording == previous.isRecording, snapshot.recordedFrameCount == previous.recordedFrameCount,
               !gesturesChanged { continue }
            let full = snapshot
            if !gesturesChanged { snapshot.gestures = nil }
            guard reply(.liveContacts(device: device, snapshot: snapshot)) else { return }   // retried next tick
            sentContacts[device] = full
        }
        if streams.status {
            let status = LiveStatus.current()
            if status != sentStatus {
                guard reply(.liveStatus(status)) else { return }
                sentStatus = status
            }
        }
    }

    private func run(_ command: LiveCommand, on device: GestureDevice) {
        let monitor = LiveContactsMonitor.forDevice(device)
        switch command {
        case .startRecording:    monitor.startRecording()
        case .stopRecording:     monitor.stopRecording()
        case .clearGestureLog:   monitor.clearGestureLog()
        case .copyReadings:      reply(.liveResult(device: device, message: monitor.copyReadings() ?? ""))
        case .showFloatingPanel: LiveContactsPanelController.forDevice(device).show()
        case .reconnectMouse:    MagicMouseInput.shared.reconnect()
        }
        tick()
    }

    /// Sends to the subscribed Settings process. If it's busy the update is
    /// skipped and resent on the next tick; if nobody is listening any more,
    /// the subscription ends.
    @discardableResult
    private func reply(_ message: LinkMessage) -> Bool {
        guard let subscriber else { return false }
        switch EngineLink.deliver(message, to: EngineLink.settingsPortName(pid: subscriber), timeout: 0.1) {
        case .delivered:  return true
        case .busy:       return false
        case .noListener:
            AppLogger.debug("[Live] Settings stopped listening; ending the stream")
            endSubscription()
            return false
        }
    }
}

// MARK: - Settings side

@MainActor
final class LiveStreamClient {
    static let shared = LiveStreamClient()
    private init() {}

    private var statusViewers = 0
    private var sent: LiveStreams?
    private var heartbeat: Timer?

    /// Pages that show status lines or the active edge call this on appear
    /// and disappear (see `liveStatus()`).
    func statusViewer(_ visible: Bool) {
        statusViewers = max(0, statusViewers + (visible ? 1 : -1))
        updateSubscription()
    }

    /// Tells the menu bar app what's on screen now. Called whenever a live view
    /// appears or disappears.
    func updateSubscription() {
        guard AppMode.isSettings else { return }
        let wanted = currentStreams
        guard wanted != sent else { return }
        if AppMode.tellMenuBarApp(.subscribe(settingsPID: getpid(), streams: wanted)) {
            sent = wanted
        } else {
            AppLogger.debug("[Live] Couldn't reach the menu bar app to subscribe")
        }
        // While anything live is on screen, repeat the subscription every second.
        // The menu bar app ignores repeats, but resumes one it had dropped.
        if wanted.isEmpty {
            heartbeat?.invalidate(); heartbeat = nil
        } else if heartbeat == nil {
            heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let client = LiveStreamClient.shared
                    let streams = client.currentStreams
                    guard !streams.isEmpty else { return }
                    if AppMode.tellMenuBarApp(.subscribe(settingsPID: getpid(), streams: streams)) { client.sent = streams }
                }
            }
        }
    }

    private var currentStreams: LiveStreams {
        LiveStreams(trackpadContacts: LiveContactsMonitor.shared.isEnabled,
                    mouseContacts: LiveContactsMonitor.mouse.isEnabled,
                    status: statusViewers > 0)
    }

    func handle(_ message: LinkMessage) {
        switch message {
        case let .liveContacts(device, snapshot):
            LiveContactsMonitor.forDevice(device).applyRemote(snapshot)
        case let .liveStatus(status):
            status.apply()
        case let .liveResult(device, text):
            if !text.isEmpty { LiveContactsMonitor.forDevice(device).applyRemoteResult(text) }
        default:
            break
        }
    }
}

private struct LiveStatusViewer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { LiveStreamClient.shared.statusViewer(true) }
            .onDisappear { LiveStreamClient.shared.statusViewer(false) }
    }
}

extension View {
    /// Marks a page that shows live engine status, so Settings streams it from
    /// the menu bar app while the page is on screen. No effect in the menu bar app.
    func liveStatus() -> some View { modifier(LiveStatusViewer()) }
}
