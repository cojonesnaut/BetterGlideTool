import Foundation
import CoreFoundation

/// What the menu bar app and the Settings process tell each other beyond the
/// shared config file (see ConfigSync for that).
enum LinkMessage: Codable, Equatable {
    /// Menu bar → Settings: come forward on this page; optionally check for updates.
    case show(tab: String?, device: String?, checkForUpdates: Bool)
    /// Settings → menu bar: open the welcome tour, which belongs to the menu bar app.
    case showOnboarding
    /// Settings → menu bar: an update was installed at this path; quit and
    /// reopen it. Settings quits with the menu bar app.
    case relaunchAfterUpdate(appPath: String)

    // Live data (see LiveStream.swift)

    /// Settings → menu bar: what Settings is showing right now. Replaces the
    /// previous subscription; an empty set ends it.
    case subscribe(settingsPID: Int32, streams: LiveStreams)
    /// Settings → menu bar: an action on a device's live monitor.
    case liveCommand(device: GestureDevice, command: LiveCommand)
    /// Settings → menu bar: Block Real Gesture Triggering.
    case setBlockActions(Bool)
    /// Settings → menu bar: write the device's last recording to this file.
    case exportRecording(device: GestureDevice, path: String)
    /// Menu bar → Settings: the live contacts view's state. `gestures` is nil
    /// when the log hasn't changed since the last message.
    case liveContacts(device: GestureDevice, snapshot: LiveContactsSnapshot)
    /// Menu bar → Settings: status lines and the active Edge Controls edge.
    case liveStatus(LiveStatus)
    /// Menu bar → Settings: how a command or export went, for the view's caption.
    case liveResult(device: GestureDevice, message: String)
}

/// A one-way message channel between the two BetterGlideTool processes over
/// named local mach ports (`CFMessagePort`). The app isn't sandboxed, so no XPC
/// service or launchd job is needed.
///
/// Each process listens on a name that includes its own pid, so several copies
/// (a test build beside the installed app, say) never share a port. Sends don't
/// wait for a reply, so the two main threads can never block each other.
enum EngineLink {
    static func menuBarPortName(pid: pid_t) -> String { "com.betterglidetool.app.engine.\(pid)" }
    static func settingsPortName(pid: pid_t) -> String { "com.betterglidetool.app.settings.\(pid)" }

    private static var listeners: [String: Listener] = [:]

    /// Starts receiving messages on `name`, delivered on the main run loop.
    /// Returns false if the name is taken or the port can't be created.
    @discardableResult
    static func listen(on name: String, handler: @escaping (LinkMessage) -> Void) -> Bool {
        guard listeners[name] == nil else { return false }
        guard let listener = Listener(name: name, handler: handler) else { return false }
        listeners[name] = listener
        return true
    }

    static func stopListening(on name: String) {
        listeners.removeValue(forKey: name)?.invalidate()
    }

    enum Delivery { case delivered, noListener, busy }

    /// Delivers `message` to the process listening on `name`. Returns whether it
    /// was handed over; false when nobody is listening or it stayed busy.
    @discardableResult
    static func send(_ message: LinkMessage, to name: String, timeout: TimeInterval = 1) -> Bool {
        deliver(message, to: name, timeout: timeout) == .delivered
    }

    /// Like `send`, but tells "nobody is listening" apart from "the listener
    /// didn't take it in time", which a stream retries instead of giving up on.
    static func deliver(_ message: LinkMessage, to name: String, timeout: TimeInterval = 1) -> Delivery {
        guard let data = try? PropertyListEncoder.binary.encode(message) else { return .busy }
        guard let remote = CFMessagePortCreateRemote(nil, name as CFString) else { return .noListener }
        // No CFMessagePortInvalidate here: CoreFoundation shares remote ports
        // by name, and invalidating one would break the next send to it.
        switch CFMessagePortSendRequest(remote, 0, data as CFData, timeout, 0, nil, nil) {
        case kCFMessagePortSuccess:
            return .delivered
        case kCFMessagePortIsInvalid, kCFMessagePortBecameInvalidError:
            return .noListener   // the listener's port went away
        default:
            // Timeouts and transport errors are temporary; the caller retries.
            return .busy
        }
    }

    static func decode(_ data: Data) -> LinkMessage? {
        try? PropertyListDecoder().decode(LinkMessage.self, from: data)
    }

    // MARK: Listener

    private final class Listener {
        let handler: (LinkMessage) -> Void
        private var port: CFMessagePort?
        private var source: CFRunLoopSource?

        init?(name: String, handler: @escaping (LinkMessage) -> Void) {
            self.handler = handler
            var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            var shouldFree: DarwinBoolean = false
            let callback: CFMessagePortCallBack = { port, _, data, info in
                guard let info, let data else { return nil }
                let listener = Unmanaged<Listener>.fromOpaque(info).takeUnretainedValue()
                if let message = EngineLink.decode(data as Data) {
                    listener.handler(message)
                } else {
                    AppLogger.debug("[Link] Ignored an unreadable message")
                }
                return nil
            }
            guard let port = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, &shouldFree) else {
                AppLogger.debug("[Link] Can't listen on \(name)")
                return nil
            }
            self.port = port
            source = CFMessagePortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        func invalidate() {
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            if let port { CFMessagePortInvalidate(port) }
            source = nil
            port = nil
        }

        deinit { invalidate() }
    }
}

private extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}
