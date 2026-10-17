import Cocoa
import Combine

extension GestureDevice {
    var monitoringTitle: String { self == .trackpad ? "Trackpad" : "Magic Mouse" }
}

struct LiveContact: Codable, Equatable, Identifiable {
    let id: Int32
    let state: Int32
    let x: Double
    let y: Double
    let size: Double
    let role: String
}

struct LiveContactFrame: Codable, Equatable {
    let timestamp: Double
    let appName: String
    let contacts: [LiveContact]
    let feedback: String
    var sampledButtonDown: Bool? = nil
    var trackpadButtonsDown: [Int]? = nil
    var sourceID: Int? = nil
    static let empty = LiveContactFrame(timestamp: 0, appName: "—", contacts: [], feedback: "Waiting for contact input")
}

struct LiveContactTransition: Codable, Equatable {
    let timestamp: Double
    let id: Int32
    let landed: Bool
}

/// Value-type history makes retention, transitions and JSON export independently testable.
struct LiveContactsHistory {
    static let frameLimit = 6000
    static let recordingDuration = 15.0
    var latest = LiveContactFrame.empty
    private(set) var transitions: [LiveContactTransition] = []
    private(set) var frames: [LiveContactFrame] = []
    private(set) var recording = false
    private var recordingStart: Double?

    mutating func startRecording() {
        frames = []; recording = true; recordingStart = nil
    }
    mutating func stopRecording() { recording = false }
    mutating func resetLive() { latest = .empty; transitions = [] }

    mutating func consume(_ frame: LiveContactFrame) {
        // Multiple Magic Mice have independent identifier namespaces. A source
        // change is not a physical lift/landing on the previous mouse.
        if latest.sourceID != frame.sourceID { transitions = [] }
        let old = latest.sourceID == frame.sourceID ? Set(latest.contacts.map(\.id)) : Set<Int32>()
        let new = Set(frame.contacts.map(\.id))
        for id in old.subtracting(new).sorted() {
            transitions.append(.init(timestamp: frame.timestamp, id: id, landed: false))
        }
        for id in new.subtracting(old).sorted() {
            transitions.append(.init(timestamp: frame.timestamp, id: id, landed: true))
        }
        if transitions.count > 64 { transitions.removeFirst(transitions.count - 64) }
        latest = frame
        if recording {
            if recordingStart == nil { recordingStart = frame.timestamp }
            if frame.timestamp - (recordingStart ?? frame.timestamp) <= Self.recordingDuration {
                frames.append(frame)
            }
            if frames.count >= Self.frameLimit || frame.timestamp - (recordingStart ?? frame.timestamp) >= Self.recordingDuration {
                recording = false
            }
        }
    }
}

/// Correlates asynchronous Stage Manager completion with the original gesture,
/// including when later gestures have already arrived or the recording stopped.
struct LiveActionContext {
    let device: GestureDevice
    let eventID: UUID
    func update(_ result: StageActionResult) {
        LiveContactsMonitor.forDevice(device).updateStageResult(eventID: eventID, result: result)
    }
}
struct StageActionResult: Codable, Equatable {
    var state = "queued"
    var message = "Waiting for the previous stage switch"
    var displayID: UInt32?
    var targetWindowIDs: [UInt32] = []
    var beforeWindowID: UInt32?
    var afterWindowID: UInt32?
    var route: String?
    var discovery: String?
    var elapsedMilliseconds = 0.0
}

struct LiveGestureEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Double
    let date: Date
    let gesture: String
    let action: String
    let appName: String
    var stageResult: StageActionResult? = nil
}

