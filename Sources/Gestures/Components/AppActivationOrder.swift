import Cocoa

/// Most-recently-used order of regular apps, for "Activate Next/Previous App".
final class AppActivationOrder {

    static let shared = AppActivationOrder()

    private var mruAppOrder: [pid_t] = []
    private var mruObserver: Any?

    private init() {}

    func startMRUTracking() {
        stopMRUTracking()
        if let front = NSWorkspace.shared.frontmostApplication {
            mruAppOrder = [front.processIdentifier]
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !mruAppOrder.contains(app.processIdentifier) {
                mruAppOrder.append(app.processIdentifier)
            }
        }
        mruObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            let pid = app.processIdentifier
            self.mruAppOrder.removeAll { $0 == pid }
            self.mruAppOrder.insert(pid, at: 0)
        }
    }

    func stopMRUTracking() {
        if let observer = mruObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        mruObserver = nil
    }

    func getOrderedApps() -> [NSRunningApplication] {
        // Matches the system ⌘Tab order, which is most-recently-used. A stable
        // tie-break keeps never-activated apps in a deterministic order.
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningPIDs = Set(apps.map(\.processIdentifier))
        mruAppOrder.removeAll { !runningPIDs.contains($0) }
        let ranks = Dictionary(uniqueKeysWithValues: mruAppOrder.enumerated().map { ($0.element, $0.offset) })
        return apps.enumerated().sorted { a, b in
            let ai = ranks[a.element.processIdentifier] ?? Int.max
            let bi = ranks[b.element.processIdentifier] ?? Int.max
            return ai == bi ? a.offset < b.offset : ai < bi
        }.map(\.element)
    }
}
