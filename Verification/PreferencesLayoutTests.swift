import Cocoa
import SwiftUI

/// Guards against a page making the Preferences window's content taller than
/// the window. With `.contentMinSize` resizability, a page whose ideal height
/// is too large pushes the whole window — sidebar included — up under the
/// title bar. In 3.2.0 the Edge Controls header sat outside its scroll view
/// and did exactly that (fitting height 1,552 pt against 572 pt elsewhere).
///
/// Every page must ask for no more height than the Tuning page, which has the
/// same picker-over-scroll-view layout, at both the minimum and a typical size.
@MainActor
func verifyPreferencesLayout() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let navigator = PreferencesNavigator.shared
    let originalTab = navigator.tab
    let originalPage = UserDefaults.standard.string(forKey: "edgeControlsPage")
    defer {
        navigator.tab = originalTab
        if let originalPage { UserDefaults.standard.set(originalPage, forKey: "edgeControlsPage") }
        else { UserDefaults.standard.removeObject(forKey: "edgeControlsPage") }
    }

    func fittingHeight(_ tab: PrefsTab, page: String? = nil, size: NSSize) -> CGFloat {
        navigator.tab = tab
        if let page { UserDefaults.standard.set(page, forKey: "edgeControlsPage") }
        let controller = NSHostingController(rootView: PreferencesWindow()
            .environmentObject(PreferencesStore.shared)
            .environmentObject(EngineBridge.shared))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(size)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let height = controller.view.fittingSize.height
        window.contentViewController = nil
        return height
    }

    let edgePages = ["Edges", "Corners", "While Sliding", "Feedback"]
    for size in [NSSize(width: 760, height: 520), NSSize(width: 1467, height: 941)] {
        let reference = fittingHeight(.tuning, size: size)
        for tab in [PrefsTab.gestures, .inputMonitoring, .keyboard, .general, .configuration] {
            let height = fittingHeight(tab, size: size)
            precondition(height <= reference + 1,
                         "\(tab) asks for \(height) pt at \(size), more than Tuning's \(reference) pt")
        }
        for page in edgePages {
            let height = fittingHeight(.edgeControls, page: page, size: size)
            precondition(height <= reference + 1,
                         "Edge Controls › \(page) asks for \(height) pt at \(size), more than Tuning's \(reference) pt — "
                         + "something outside its scroll view is stretching the window")
        }
    }
    print("PASS: every Preferences page, and every Edge Controls category, fits the window like Tuning at 760×520 and 1467×941")
}