struct LiveContactsRecording: Codable {
    let formatVersion: Int
    let appVersion: String
    let note: String
    let frames: [LiveContactFrame]
    var device: GestureDevice?
    var gestures: [LiveGestureEvent]?
    init(frames: [LiveContactFrame], device: GestureDevice = .trackpad, gestures: [LiveGestureEvent] = []) {
        self.gestures = gestures
        self.device = device
        formatVersion = 1
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        note = "\(device.monitoringTitle) frames delivered by the app's multitouch input. Timestamps are monotonic seconds; X/Y are normalized device coordinates. Size is contact size, not calibrated pressure. States are raw 3/4. Roles describe the recognizer, not physical finger identity. Contact IDs may change. sampledButtonDown is the system-wide button sample; trackpadButtonsDown is the recognizer's confirmed trackpad button-event state."
        self.frames = frames
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Callback input is copied under a lock. At most one 60 Hz UI update is queued;
/// recordings retain every delivered frame independently of visual refresh rate.
final class LiveContactsMonitor: ObservableObject {
    static let shared = LiveContactsMonitor(device: .trackpad)
    static let mouse = LiveContactsMonitor(device: .magicMouse)
    static func forDevice(_ device: GestureDevice) -> LiveContactsMonitor { device == .trackpad ? shared : mouse }
    let device: GestureDevice
    private init(device: GestureDevice) { self.device = device }
    @Published private(set) var frame = LiveContactFrame.empty
    @Published private(set) var transitions: [LiveContactTransition] = []
    @Published private(set) var isRecording = false
    @Published private(set) var recordedFrameCount = 0
    @Published private(set) var gestures: [LiveGestureEvent] = []
    private var gestureHistory: [LiveGestureEvent] = []
    private var recordedGestures: [LiveGestureEvent] = []
    @Published private(set) var lastReceived = 0.0
    private let lock = NSLock()
    private var owners: Set<String> = []
    private var history = LiveContactsHistory()
    private var updateQueued = false
    private var receivedAt = 0.0
    private var recordingID = UUID()

    var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }; return !owners.isEmpty
    }
    func setVisible(_ visible: Bool, owner: String) {
        precondition(Thread.isMainThread)
        lock.lock()
        if visible { owners.insert(owner) } else { owners.remove(owner) }
        if owners.isEmpty { history.stopRecording(); history.resetLive(); receivedAt = 0 }
        lock.unlock()
        refresh()
        if device == .trackpad { MultitouchBridge.shared.updateMinimumContactCount() }
        else { MagicMouseInput.shared.applySettings() }
    }
    func inputStopped() {
        lock.lock(); history.stopRecording(); history.resetLive(); receivedAt = 0; lock.unlock()
        DispatchQueue.main.async { self.refresh() }
    }
    func receive(_ points: UnsafePointer<GLDTouchPoint>?, count: Int32, timestamp: Double,
                 appName: String, roles: [Int32: String], feedback: String,
                 sampledButtonDown: Bool? = nil, trackpadButtonsDown: [Int]? = nil, sourceID: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard !owners.isEmpty, count >= 0, count <= 32, timestamp.isFinite else { return }
        var contacts: [LiveContact] = []
        if let points {
            for index in 0..<Int(count) {
                let p = points[index]
                guard p.x.isFinite, p.y.isFinite, p.size.isFinite else { continue }
                contacts.append(.init(id: p.identifier, state: p.state, x: Double(p.x), y: Double(p.y),
                                      size: Double(p.size), role: roles[p.identifier] ?? "Unassigned"))
            }
        }
        history.consume(.init(timestamp: timestamp, appName: appName, contacts: contacts.sorted { $0.id < $1.id }, feedback: feedback,
                              sampledButtonDown: sampledButtonDown, trackpadButtonsDown: trackpadButtonsDown, sourceID: sourceID))
        receivedAt = ProcessInfo.processInfo.systemUptime
        if !updateQueued {
            updateQueued = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { self.refresh() }
        }
    }
    private func refresh() {
        precondition(Thread.isMainThread)
        lock.lock()
        let snapshot = history, received = receivedAt, events = gestureHistory
        updateQueued = false
        lock.unlock()
        frame = snapshot.latest; transitions = snapshot.transitions; gestures = events
        isRecording = snapshot.recording; recordedFrameCount = snapshot.frames.count; lastReceived = received
    }
    func startRecording() {
        precondition(Thread.isMainThread)
        let id = UUID(); recordingID = id
        lock.lock(); history.startRecording(); recordedGestures = []; lock.unlock()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveContactsHistory.recordingDuration) {
            if self.recordingID == id { self.stopRecording() }
        }
    }
    func stopRecording() {
        precondition(Thread.isMainThread)
        lock.lock(); history.stopRecording(); lock.unlock(); refresh()
    }
    /// Called at gesture action dispatch, never inferred from repeated status
    /// text. Identical consecutive gestures remain separate log entries.
    @discardableResult
    func recordGesture(_ gesture: String, action: String, appName: String) -> LiveActionContext? {
        let event = LiveGestureEvent(id: UUID(), timestamp: ProcessInfo.processInfo.systemUptime,
            date: Date(), gesture: gesture, action: action, appName: appName)
        lock.lock()
        guard !owners.isEmpty else { lock.unlock(); return nil }
        gestureHistory.insert(event, at: 0)
        if gestureHistory.count > 80 { gestureHistory.removeLast(gestureHistory.count - 80) }
        if history.recording, recordedGestures.count < LiveContactsHistory.frameLimit { recordedGestures.append(event) }
        lock.unlock()
        DispatchQueue.main.async { self.refresh() }
        return LiveActionContext(device: device, eventID: event.id)
    }
    func updateStageResult(eventID: UUID, result: StageActionResult) {
        lock.lock()
        if let index = gestureHistory.firstIndex(where: { $0.id == eventID }) { gestureHistory[index].stageResult = result }
        if let index = recordedGestures.firstIndex(where: { $0.id == eventID }) { recordedGestures[index].stageResult = result }
        lock.unlock()
        DispatchQueue.main.async { self.refresh() }
    }
    func clearGestureLog() {
        lock.lock(); gestureHistory = []; lock.unlock()
        refresh()
    }
    func recordingData() throws -> Data {
        lock.lock(); let frames = history.frames, events = recordedGestures; lock.unlock()
        return try LiveContactsRecording(frames: frames, device: device, gestures: events).encoded()
    }
    func snapshotData() throws -> Data {
        lock.lock(); let latest = history.latest, events = gestureHistory; lock.unlock()
        return try LiveContactsRecording(frames: [latest], device: device, gestures: events).encoded()
    }
}
