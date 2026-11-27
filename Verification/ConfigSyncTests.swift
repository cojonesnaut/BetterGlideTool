import Foundation

/// The menu bar app and the Settings process share `config.yaml`; each saves
/// its own edits and reloads the other's (ConfigSync). These checks play the
/// other process by writing the file directly. They run against the scratch
/// config `Verification/run.sh` points BETTERGLIDETOOL_CONFIG_PATH at.
@MainActor
func verifyConfigSync() {
    let store = GlideConfigStore.shared
    let url = store.configURL
    precondition(ProcessInfo.processInfo.environment["BETTERGLIDETOOL_CONFIG_PATH"] == url.path,
                 "config sync checks must run against the scratch config")
    func fileText() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    /// What the other process would write: this process's config with one change.
    func otherProcessWrites(_ mutate: (inout GlideConfig) -> Void) -> String {
        var cfg = GlideConfig.fromSettings()
        mutate(&cfg)
        let yaml = GlideConfigSerializer.serialize(cfg)
        try! yaml.write(to: url, atomically: true, encoding: .utf8)
        return yaml
    }

    var refreshes = 0
    let previousHook = store.onExternalChange
    store.onExternalChange = { refreshes += 1 }
    defer { store.onExternalChange = previousHook }

    // 1. Its own save is never mistaken for the other process's.
    precondition(store.save())
    precondition(!store.reloadIfChangedExternally() && refreshes == 0, "own save is ignored")

    // 2. The other process's save is applied, refreshes once, and writes nothing.
    let original = Settings.shared.windowTargetingMode
    let flipped: WindowTargetingMode = original == .focusedThenCursor ? .cursorThenFocused : .focusedThenCursor
    let written = otherProcessWrites { $0.preferences.windowTargeting = flipped.rawValue }
    precondition(store.reloadIfChangedExternally(), "external save is applied")
    precondition(Settings.shared.windowTargetingMode == flipped, "external value reaches Settings")
    precondition(refreshes == 1, "dependents refresh once")
    precondition(!store.isDirty, "a reload schedules no save")
    spin(0.6)   // past the 0.4 s save debounce
    precondition(fileText() == written, "a reload never writes the file back")
    precondition(!store.reloadIfChangedExternally() && refreshes == 1, "the same contents apply once")

    // 3. Edits that cascade (rules) don't write during a reload either.
    let ruleCount = Settings.shared.rules.count
    precondition(ruleCount > 0, "scratch config has gestures to remove")
    let fewer = otherProcessWrites { $0.gestures.removeLast() }
    precondition(store.reloadIfChangedExternally() && Settings.shared.rules.count == ruleCount - 1,
                 "rule changes from the other process are applied")
    spin(0.6)
    precondition(fileText() == fewer && !store.isDirty, "rule reload writes nothing")

    // 4. An unsaved local edit is never discarded: the reload waits, and the
    //    local save wins, which the other process then reloads.
    Settings.shared.windowTargetingMode = original          // local edit, save pending
    precondition(store.isDirty)
    _ = otherProcessWrites { $0.preferences.hapticFeedback.toggle() }
    precondition(!store.reloadIfChangedExternally(), "no reload over an unsaved local edit")
    store.flushPendingSave()
    precondition(Settings.shared.windowTargetingMode == original && GlideConfigParser.parse(yaml: fileText())?
                    .preferences.windowTargeting == original.rawValue, "the local edit is saved")

    // 5. A half-written or broken file is ignored.
    let before = Settings.shared.rules.count
    try! "touchpad: [unterminated".write(to: url, atomically: true, encoding: .utf8)
    precondition(!store.reloadIfChangedExternally() && Settings.shared.rules.count == before,
                 "an unparsable file changes nothing")
    precondition(store.save())

    // 6. The watcher sees an atomic replace (write new file, rename over).
    var seen = 0
    let watcher = ConfigFileWatcher(url: url) { seen += 1 }
    _ = otherProcessWrites { $0.preferences.debugLogging.toggle() }
    let deadline = Date(timeIntervalSinceNow: 3)
    while seen == 0 && Date() < deadline { spin(0.05) }
    precondition(seen > 0, "the folder watch notices an atomic save")
    withExtendedLifetime(watcher) {}
    precondition(store.reloadIfChangedExternally())

    print("PASS: config sync between processes: own saves ignored, external saves applied once without writing back, unsaved local edits kept, broken files ignored, atomic saves seen")
}
