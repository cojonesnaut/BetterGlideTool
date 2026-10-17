import Cocoa
import Combine
import Darwin

struct DesktopActionOptions: Codable, Equatable {
    var stagePosition = 1
    var stageApps: [String] = []
    var windowTitle = ""
    var allowAnimatedFallback = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stagePosition = try c.decodeIfPresent(Int.self, forKey: .stagePosition) ?? 1
        stageApps = try c.decodeIfPresent([String].self, forKey: .stageApps) ?? []
        windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        allowAnimatedFallback = try c.decodeIfPresent(Bool.self, forKey: .allowAnimatedFallback) ?? false
    }
}

/// WindowServer compatibility is resolved at runtime. Failed private calls are
/// reported; they never lead to a Dock restart or changes to system protections.
final class DesktopActions: NSObject, ObservableObject {
    static let shared = DesktopActions()
    private typealias Connection = @convention(c) () -> Int32
    private typealias Displays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias ActiveDisplay = @convention(c) (Int32) -> Unmanaged<CFString>?
    private typealias ChangeSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SetCurrent = @convention(c) (Int32, CFString, UInt64) -> Void
    private typealias MoveWindows = @convention(c) (Int32, CFArray, UInt64) -> Void
    private let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private var menuStages: [Stage] = []
    struct CycleState {
        var last: String?
        var attempted: String?
        var order: [String] = []
        var members: [String: [UInt32]] = [:]
        mutating func currentKey(groups: [String: [UInt32]], focused: UInt32?) -> String? {
            for (key, ids) in groups { members[key] = ids }
            if members.count > 128 { members = members.filter { order.contains($0.key) || groups[$0.key] != nil } }
            guard let focused else { return nil }
            // The active stage is usually absent from the recent strip. Remember
            // its member IDs so a manual focus change can still reset the cursor.
            return groups.first { $0.value.contains(focused) }?.key
                ?? members.first { $0.value.contains(focused) }?.key
        }
        mutating func next(visible: [String], current: String?, forward: Bool) -> String? {
            // An external focus change starts from that stage. A failed request
            // leaves focus unchanged, but the next tap must move past its target.
            if let current, current != last { attempted = nil }
            let previous = attempted ?? current ?? last
            if let current { last = current }
            let target = DesktopActions.nextStageKey(visible: visible, previous: previous, forward: forward, order: &order)
            attempted = target
            return target
        }
    }
    private var cycles: [UInt32: CycleState] = [:]
    @Published private(set) var stageStatus = "Not tested yet."
    private let stageWorker = DispatchQueue(label: "com.betterglidetool.stage-actions", qos: .userInitiated)
    private var stageBusy = false
    private var stageRequests: [() -> Void] = []
    private var activeMonitoring: LiveActionContext?
    private var activeRequestTime = 0.0
    private var activeResult = StageActionResult()
    private var alertVisible = false

