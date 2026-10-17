import Cocoa
import SwiftUI

func verifyLiveContacts() throws {
    func frame(_ ids: [Int32], time: Double) -> LiveContactFrame {
        .init(timestamp: time, appName: "Brave Browser", contacts: ids.map {
            .init(id: $0, state: 4, x: 0.15 + Double($0) * 0.18, y: 0.6, size: 0.4375, role: "Resting")
        }, feedback: "Test frame")
    }
    var history = LiveContactsHistory()
    history.startRecording()
    history.consume(frame([1, 2, 3], time: 10))
    history.consume(frame([2, 3], time: 10.1))
    history.consume(frame([1, 2, 3], time: 10.2))
    history.consume(frame([1, 2], time: 10.3))
    history.consume(frame([], time: 10.4))
    precondition(history.transitions.filter { !$0.landed }.map(\.id) == [1, 3, 1, 2])
    precondition(history.latest.contacts.isEmpty && history.frames.count == 5)
    let data = try LiveContactsRecording(frames: history.frames).encoded()
    let decoded = try JSONDecoder().decode(LiveContactsRecording.self, from: data)
    precondition(decoded.frames == history.frames && decoded.note.contains("not calibrated pressure"))
    for i in 0..<100 { history.consume(frame(i % 2 == 0 ? [9] : [], time: 11 + Double(i) / 100)) }
    precondition(history.transitions.count == 64)
    history.consume(frame([], time: 25.1))
    precondition(!history.recording)
    history.startRecording()
    for i in 0..<7000 { history.consume(frame([2], time: 100 + Double(i) / 1000)) }
    precondition(history.frames.count == 6000 && !history.recording)
    history.resetLive()
    precondition(history.latest == .empty && history.transitions.isEmpty && history.frames.count == 6000)

    var settings = MagicMouseSettings()
    settings.tipTapSpacingGeometry = .surface
    settings.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
    let chord = [MouseContact(id: 11, x: 0.3, y: 0.5), MouseContact(id: 12, x: 0.5, y: 0.5), MouseContact(id: 13, x: 0.7, y: 0.5)]
    var observed = MagicMouseRecognizer(), reference = MagicMouseRecognizer()
    for (index, contacts) in [chord, chord, Array(chord.dropFirst()), chord, Array(chord.dropLast()), []].enumerated() {
        let time = 1 + Double(index) * 0.3
        let actual = observed.consume(contacts, timestamp: time, settings: settings)
        precondition(actual == reference.consume(contacts, timestamp: time, settings: settings), "Reading roles cannot change recognition")
        let roles = observed.liveContactRoles
        precondition(Set(roles.keys).isSubset(of: Set(contacts.map(\.id))))
        if index == 1 {
            precondition(roles[12] == "Resting middle" && roles[11] == "Outer candidate" && roles[13] == "Outer candidate")
        }
    }
    _ = observed.consume(chord, timestamp: 5, settings: settings)
    observed.cancel()
    precondition(observed.liveContactRoles.values.allSatisfy { $0 == "Blocked" })

    // Exercise the production callback copy and coalesced final-release update,
    // without opening the hardware stream or dispatching gestures.
    let monitor = LiveContactsMonitor.shared
    monitor.setVisible(true, owner: "test-settings")
    monitor.setVisible(true, owner: "test-panel")
    monitor.setVisible(false, owner: "test-settings")
    precondition(monitor.isEnabled)
    monitor.startRecording()
    var point = GLDTouchPoint()
    point.identifier = 37; point.state = 4; point.x = 0.375; point.y = 0.625; point.size = 0.4375
    withUnsafePointer(to: &point) { pointer in
        monitor.receive(pointer, count: 1, timestamp: 1, appName: "Brave Browser", roles: [37: "Resting"], feedback: "Ready", sampledButtonDown: true, trackpadButtonsDown: [0])
    }
    monitor.receive(nil, count: 0, timestamp: 1.1, appName: "Brave Browser", roles: [:], feedback: "Lifted")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    precondition(monitor.frame.contacts.isEmpty && monitor.frame.timestamp == 1.1)
    precondition(monitor.transitions.last?.landed == false && monitor.transitions.last?.id == 37)
    monitor.stopRecording()
    let captured = try JSONDecoder().decode(LiveContactsRecording.self, from: monitor.recordingData())
    precondition(captured.frames.count == 2 && captured.frames[0].contacts[0].size == 0.4375)
    precondition(captured.frames[0].sampledButtonDown == true && captured.frames[0].trackpadButtonsDown == [0])
    monitor.setVisible(false, owner: "test-panel")
    precondition(!monitor.isEnabled && monitor.frame == .empty && monitor.recordedFrameCount == 2)
    monitor.receive(nil, count: 0, timestamp: 2, appName: "Ignored", roles: [:], feedback: "Ignored")
    precondition(monitor.frame == .empty)
    // Both devices can be monitored/recorded independently, including when
    // one viewer closes. Sensor IDs may overlap without mixing histories.
    let mouse = LiveContactsMonitor.mouse
    monitor.setVisible(true, owner: "test-trackpad")
    mouse.setVisible(true, owner: "test-mouse")
    mouse.startRecording()
    withUnsafePointer(to: &point) { pointer in
        monitor.receive(pointer, count: 1, timestamp: 10, appName: "Trackpad app", roles: [:], feedback: "Trackpad")
        mouse.receive(pointer, count: 1, timestamp: 20, appName: "Mouse app", roles: [:], feedback: "Mouse", sourceID: 0)
        mouse.receive(pointer, count: 1, timestamp: 21, appName: "Mouse app", roles: [:], feedback: "Mouse", sourceID: 1)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    precondition(monitor.frame.appName == "Trackpad app" && mouse.frame.appName == "Mouse app")
    precondition(mouse.transitions.count == 1 && mouse.transitions[0].landed)
    mouse.stopRecording()
    let mouseRecording = try JSONDecoder().decode(LiveContactsRecording.self, from: mouse.recordingData())
    precondition(mouseRecording.device == .magicMouse && mouseRecording.frames.map(\.sourceID) == [0, 1])
    let trackpadRecording = try JSONDecoder().decode(LiveContactsRecording.self, from: monitor.snapshotData())
    precondition(trackpadRecording.device == .trackpad)
    mouse.setVisible(false, owner: "test-mouse")
    precondition(monitor.isEnabled && monitor.frame.appName == "Trackpad app" && !mouse.isEnabled)
    monitor.startRecording()
    for _ in 0..<100 { monitor.recordGesture("TipTap Right", action: "Keyboard Shortcut", appName: "Brave") }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    precondition(monitor.gestures.count == 80 && Set(monitor.gestures.map(\.id)).count == 80)
    let eventRecording = try JSONDecoder().decode(LiveContactsRecording.self, from: monitor.recordingData())
    precondition(eventRecording.gestures?.count == 100)
    // Completion follows UUIDs even after recording stops, never the newest tap.
    let first = monitor.recordGesture("TipTap Left", action: "Stage Previous", appName: "Brave")!
    let second = monitor.recordGesture("TipTap Right", action: "Stage Next", appName: "Brave")!
    monitor.stopRecording()
    let success = StageActionResult(state: "succeeded", message: "Stage activated", displayID: 1,
        targetWindowIDs: [12, 13], beforeWindowID: 5, afterWindowID: 12, route: "exact window 12",
        discovery: "4 stages", elapsedMilliseconds: 42.5)
    let failure = StageActionResult(state: "failed", message: "Focus did not reach target", displayID: 1, targetWindowIDs: [8])
    second.update(success)
    first.update(failure)
    let completed = try JSONDecoder().decode(LiveContactsRecording.self, from: monitor.recordingData())
    precondition(completed.gestures?.first(where: { $0.id == first.eventID })?.stageResult == failure)
    precondition(completed.gestures?.first(where: { $0.id == second.eventID })?.stageResult == success)
    precondition(completed.gestures?.first?.stageResult == nil)
    let legacyEvent = LiveGestureEvent(id: UUID(), timestamp: 4, date: Date(), gesture: "TipTap", action: "Stage Next", appName: "Brave")
    let legacyData = try JSONEncoder().encode(legacyEvent)
    let legacyDecoded = try JSONDecoder().decode(LiveGestureEvent.self, from: legacyData)
    precondition(legacyDecoded.stageResult == nil)
    monitor.clearGestureLog()
    precondition(monitor.gestures.isEmpty)
    let afterClear = try JSONDecoder().decode(LiveContactsRecording.self, from: monitor.recordingData())
    precondition(afterClear.gestures?.count == 102, "Clearing live log must not erase recording")
    monitor.stopRecording()
    monitor.setVisible(false, owner: "test-trackpad")

    _ = NSApplication.shared
    let panel = LiveContactsPanelController.makePanel()
    precondition(!panel.canBecomeKey && !panel.canBecomeMain)
    precondition(panel.styleMask.contains(.nonactivatingPanel) && panel.level == .floating)
    precondition(!panel.hidesOnDeactivate && panel.collectionBehavior.contains(.fullScreenAuxiliary))
    precondition(panel.collectionBehavior.contains(.canJoinAllApplications))
    precondition(!panel.isVisible)
    let mousePanel = LiveContactsPanelController.makePanel(device: .magicMouse)
    precondition(mousePanel.title.contains("Magic Mouse") && !mousePanel.canBecomeKey && !mousePanel.canBecomeMain)
    precondition(mousePanel.frameAutosaveName != panel.frameAutosaveName)
    print("PASS: Live Contacts transitions, retention, exact JSON round trip, diagnostic roles, viewer ownership and final-release refresh")
}

@MainActor
func renderLiveContactsPreviewIfRequested() throws {
    if let folder = ProcessInfo.processInfo.environment["INPUT_MONITORING_PREVIEW"] {
        for device in GestureDevice.allCases {
            let content = InputMonitoringTab(device: device)
                .frame(width: 1000, height: 920)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 920),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1000, height: 920)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Input Monitoring page did not render")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Preview encoding failed") }
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("input-monitoring-\(device.rawValue).png"))
        }
    }
    guard let output = ProcessInfo.processInfo.environment["LIVE_CONTACTS_PREVIEW"] else { return }
    let sample = LiveContactFrame(timestamp: 342.125, appName: "Brave Browser", contacts: [
        .init(id: 11, state: 4, x: 0.27, y: 0.45, size: 0.4375, role: "Outer candidate"),
        .init(id: 12, state: 4, x: 0.50, y: 0.58, size: 0.521, role: "Resting middle"),
        .init(id: 13, state: 3, x: 0.75, y: 0.44, size: 0.395, role: "Outer candidate")
    ], feedback: "Recognized: TipTap Right (2 Fingers Fix)")
    var events: [LiveGestureEvent] = []
    for index in 0..<6 {
        let offset = Double(index)
        let date = Date(timeIntervalSince1970: 1790445000.0 - offset)
        let gesture = index % 2 == 0 ? "TipTap Right (2 Fingers Fix)" : "3 Finger Swipe Right"
        let action = index % 2 == 0 ? "Keyboard Shortcut…" : "Stage Manager: Cycle Through Stages (Forward)"
        events.append(LiveGestureEvent(id: UUID(), timestamp: 342.0 - offset, date: date,
            gesture: gesture, action: action, appName: "Brave Browser"))
    }
    let view = LiveContactsReadout(frame: sample,
        transitions: [.init(timestamp: 341.975, id: 13, landed: false), .init(timestamp: 342.125, id: 13, landed: true)], stale: false, gestures: events)
        .frame(width: 760, height: 360).padding(12).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark).tint(.purple)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 784, height: 384), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 784, height: 384)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Preview failed") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Preview encoding failed") }
    try png.write(to: URL(fileURLWithPath: output))
}
