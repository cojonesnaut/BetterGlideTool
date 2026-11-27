import Foundation

/// Keeps the menu bar app and the Settings process on the same configuration.
///
/// Both run in the same `config.yaml`. Each saves its own edits as before and
/// watches the file; when the other process saves, it applies the new contents
/// (`GlideConfigStore.reloadIfChangedExternally`) without writing back.
@MainActor
enum ConfigSync {
    private static var watcher: ConfigFileWatcher?

    /// Starts watching and wires the reload to PreferencesStore, whose reload
    /// already replays every engine side effect of an in-process edit.
    static func start() {
        guard watcher == nil else { return }
        GlideConfigStore.shared.onExternalChange = {
            MainActor.assumeIsolated { refreshAfterExternalChange() }
        }
        watcher = ConfigFileWatcher(url: GlideConfigStore.shared.configURL) {
            GlideConfigStore.shared.reloadIfChangedExternally()
        }
    }

    static func refreshAfterExternalChange() {
        let store = PreferencesStore.shared
        // Rules, devices, Edge Controls, hotkeys, native gesture conflicts and
        // pointer speed (see PreferencesStore.reload and persistRules).
        store.reload()
        TouchTracker.updateTuningCache(edgeMarginEnabled: store.tuning.edgeMarginEnabled,
                                       edgeMargin: store.tuning.edgeMargin)
    }
}

/// Calls `onChange` shortly after the file at `url` is written, replaced or
/// created. Watches the folder rather than the file: a save writes a new file
/// and renames it over the old one, which a watch on the old file would miss.
final class ConfigFileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            AppLogger.debug("[Config] Can't watch \(folder.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    /// A save is a burst of events; check once it has settled.
    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