    private func function<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
    static func adjacentID(in spaces: [[String: Any]], current: UInt64, next: Bool, desktopsOnly: Bool) -> UInt64? {
        guard let index = spaces.firstIndex(where: { ($0["id64"] as? NSNumber)?.uint64Value == current }) else { return nil }
        let candidate = index + (next ? 1 : -1)
        guard spaces.indices.contains(candidate), !desktopsOnly || (spaces[candidate]["type"] as? NSNumber)?.intValue == 0 else { return nil }
        return (spaces[candidate]["id64"] as? NSNumber)?.uint64Value
    }
    private func displayState() -> (Int32, [[String: Any]], String?)? {
        guard let connect = function("SLSMainConnectionID", as: Connection.self),
              let copy = function("SLSCopyManagedDisplaySpaces", as: Displays.self) else { return nil }
        let connection = connect()
        guard connection != 0, let list = copy(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let active = function("SLSCopyActiveMenuBarDisplayIdentifier", as: ActiveDisplay.self)?(connection)?.takeRetainedValue() as String?
        return (connection, list, active)
    }
    func changeSpace(next: Bool, options: DesktopActionOptions) {
        guard let (connection, displays, active) = displayState(),
              let display = displays.first(where: { ($0["Display Identifier"] as? String) == active }) ?? (displays.count == 1 ? displays.first : nil),
              let identifier = display["Display Identifier"] as? String,
              let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber,
              let spaces = display["Spaces"] as? [[String: Any]],
              let target = Self.adjacentID(in: spaces, current: current.uint64Value, next: next, desktopsOnly: false) else {
            report("No adjacent Space is available on the active display."); return
        }
        if let show = function("SLSShowSpaces", as: ChangeSpaces.self),
           let hide = function("SLSHideSpaces", as: ChangeSpaces.self),
           let set = function("SLSManagedDisplaySetCurrentSpace", as: SetCurrent.self) {
            let destination = [NSNumber(value: target)] as CFArray
            let previous = [current] as CFArray
            if show(connection, destination) == 0 {
                if hide(connection, previous) == 0 {
                    set(connection, identifier as CFString, target)
                    if GLDWIsSpaceCurrent(target) { return }
                }
                // Restore a coherent display if a later operation was rejected.
                _ = show(connection, previous)
                set(connection, identifier as CFString, current.uint64Value)
                _ = hide(connection, destination)
            }
        }
        if options.allowAnimatedFallback, let shortcut = MissionControlShortcut.moveToSpace(next: next) {
            KeyboardEmulator.shared.sendKey(shortcut.keyCode, shortcut.flags)
        } else {
            report("macOS did not allow animation-free Space switching. You can enable “Allow native animated fallback” in this action's settings. No system security settings were changed.")
        }
    }
    func moveWindow(next: Bool) {
        guard let window = WindowTargeting.shared.targetWindowForDesktopAction() else { report("No target window is available."); return }
        if (attribute(window, "AXFullScreen") as? Bool) == true { report("Exit full screen before moving this window to another desktop."); return }
        var id: UInt32 = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id != 0,
              let (connection, displays, _) = displayState() else { report("Could not identify the target window's desktop."); return }
        let source = GLDWSpaceForWindow(id)
        guard let spaces = displays.compactMap({ $0["Spaces"] as? [[String: Any]] }).first(where: { list in list.contains { ($0["id64"] as? NSNumber)?.uint64Value == source } }),
              let target = Self.adjacentID(in: spaces, current: source, next: next, desktopsOnly: true),
              let move = function("SLSMoveWindowsToManagedSpace", as: MoveWindows.self) else {
            report("No adjacent desktop is available for this window. Full-screen Spaces are not valid destinations."); return
        }
        move(connection, [NSNumber(value: id)] as CFArray, target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if GLDWSpaceForWindow(id) != target { self.report("macOS rejected moving this window to another Space.") }
        }
    }

    private struct Stage {
        let key: String
        let title: String
        let element: AXUIElement
        let position: CGPoint
        let windowIDs: [UInt32]
        let display: StageDisplay
    }
    private struct StageDiscovery {
        let stages: [Stage]
        let details: String
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func text(_ element: AXUIElement) -> String {
        [kAXIdentifierAttribute as String, kAXTitleAttribute as String, kAXDescriptionAttribute as String, kAXSubroleAttribute as String]
            .compactMap { attribute(element, $0) as? String }.joined(separator: " ")
    }
    private func stageAttributes(_ element: AXUIElement) -> [String: CFTypeRef] {
        // One IPC round trip per node instead of separate calls for each of the
        // twelve tree/identity/frame attributes. Unsupported values are omitted.
        let keys = ["AXIdentifier", "AXRole", "AXSubrole", "AXWindowsIDs", "AXTitle", "AXDescription",
                    "AXPosition", "AXSize", "AXChildren", "AXWindows", "AXContents", "AXVisibleChildren"]
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &values) == .success,
              let values = values as? [CFTypeRef], values.count == keys.count else {
            return Dictionary(uniqueKeysWithValues: keys.compactMap { key in attribute(element, key).map { (key, $0) } })
        }
        return Dictionary(uniqueKeysWithValues: zip(keys, values).filter { _, value in
            CFGetTypeID(value) != AXValueGetTypeID() || AXValueGetType(unsafeBitCast(value, to: AXValue.self)) != .axError
        })
    }
    private func children(from values: [String: CFTypeRef]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for key in ["AXChildren", "AXWindows", "AXContents", "AXVisibleChildren"] {
            for child in values[key] as? [AXUIElement] ?? [] {
                if !result.contains(where: { CFEqual($0, child) }) { result.append(child) }
            }
        }
        return result
    }
    static func stageIdentity(identifier: String?, labels: [String], windowIDs: [UInt32]) -> String? {
        // A stage's member windows survive strip rebuilds and distinguish
        // groups whose accessibility identifiers or labels are identical.
        if !windowIDs.isEmpty { return "windows:" + Set(windowIDs).sorted().map(String.init).joined(separator: ",") }
        if let identifier, !identifier.isEmpty {
            let normalized = identifier.lowercased().filter { $0.isLetter || $0.isNumber }
            if !["stagemanagerpile", "stagemanagerpiles"].contains(normalized) { return "id:" + identifier }
        }
        let labels = Set(labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).sorted()
        return labels.isEmpty ? nil : "labels:" + labels.joined(separator: "\u{1F}")
    }
    static func isStageStrip(_ descriptor: String) -> Bool {
        let normalized = descriptor.lowercased().filter { $0.isLetter || $0.isNumber }
        return ["stagemanagerstrip", "stagemanagerpiles"].contains(normalized)
    }
    /// The structural path and AXWindowsIDs are also used by Rectangle's
    /// StageUtil; identifiers are optional on some WindowManager versions.
    static func isStageButton(host: String, role: String, parentRole: String, grandparentRole: String,
                              descriptors: [String], actions: [String], windowIDs: [UInt32], insideStrip: Bool) -> Bool {
        // Some WindowManager versions expose membership but no thumbnail
        // actions. Those groups can be activated through a member AXWindow.
        let canActivate = !windowIDs.isEmpty || actions.contains(kAXPressAction as String)
        guard canActivate else { return false }
        let namedPile = descriptors.contains {
            let name = $0.lowercased().filter { $0.isLetter || $0.isNumber }
            return name.contains("stagemanagerpile") && !isStageStrip($0)
        }
        if namedPile || insideStrip { return true }
        guard host == "com.apple.WindowManager", role == kAXButtonRole as String else { return false }
        return actions.contains("AXAddToStage") ||
            (parentRole == kAXListRole as String && grandparentRole == kAXGroupRole as String && !windowIDs.isEmpty)
    }
    struct StageDisplay: Equatable {
        let id: UInt32
        let bounds: CGRect
    }
    /// All rectangles use Quartz/AX global coordinates, including displays above
    /// or left of the primary display. Never mix in AppKit's flipped coordinates.
    static func displayForWindow(_ frame: CGRect, displays: [StageDisplay]) -> StageDisplay? {
        guard !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return nil }
        return displays.compactMap { display -> (StageDisplay, CGFloat)? in
            let overlap = frame.intersection(display.bounds)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return nil }
            return (display, overlap.width * overlap.height)
        }.max { $0.1 < $1.1 }?.0
    }
    static func focusedDisplay(window: CGRect?, pointer: CGPoint, displays: [StageDisplay]) -> StageDisplay? {
        if let window { return displayForWindow(window, displays: displays) }
        return displays.first { $0.bounds.contains(pointer) }
    }
    private func axFrame(_ element: AXUIElement) -> CGRect? {
        axFrame(position: attribute(element, "AXPosition"), size: attribute(element, "AXSize"))
    }
    private func axFrame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let p = position, CFGetTypeID(p) == AXValueGetTypeID(),
              let s = size, CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func stageDisplayContext() -> (StageDisplay, [StageDisplay])? {
        dispatchPrecondition(condition: .onQueue(.main))
        let displays = NSScreen.screens.compactMap { screen -> StageDisplay? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return StageDisplay(id: id.uint32Value, bounds: CGDisplayBounds(id.uint32Value))
        }
        var frame: CGRect?
        if let app = NSWorkspace.shared.frontmostApplication {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.05)
            if let value = attribute(root, kAXFocusedWindowAttribute as String), CFGetTypeID(value) == AXUIElementGetTypeID() {
                frame = axFrame(unsafeBitCast(value, to: AXUIElement.self))
            }
        }
        guard let pointer = CGEvent(source: nil)?.location,
              let display = Self.focusedDisplay(window: frame, pointer: pointer,
                                               displays: displays) else { return nil }
        return (display, displays)
    }
    private func stages(on display: StageDisplay, displays: [StageDisplay]) -> StageDiscovery {
        var result: [Stage] = [], visited: [AXUIElement] = []
        var hostDetails: [String] = []
        let scanStarted = ProcessInfo.processInfo.systemUptime
        let deadline = scanStarted + 1.5
        var hosts = NSWorkspace.shared.runningApplications.filter {
            ["com.apple.WindowManager", "com.apple.dock"].contains($0.bundleIdentifier ?? "")
        }.map { (processIdentifier: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName) }
        if !hosts.contains(where: { $0.bundleIdentifier == "com.apple.WindowManager" }) {
            // Background WindowManager is not always registered as a launchable
            // app. WindowServer still identifies the owner of its strip surfaces.
            let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            for window in windows where window[kCGWindowOwnerName as String] as? String == "WindowManager" {
                guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                      pid.int32Value > 0, !hosts.contains(where: { $0.processIdentifier == pid.int32Value }) else { continue }
                hosts.append((pid.int32Value, "com.apple.WindowManager", "WindowManager"))
            }
        }
        hosts.sort { $0.bundleIdentifier == "com.apple.WindowManager" && $1.bundleIdentifier != "com.apple.WindowManager" }
        for app in hosts {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.05)
            var rootRole: CFTypeRef?
            let rootResult = AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &rootRole)
            let startCount = visited.count
            var pending: [(AXUIElement, Int, Bool, [String])] = [(root, 0, false, [])]
            var cursor = 0
            while cursor < pending.count, visited.count < 512,
                  ProcessInfo.processInfo.systemUptime < deadline {
                let (element, depth, insideStrip, ancestors) = pending[cursor]
                cursor += 1
                guard depth < 16, !visited.contains(where: { CFEqual($0, element) }) else { continue }
                visited.append(element)
                let values = stageAttributes(element)
                let identifier = values["AXIdentifier"] as? String
                let role = values["AXRole"] as? String ?? ""
                let subrole = values["AXSubrole"] as? String ?? ""
                let descriptors = [identifier ?? "", subrole, role]
                let strip = descriptors.contains(where: Self.isStageStrip)
                let descendants = children(from: values)
                var actionNames: CFArray?
                if role == kAXButtonRole as String || insideStrip || identifier?.lowercased().contains("stage") == true {
                    _ = AXUIElementCopyActionNames(element, &actionNames)
                }
                let actions = actionNames as? [String] ?? []
                // AXWindowsIDs contains the group's application windows. The
                // AX element's own backing window is only the thumbnail surface.
                let members = (values["AXWindowsIDs"] as? [NSNumber] ?? [])
                    .map(\.uint32Value).filter { $0 != 0 }
                let candidate = !strip && Self.isStageButton(host: app.bundleIdentifier ?? "", role: role,
                    parentRole: ancestors.last ?? "", grandparentRole: ancestors.dropLast().last ?? "",
                    descriptors: descriptors, actions: actions, windowIDs: members, insideStrip: insideStrip)
                if candidate {
                    let labels = [values["AXTitle"] as? String, values["AXDescription"] as? String].compactMap { $0 }
                        + descendants.map { text($0) }
                    // Unknown geometry is not permission to activate another display.
                    guard let frame = axFrame(position: values["AXPosition"], size: values["AXSize"]),
                          Self.displayForWindow(frame, displays: displays)?.id == display.id else { continue }
                    let position = frame.origin
                    guard let identity = Self.stageIdentity(identifier: identifier, labels: labels, windowIDs: members) else { continue }
                    let key = "\(app.processIdentifier):" + identity
                    // Only proven identical memberships may be collapsed.
                    // Duplicate text-only identities must still fail as ambiguous.
                    if members.isEmpty || !result.contains(where: { $0.key == key }) {
                        result.append(Stage(key: key, title: labels.filter { !$0.isEmpty }.joined(separator: " — "),
                                            element: element, position: position, windowIDs: members, display: display))
                    }
                } else {
                    let path = Array((ancestors + [role]).suffix(2))
                    pending.append(contentsOf: descendants.map { ($0, depth + 1, insideStrip || strip, path) })
                }
            }
            hostDetails.append("\(app.localizedName ?? app.bundleIdentifier ?? "host"): AX \(rootResult.rawValue), \(visited.count - startCount) elements")
            // WindowManager owns the native groups; don't also include Dock
            // proxies for those same stages.
            if !result.isEmpty { break }
        }
        let limited = ProcessInfo.processInfo.systemUptime >= deadline || visited.count >= 512
        let details = "Display \(display.id); " + (hostDetails.isEmpty ? "No WindowManager or Dock process found." : hostDetails.joined(separator: "; "))
            + String(format: "; %d stages; %.0f ms", result.count, (ProcessInfo.processInfo.systemUptime - scanStarted) * 1000)
            + (limited ? "; scan limit reached" : "")
        return StageDiscovery(stages: result.sorted {
            $0.position.y == $1.position.y ? $0.position.x < $1.position.x : $0.position.y < $1.position.y
        }, details: details)
    }
    static func cycleIndex(count: Int, previous: Int?, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let previous else { return forward ? 0 : count - 1 }
        return (previous + (forward ? 1 : count - 1)) % count
    }
    static func nextStageKey(visible: [String], previous: String?, forward: Bool, order: inout [String]) -> String? {
        // The active stage disappears from the recent strip; other thumbnails
        // can briefly disappear during its animation. Keep their places in the
        // ring and select only currently exposed groups, rather than reorder on
        // each partial snapshot. Bound retention for long-running sessions.
        if order.count > 128 { order.removeAll { !visible.contains($0) && $0 != previous } }
        if let previous, !order.contains(previous) { order.append(previous) }
        for key in visible where !order.contains(key) { order.append(key) }
        guard !visible.isEmpty else { return nil }
        var index = previous.flatMap { order.firstIndex(of: $0) }
        for _ in 0..<order.count {
            guard let next = cycleIndex(count: order.count, previous: index, forward: forward) else { return nil }
            if visible.contains(order[next]) { return order[next] }
            index = next
        }
        return nil
    }
    private func focusedWindowID() -> UInt32? {
        if !Thread.isMainThread { return DispatchQueue.main.sync { self.focusedWindowID() } }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.05)
        guard let value = attribute(root, kAXFocusedWindowAttribute as String),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        var windowID: UInt32 = 0
        return _AXUIElementGetWindow(window, &windowID) == .success && windowID != 0 ? windowID : nil
    }
    static func stageActivationConfirmed(members: [UInt32], before: UInt32?, after: UInt32?) -> Bool {
        guard let after else { return false }
        if !members.isEmpty { return members.contains(after) }
        return before != nil && before != after
    }
    static func memberIsOnDisplay(nativeDisplay: UInt32, frame: CGRect?, target: StageDisplay, displays: [StageDisplay]) -> Bool {
        // Inactive Stage Manager windows can have offscreen AX coordinates.
        // WindowServer ownership takes precedence, including a negative answer.
        if nativeDisplay != 0 { return nativeDisplay == target.id }
        guard let frame else { return false }
        return displayForWindow(frame, displays: displays)?.id == target.id
    }
    private func memberWindow(in stage: Stage) -> (NSRunningApplication, AXUIElement, AXUIElement, UInt32)? {
        guard !stage.windowIDs.isEmpty else { return nil }
        let members = Set(stage.windowIDs)
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var visitedPIDs = Set<pid_t>()
        for info in windows {
            guard let id = info[kCGWindowNumber as String] as? NSNumber, members.contains(id.uint32Value),
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                  visitedPIDs.insert(pid.int32Value).inserted,
                  let app = NSRunningApplication(processIdentifier: pid.int32Value) else { continue }
            let root = AXUIElementCreateApplication(pid.int32Value)
            AXUIElementSetMessagingTimeout(root, 0.1)
            // AX calls targeting this process execute AppKit accessors locally.
            let appWindows: [AXUIElement]
            if pid.int32Value == ProcessInfo.processInfo.processIdentifier, !Thread.isMainThread {
                appWindows = DispatchQueue.main.sync { self.attribute(root, kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }
            } else {
                appWindows = attribute(root, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
            }
            for window in appWindows {
                var windowID: UInt32 = 0
                if _AXUIElementGetWindow(window, &windowID) == .success, members.contains(windowID) {
                    let frame = pid.int32Value == ProcessInfo.processInfo.processIdentifier && !Thread.isMainThread
                        ? DispatchQueue.main.sync { self.axFrame(window) } : axFrame(window)
                    // A group can name windows outside its strip's display. Only
                    // raise a member whose WindowServer ownership (or AX fallback) matches.
                    let allDisplays = DispatchQueue.main.sync {
                        NSScreen.screens.compactMap { screen -> StageDisplay? in
                            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                            return StageDisplay(id: id.uint32Value, bounds: CGDisplayBounds(id.uint32Value))
                        }
                    }
                    guard Self.memberIsOnDisplay(nativeDisplay: GLDWDisplayForWindow(windowID), frame: frame,
                                                 target: stage.display, displays: allDisplays) else { continue }
                    return (app, root, window, windowID)
                }
            }
        }
        return nil
    }
    private func updateStageTrace(_ state: String, _ message: String) {
        activeResult.state = state
        activeResult.message = message
        activeResult.elapsedMilliseconds = max(0, ProcessInfo.processInfo.systemUptime - activeRequestTime) * 1000
        activeMonitoring?.update(activeResult)
    }
    private func finishStageRequest(_ message: String, succeeded: Bool = false) {
        stageStatus = message
        updateStageTrace(succeeded ? "succeeded" : "failed", message)
        activeMonitoring = nil
        AppLogger.debug("[Stage Manager] \(message)")
        stageBusy = false
        if !stageRequests.isEmpty {
            stageRequests.removeFirst()()
        }
    }
    private func activate(_ stage: Stage) {
        stageStatus = "Activating stage…"
        activeResult.targetWindowIDs = stage.windowIDs
        updateStageTrace("activating", stageStatus)
        stageWorker.async {
            let before = self.focusedWindowID()
            let member = self.memberWindow(in: stage)
            if !stage.windowIDs.isEmpty && member == nil {
                DispatchQueue.main.async { self.finishStageRequest("No accessible member window on the focused display. No other display was activated.") }
                return
            }
            Self.performStageWindowMutation {
                let result: AXError
                let route: String
                self.activeResult.beforeWindowID = before
                if let (app, root, window, windowID) = member {
                    // A process-wide activation can select another window of
                    // this app, including one in a different stage or display.
                    // Use the existing exact-window focus bridge first.
                    let exact = GLDWFocusWindow(app.processIdentifier, windowID)
                    _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    _ = AXUIElementSetAttributeValue(root, kAXFocusedWindowAttribute as CFString, window)
                    result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    route = exact ? "exact window \(windowID)" : "AX window \(windowID); native focus unavailable/rejected"
                } else {
                    result = AXUIElementPerformAction(stage.element, kAXPressAction as CFString)
                    route = stage.windowIDs.isEmpty ? "thumbnail; no member IDs exposed" : "thumbnail; member windows unavailable"
                }
                // AXRaise may return an error even when setting the focused window
                // succeeded. Verify the outcome of the complete sequence either way.
                self.activeResult.route = route
                self.verifyStageActivation(stage, before: before, route: route, result: result, attempt: 0)
            }
        }
    }
    // AX setters/actions can enter this app's NSWindow implementation directly.
    // Route the whole mutation, including AXMain/AXFocusedWindow/AXRaise, to main.
    static func performStageWindowMutation(_ body: @escaping () -> Void) {
        DispatchQueue.main.async {
            dispatchPrecondition(condition: .onQueue(.main))
            body()
        }
    }
    private func verifyStageActivation(_ stage: Stage, before: UInt32?, route: String, result: AXError, attempt: Int) {
        // Release the queue promptly when focus arrives; retain a bounded
        // settling window for slow apps instead of adding 120 ms to every tap.
        let delays = [0.04, 0.06, 0.10, 0.16, 0.24, 0.30]
        stageWorker.asyncAfter(deadline: .now() + delays[attempt]) {
            let after = self.focusedWindowID()
            let nativeDisplay = after.map { GLDWDisplayForWindow($0) } ?? 0
            let focusedDisplay = nativeDisplay != 0 ? nativeDisplay : DispatchQueue.main.sync { self.stageDisplayContext()?.0.id }
            DispatchQueue.main.async { self.activeResult.afterWindowID = after }
            if focusedDisplay == stage.display.id,
               Self.stageActivationConfirmed(members: stage.windowIDs, before: before, after: after) {
                DispatchQueue.main.async {
                    self.cycles[stage.display.id, default: CycleState()].last = stage.key
                    self.finishStageRequest("Stage activated: " + (stage.title.isEmpty ? "recent stage" : stage.title), succeeded: true)
                }
            } else if attempt + 1 < delays.count {
                self.verifyStageActivation(stage, before: before, route: route, result: result, attempt: attempt + 1)
            } else {
                DispatchQueue.main.async {
                    self.finishStageRequest("Stage found, but focus did not reach it (\(route); \(stage.windowIDs.count) member IDs; AX \(result.rawValue)).")
                }
            }
        }
    }
    func performStage(_ action: GestureAction, options: DesktopActionOptions, monitoring: LiveActionContext? = nil) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        if action == .stageToggle || action == .stageRecentToggle {
            let domain = "com.apple.WindowManager" as CFString
            let key = (action == .stageToggle ? "GloballyEnabled" : "AutoHide") as CFString
            CFPreferencesAppSynchronize(domain)
            let old = (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.boolValue ?? false
            CFPreferencesSetAppValue(key, NSNumber(value: !old), domain)
            if !CFPreferencesAppSynchronize(domain) { report("macOS could not save the Stage Manager setting.") }
            return
        }
        guard AXIsProcessTrusted() else {
            stageStatus = "Stage Manager actions need Accessibility access for this installed copy of BetterGlideTool."
            monitoring?.update(StageActionResult(state: "failed", message: stageStatus))
            report(stageStatus); return
        }
        guard let (display, displays) = stageDisplayContext() else {
            stageStatus = "Could not identify the focused display. No stage was activated."
            monitoring?.update(StageActionResult(state: "failed", message: stageStatus))
            return
        }
        if stageBusy {
            // Capture at invocation, so queued taps cannot follow a focus change
            // onto another display while discovery/activation is in progress.
            if stageRequests.count < 8 {
                monitoring?.update(StageActionResult(displayID: display.id))
                stageRequests.append { self.startStage(action, options: options, display: display, displays: displays, monitoring: monitoring, requestedAt: requestedAt) }
            } else {
                monitoring?.update(StageActionResult(state: "failed", message: "Stage switch queue is full; this request was not run.", displayID: display.id))
            }
            return
        }
        startStage(action, options: options, display: display, displays: displays, monitoring: monitoring, requestedAt: requestedAt)
    }
    private func startStage(_ action: GestureAction, options: DesktopActionOptions, display: StageDisplay, displays: [StageDisplay], monitoring: LiveActionContext?, requestedAt: Double) {
        activeMonitoring = monitoring
        activeRequestTime = requestedAt
        activeResult = StageActionResult(displayID: display.id)
        stageBusy = true
        stageStatus = "Finding recent stages on the focused display…"
        updateStageTrace("discovering", stageStatus)
        stageWorker.async {
            let discovery = self.stages(on: display, displays: displays)
            DispatchQueue.main.async {
                self.activeResult.discovery = discovery.details
                self.performStage(action, options: options, available: discovery.stages, discoveryDetails: discovery.details)
            }
        }
    }
    private func performStage(_ action: GestureAction, options: DesktopActionOptions, available: [Stage], discoveryDetails: String) {
        guard !available.isEmpty else {
            finishStageRequest("No stage buttons found on the focused display. " + discoveryDetails + ". Check that recent stages are visible on this desktop.")
            return
        }
        guard Set(available.map(\.key)).count == available.count else {
            finishStageRequest("macOS exposed ambiguous stage identifiers. Cycling was stopped to avoid choosing the wrong stage.")
            return
        }
        switch action {
        case .stagePosition:
            let index = options.stagePosition - 1
            guard available.indices.contains(index) else { finishStageRequest("There are only \(available.count) visible recent stages."); return }
            activate(available[index])
        case .stageNext, .stagePrevious:
            let focused = focusedWindowID()
            let displayID = available[0].display.id
            var state = cycles[displayID, default: CycleState()]
            let current = state.currentKey(groups: Dictionary(uniqueKeysWithValues: available.map { ($0.key, $0.windowIDs) }), focused: focused)
            let candidates = available.filter { $0.key != current }
            let next = state.next(visible: candidates.map(\.key), current: current, forward: action == .stageNext)
            cycles[displayID] = state
            if let key = next,
               let target = candidates.first(where: { $0.key == key }) { activate(target) }
            else { finishStageRequest("No other recent stage is available.") }
        case .stageMatching:
            let names = options.stageApps.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.deletingPathExtension().lastPathComponent }
            guard !options.stageApps.isEmpty || !options.windowTitle.isEmpty else { finishStageRequest("Choose target apps or a window title in this action's settings."); return }
            guard names.count == options.stageApps.count,
                  let found = available.first(where: { stage in names.allSatisfy { stage.title.localizedCaseInsensitiveContains($0) } && (options.windowTitle.isEmpty || stage.title.localizedCaseInsensitiveContains(options.windowTitle)) }) else {
                finishStageRequest("No visible stage matches the selected apps and window title."); return
            }
            activate(found)
        case .stageMenu:
            menuStages = available
            let menu = NSMenu(title: "Stage Manager")
            for (index, stage) in available.enumerated() {
                let item = NSMenuItem(title: stage.title.isEmpty ? "Stage \(index + 1)" : stage.title, action: #selector(selectStage(_:)), keyEquivalent: "")
                item.tag = index; item.target = self; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            menuStages = []
            if stageStatus != "Activating stage…" { finishStageRequest("Stage menu closed.") }
        default: finishStageRequest("No stage action selected.")
        }
    }
    @objc private func selectStage(_ sender: NSMenuItem) {
        if menuStages.indices.contains(sender.tag) { activate(menuStages[sender.tag]) }
    }
    private func report(_ message: String) {
        guard !alertVisible else { return }
        alertVisible = true
        let alert = NSAlert(); alert.messageText = "BetterGlideTool"; alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        alertVisible = false
    }
}
