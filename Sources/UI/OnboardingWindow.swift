import SwiftUI
import Cocoa
import ApplicationServices
// Timer.publish returns a Combine type used in a stored property below; without
// this import the compiler warns that the type isn't visible in this file.
import Combine

// ─────────────────────────────────────────────
// MARK: - OnboardingController
//
// Hosts the welcome tour in a plain NSWindow so it can be shown from the
// AppKit app delegate at first launch (the app is LSUIElement — there is no
// SwiftUI scene visible at startup to hang an openWindow call on).
// ─────────────────────────────────────────────

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private static let completedKey = "BetterGlideToolHasCompletedOnboarding"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.close()
        })
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.setContentSize(NSSize(width: 540, height: 600))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w

        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()   // triggers windowWillClose for the shared teardown
    }

    func windowWillClose(_ notification: Notification) {
        // Closing counts as done either way — don't nag on every launch.
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
        NSApp.setActivationPolicy(.accessory)
        AccessibilityPermission.requestAutomaticallyIfNeeded()
    }
}

// ─────────────────────────────────────────────
// MARK: - OnboardingView
// ─────────────────────────────────────────────

private struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0:  welcomePage
                case 1:  permissionPage
                case 2:  gesturesPage
                default: finishPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            footer
        }
        .frame(width: 540, height: 600)
        .background(.regularMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Text("Welcome to BetterGlideTool")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Your trackpad and Magic Mouse, with superpowers.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "hand.draw.fill", color: .blue,
                           title: "Gestures for both devices",
                           detail: "Swipes, clicks and force clicks on the trackpad; TipTaps, TipSwipes, flicks and circles on the trackpad and Magic Mouse.")
                featureRow(icon: "bolt.fill", color: .orange,
                           title: "Instant actions",
                           detail: "Cycle Stage Manager, tile and size windows, switch tabs, take screenshots, or send any shortcut.")
                featureRow(icon: "slider.horizontal.3", color: .purple,
                           title: "Per-app and tunable",
                           detail: "Rules for each app, a Live View of every gesture, and tuning tabs for each device.")
            }
            .padding(.top, 12)
            .padding(.horizontal, 50)
            Spacer()
        }
    }

    private var permissionPage: some View {
        PermissionStepView()
    }

    private var gesturesPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Text("Learn the moves")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("These starter gestures are set up for you.\nEvery one of them can be changed in Preferences.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            StarterGestureTour()
                .padding(.top, 4)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 40)
    }

    private var finishPage: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .frame(width: 220, height: 34)
                HStack(spacing: 12) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75")
                    // The real menu bar icon: a hand over a trackpad.
                    Image(nsImage: MenuBarIcon.image)
                        .renderingMode(.template)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    Image(systemName: "magnifyingglass")
                }
                .font(.system(size: 13))
            }

            Text("BetterGlideTool lives in your menu bar")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Click its icon any time to open Preferences,\npause gestures, or quit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                tipRow("Try it now: in Safari or Brave, swipe up with three fingers on the trackpad for a new tab.")
                tipRow("Every gesture in Preferences → Gestures shows a Live View of how to perform it.")
                tipRow("Tune each device in Preferences → Tuning, and watch your touches in Input Monitoring.")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 50)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(page < pageCount - 1 ? 1 : 0)

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            Button(page < pageCount - 1 ? "Continue" : "Get Started") {
                if page < pageCount - 1 { page += 1 } else { onFinish() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }

    // MARK: Bits

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(.yellow)
                .font(.caption)
                .padding(.top, 3)
            Text(text).font(.callout)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Permission step
// ─────────────────────────────────────────────

private struct PermissionStepView: View {
    @State private var granted = AXIsProcessTrusted()
    // Tolerance lets macOS coalesce this wakeup with others instead of scheduling
    // its own. A permission check has no deadline, so drift is free.
    private let poll = Timer.publish(every: 1.0, tolerance: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: granted ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(granted ? .green : .orange)

            Text(granted ? "You're all set" : "One permission needed")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text(granted
                 ? "BetterGlideTool can now see your trackpad gestures.\nHit Continue to learn the moves."
                 : "BetterGlideTool reads trackpad touches and controls windows through macOS Accessibility. Nothing leaves your Mac — there's no network access, no analytics.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if !granted {
                VStack(alignment: .leading, spacing: 12) {
                    stepRow(1, "Click the button below.")
                    stepRow(2, "Find **BetterGlideTool** in the list and switch it on.")
                    stepRow(3, "Come back here — this page updates by itself.")
                }
                .padding(.vertical, 4)

                Button {
                    AccessibilityPermission.request()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Accessibility Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .onReceive(poll) { _ in
            guard !granted else { return }
            let now = AXIsProcessTrusted()
            if now != granted {
                withAnimation { granted = now }
                if now { PreferencesStore.shared.refreshAccessibilityStatus() }
            }
        }
    }

    private func stepRow(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Starter gestures (animated)
// ─────────────────────────────────────────────

/// Cycles through the default gestures, each demonstrated the way the gesture
/// editor's Live View shows it.
struct StarterGestureTour: View {
    private struct Starter: Identifiable {
        let id = UUID()
        let device: GestureDevice
        let direction: GestureDirection
        let fingers: Int
        let does: String
    }
    private let starters: [Starter] = [
        Starter(device: .magicMouse, direction: .tipTapTwoLeft, fingers: 3, does: "Next Stage Manager stage"),
        Starter(device: .magicMouse, direction: .tipSwipeLeftUp, fingers: 3, does: "Maximize the window"),
        Starter(device: .magicMouse, direction: .swipeUp, fingers: 2, does: "New tab in your browser"),
        Starter(device: .magicMouse, direction: .swipeRight, fingers: 1, does: "Flick for Back in your browser"),
        Starter(device: .trackpad, direction: .tipTapTwoRight, fingers: 3, does: "Next tab in your browser"),
        Starter(device: .trackpad, direction: .swipeDown, fingers: 3, does: "Close the tab in your browser"),
        Starter(device: .trackpad, direction: .forceClick, fingers: 3, does: "Screenshot to the clipboard"),
        Starter(device: .trackpad, direction: .swipeUp, fingers: 4, does: "Maximize, then full screen"),
    ]
    @State private var index = 0
    private let tick = Timer.publish(every: 3.2, tolerance: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        let starter = starters[index]
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
                GestureHowToLayer(device: starter.device,
                                  demo: GestureHowTo(direction: starter.direction, fingers: starter.fingers, device: starter.device,
                                                     zone: starter.direction == .forceClick ? .topLeft : .any))
                    .id(starter.id)
            }
            .frame(width: 300, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 4) {
                Label(starter.device == .magicMouse ? "Magic Mouse" : "Trackpad",
                      systemImage: starter.device == .magicMouse ? "magicmouse" : "rectangle.and.hand.point.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(starter.direction.title(fingers: starter.fingers))
                    .font(.headline)
                Text(starter.does)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 62)

            HStack(spacing: 6) {
                ForEach(starters.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: index)
        }
        .onReceive(tick) { _ in index = (index + 1) % starters.count }
    }
}
