import Foundation

/// Live data from the menu bar app to Settings (LiveStream.swift). This test
/// process plays both: LiveStreamServer as the menu bar app, and a listener on
/// its own Settings port as the Settings process.
@MainActor
func verifyLiveStream() {
    func spin(_ seconds: TimeInterval = 0.3, until done: () -> Bool = { false }) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }
    let server = LiveStreamServer.shared
    let trackpad = LiveContactsMonitor.shared, mouse = LiveContactsMonitor.mouse
    let me = getpid()
    var inbox: [LinkMessage] = []
    precondition(EngineLink.listen(on: EngineLink.settingsPortName(pid: me)) { inbox.append($0) })
    defer { EngineLink.stopListening(on: EngineLink.settingsPortName(pid: me)); server.endSubscription() }

    // Every live message survives encoding.
    let snapshot = LiveContactsSnapshot(
        frame: LiveContactFrame(timestamp: 3, appName: "Safari", contacts: [LiveContact(id: 1, state: 4, x: 0.25, y: 0.5, size: 0.8, role: "Anchor")], feedback: "Resting"),
        transitions: [LiveContactTransition(timestamp: 3, id: 1, landed: true)],
        isRecording: true, recordedFrameCount: 12, lastReceived: 99.5, gestures: nil)
    let status = LiveStatus(trackpadLines: ["a", "b", "c", "d", "e"], mouseLines: ["m", "n", "o", "p"], mouseConnected: 1,
                            pointerMouse: "1.5×", pointerTrackpad: "1×", stageStatus: "Switched", blockActions: true, activeEdge: .left,
                            firedCorner: .bottomRight)
    let samples: [LinkMessage] = [
        .subscribe(settingsPID: me, streams: LiveStreams(trackpadContacts: true, mouseContacts: false, status: true)),
        .liveCommand(device: .magicMouse, command: .reconnectMouse), .setBlockActions(true),
        .exportRecording(device: .trackpad, path: "/tmp/x.json"),
        .liveContacts(device: .trackpad, snapshot: snapshot), .liveStatus(status),
        .liveResult(device: .magicMouse, message: "Recording exported."),
    ]
    for message in samples {
        precondition(EngineLink.decode(try! PropertyListEncoder().encode(message)) == message, "\(message) round-trips")
    }

    // Subscribing turns on the menu bar app's monitor and streams its state.
    precondition(!trackpad.isEnabled && !mouse.isEnabled, "monitors start off")
    server.handle(.subscribe(settingsPID: me, streams: LiveStreams(trackpadContacts: true, mouseContacts: false, status: true)))
    precondition(trackpad.isEnabled && !mouse.isEnabled && server.isStreaming, "only the wanted monitor is on")
    spin(1) { inbox.contains { if case .liveStatus = $0 { return true }; return false }
              && inbox.contains { if case .liveContacts(.trackpad, _) = $0 { return true }; return false } }
    precondition(inbox.contains { if case .liveStatus = $0 { return true }; return false }, "status is streamed")
    precondition(inbox.contains { if case let .liveContacts(.trackpad, s) = $0 { return s.gestures != nil }; return false },
                 "the first contacts message carries the gesture log")

    // Unchanged state isn't resent.
    inbox.removeAll(); spin(0.4)
    precondition(inbox.isEmpty, "nothing is sent while nothing changes (got \(inbox.count))")

    // Settings repeats its subscription every second: repeats change nothing,
    // and a repeat after the stream was dropped resumes it.
    let streamsNow = LiveStreams(trackpadContacts: true, mouseContacts: false, status: true)
    server.handle(.subscribe(settingsPID: me, streams: streamsNow)); spin(0.3)
    precondition(inbox.isEmpty && server.isStreaming, "a repeated subscription resends nothing")
    server.endSubscription()
    precondition(!server.isStreaming && !trackpad.isEnabled)
    server.handle(.subscribe(settingsPID: me, streams: streamsNow))
    spin(1) { inbox.contains { if case .liveContacts(.trackpad, _) = $0 { return true }; return false } }
    precondition(server.isStreaming && trackpad.isEnabled
                 && inbox.contains { if case let .liveContacts(.trackpad, s) = $0 { return s.gestures != nil }; return false },
                 "a repeat after a drop resumes the stream with full state")
    inbox.removeAll()

    // A dispatched gesture reaches Settings in the log.
    trackpad.recordGesture("3 Finger Swipe Up", action: "Mission Control", appName: "Finder")
    spin(1) { inbox.contains { if case let .liveContacts(.trackpad, s) = $0 { return s.gestures?.first?.gesture == "3 Finger Swipe Up" }; return false } }
    precondition(inbox.contains { if case let .liveContacts(.trackpad, s) = $0 { return s.gestures?.first?.gesture == "3 Finger Swipe Up" }; return false },
                 "a new gesture is streamed")

    // Block Real Gesture Triggering from Settings takes effect, and is echoed back.
    inbox.removeAll()
    server.handle(.setBlockActions(true))
    precondition(GestureActionBlock.shared.blocksActions, "blocking applies while Settings is watching")
    spin(1) { inbox.contains { if case let .liveStatus(s) = $0 { return s.blockActions }; return false } }
    precondition(inbox.contains { if case let .liveStatus(s) = $0 { return s.blockActions }; return false }, "the switch is echoed")

    // Unsubscribing hands the monitor back, so blocking lapses with it.
    server.handle(.subscribe(settingsPID: me, streams: LiveStreams()))
    precondition(!trackpad.isEnabled && !server.isStreaming && !GestureActionBlock.shared.blocksActions,
                 "an empty subscription releases everything")

    // A Settings process that dies without unsubscribing is noticed.
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["0.4"]
    try! child.run()
    // Answer on the child's port so only its exit, not an unreachable port, ends this.
    let childPort = EngineLink.settingsPortName(pid: child.processIdentifier)
    precondition(EngineLink.listen(on: childPort) { _ in })
    defer { EngineLink.stopListening(on: childPort) }
    server.handle(.subscribe(settingsPID: child.processIdentifier, streams: LiveStreams(trackpadContacts: true, mouseContacts: true, status: true)))
    precondition(trackpad.isEnabled && mouse.isEnabled && GestureActionBlock.shared.blocksActions,
                 "dying subscriber starts: trackpad \(trackpad.isEnabled) mouse \(mouse.isEnabled) block \(GestureActionBlock.shared.isOn) streaming \(server.isStreaming)")
    spin(3) { !trackpad.isEnabled }
    precondition(!trackpad.isEnabled && !mouse.isEnabled && !server.isStreaming && !GestureActionBlock.shared.blocksActions,
                 "a vanished Settings process releases the monitors and the block")

    // So does one that stops answering (nobody on its port).
    server.handle(.subscribe(settingsPID: me, streams: LiveStreams(trackpadContacts: true, mouseContacts: false, status: true)))
    EngineLink.stopListening(on: EngineLink.settingsPortName(pid: me))
    trackpad.recordGesture("probe", action: "none", appName: "test")
    spin(1) { !server.isStreaming }
    precondition(!server.isStreaming && !trackpad.isEnabled, "an unreachable Settings process ends the subscription")
    precondition(EngineLink.listen(on: EngineLink.settingsPortName(pid: me)) { inbox.append($0) })
    GestureActionBlock.shared.isOn = false
    trackpad.clearGestureLog()

    // The Settings side applies what it receives.
    LiveContactsMonitor.mouse.applyRemote(snapshot)
    precondition(mouse.frame == snapshot.frame && mouse.isRecording && mouse.recordedFrameCount == 12 && mouse.lastReceived == 99.5)
    let before = mouse.gestures
    LiveContactsMonitor.mouse.applyRemote(snapshot)   // gestures nil: log kept
    precondition(mouse.gestures == before, "a snapshot without a log keeps the current log")
    let saved = LiveStatus.current()
    status.apply()
    precondition(LowFingerTrackpadInput.shared.statusLines == status.trackpadLines
                 && MagicMouseInput.shared.statusLines == status.mouseLines && MagicMouseInput.shared.connectedCount == 1
                 && NativePointerSpeed.shared.mouseStatus == "1.5×" && DesktopActions.shared.stageStatus == "Switched"
                 && EdgeControlsController.shared.activeEdge == .left
                 && EdgeControlsController.shared.firedCorner == .bottomRight, "status lines are applied")
    saved.apply()
    GestureActionBlock.shared.isOn = false
    LiveContactsMonitor.mouse.applyRemote(LiveContactsSnapshot(frame: .empty, transitions: [], isRecording: false,
                                                                recordedFrameCount: 0, lastReceived: 0, gestures: []))

    print("PASS: live stream: messages round-trip, subscriptions switch only the wanted monitors on, state streams once and only when changed, gestures and Block Real Gesture Triggering reach Settings, unsubscribing or a vanished Settings process releases the monitors and the block, mirrors apply what arrives")
}
