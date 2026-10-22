import SwiftUI
import UniformTypeIdentifiers

/// A quiet, device-sized touch surface; the raw table is opt-in below it.
struct LiveContactsReadout: View {
    var device: GestureDevice = .trackpad
    let frame: LiveContactFrame
    let transitions: [LiveContactTransition]
    let stale: Bool
    var gestures: [LiveGestureEvent] = []
    var showIDs = false
    var clearLog: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                // The device's own outline, sized to its proportions, above the status line.
                let surface = DeviceSurfaceShape.fitted(device,
                    in: CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 34)), inset: 18)
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(red: 0.20, green: 0.13, blue: 0.23), Color(red: 0.105, green: 0.105, blue: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    DeviceSurfaceShape(device: device)
                        .path(in: surface)
                        .fill(Color.white.opacity(0.045))
                    DeviceSurfaceShape(device: device)
                        .path(in: surface)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.2)
                    FingerDots(frame: frame, live: !stale, surface: surface, showIDs: showIDs)
                    if stale {
                        VStack(spacing: 7) {
                            Image(systemName: device == .trackpad ? "rectangle.and.hand.point.up.left" : "magicmouse")
                                .font(.title2)
                            Text("Touch the \(device == .trackpad ? "trackpad" : "Magic Mouse")")
                                .font(.callout)
                            Text("Keep gestures enabled to see contacts").font(.caption)
                        }.foregroundStyle(Color.white.opacity(0.42))
                            .multilineTextAlignment(.center)
                            .frame(width: surface.width, height: surface.height)
                            .position(x: surface.midX, y: surface.midY)
                    }
                    HStack(spacing: 7) {
                        Circle().fill(stale ? Color.gray : Color.green).frame(width: 5, height: 5)
                        Text(stale ? "Waiting for input" : "\(frame.contacts.count) contacts")
                        Spacer()
                        Text(frame.appName == "—" ? device.monitoringTitle : frame.appName).lineLimit(1)
                    }.font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.55)).padding(12)
                }
            }
            Divider().overlay(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gesture Log").font(.system(size: 12, weight: .semibold))
                        Text("Latest first").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: clearLog) { Image(systemName: "trash").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(gestures.isEmpty)
                        .help("Clear gesture log")
                }.padding(12)
                Divider()
                if gestures.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No gestures yet").font(.callout)
                        Text("Assigned gestures appear here when their actions are dispatched.").font(.caption)
                    }.foregroundStyle(.secondary).padding(12)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 13) {
                            ForEach(gestures) { event in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                                    Text(event.gesture).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                    Text(event.action).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                    if let result = event.stageResult {
                                        Text(result.message).font(.system(size: 10))
                                            .foregroundStyle(result.state == "failed" ? Color.orange : Color.secondary)
                                            .lineLimit(3).help(result.message)
                                    }
                                    Text(event.appName).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .help("\(event.gesture) → \(event.action) in \(event.appName)")
                            }
                        }.padding(12)
                    }
                }
            }.frame(width: 220).background(Color.white.opacity(0.025))
        }
        .background(Color(red: 0.12, green: 0.115, blue: 0.13))
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Fingers drawn as BetterTouchTool draws them in its Live View: a solid purple
/// dot per contact that fades and grows in as the finger lands, follows it, and
/// fades out as it lifts.
private struct FingerDots: View {
    let frame: LiveContactFrame
    let live: Bool
    let surface: CGRect
    let showIDs: Bool
    @State private var touches: [Int32: Touch] = [:]

    private struct Touch { var x: Double; var y: Double; var landed: Double; var lifted: Double? }
    private static let fadeIn = 0.12
    private static let fadeOut = 0.25

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: touches.isEmpty)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in draw(in: &context, now: now) }
        }
        .allowsHitTesting(false)
        .onAppear { update() }
        .onChange(of: frame) { _ in update() }
        .onChange(of: live) { _ in update() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(frame.contacts.count) contacts")
    }

    private func update() {
        let now = Date.timeIntervalSinceReferenceDate
        let down = live ? frame.contacts.filter { $0.state == 3 || $0.state == 4 } : []
        for contact in down {
            if var touch = touches[contact.id], touch.lifted == nil {
                touch.x = contact.x; touch.y = contact.y
                touches[contact.id] = touch
            } else {
                touches[contact.id] = Touch(x: contact.x, y: contact.y, landed: now)
            }
        }
        for (id, touch) in touches where touch.lifted == nil && !down.contains(where: { $0.id == id }) {
            touches[id]?.lifted = now
            // Forget it once faded, so nothing animates while no finger is down.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut + 0.05) {
                if let lifted = touches[id]?.lifted, Date.timeIntervalSinceReferenceDate - lifted >= Self.fadeOut { touches[id] = nil }
            }
        }
    }

    private func draw(in context: inout GraphicsContext, now: Double) {
        let radius = max(7, min(surface.width, surface.height) * 0.055)
        for (id, touch) in touches {
            let appear = min(1, (now - touch.landed) / Self.fadeIn)
            let vanish = touch.lifted.map { max(0, 1 - (now - $0) / Self.fadeOut) } ?? 1
            let alpha = appear * vanish
            guard alpha > 0 else { continue }
            let r = radius * (0.55 + 0.45 * appear)
            let center = CGPoint(x: surface.minX + min(1, max(0, touch.x)) * surface.width,
                                 y: surface.minY + (1 - min(1, max(0, touch.y))) * surface.height)
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.accentColor.opacity(alpha)))
            if showIDs {
                context.draw(Text("\(id)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(alpha)),
                             at: center)
            }
        }
    }
}

private struct LiveContactsDetails: View {
    let frame: LiveContactFrame
    let transitions: [LiveContactTransition]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(frame.feedback).font(.callout)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow { Text("ID"); Text("X"); Text("Y"); Text("Size"); Text("State"); Text("Role") }
                    .foregroundStyle(.secondary)
                ForEach(frame.contacts) { contact in
                    GridRow {
                        Text("\(contact.id)")
                        Text(String(format: "%.4f", contact.x)); Text(String(format: "%.4f", contact.y))
                        Text(String(format: "%.4f", contact.size)); Text("\(contact.state)"); Text(contact.role)
                    }
                }
            }.font(.system(.caption, design: .monospaced))
            if !transitions.isEmpty {
                Text(transitions.suffix(4).reversed().map {
                    String(format: "%.3f s · ID %d %@", $0.timestamp, $0.id, $0.landed ? "landed" : "lifted")
                }.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text("Size is contact size, not pressure. Coordinates are normalized; state is the raw sensor value. Lifts are inferred when contact IDs disappear.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled)
    }
}

struct LiveContactsView: View {
    let device: GestureDevice
    let floating: Bool
    @ObservedObject private var monitor: LiveContactsMonitor
    init(device: GestureDevice = .trackpad, floating: Bool = false) {
        self.device = device; self.floating = floating
        _monitor = ObservedObject(wrappedValue: LiveContactsMonitor.forDevice(device))
    }
    @State private var message: String?
    @State private var showIDs = false
    @State private var showDetails = false
    @ObservedObject private var actionBlock = GestureActionBlock.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label(device.monitoringTitle, systemImage: device == .trackpad ? "rectangle.and.hand.point.up.left" : "magicmouse")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Toggle("Block Real Gesture Triggering", isOn: $actionBlock.isOn).toggleStyle(.checkbox)
                    .help("Gestures are recognised and logged, but their actions do not run — only while Input Monitoring is open.")
                Toggle("Show IDs", isOn: $showIDs).toggleStyle(.checkbox)
                Toggle("Details", isOn: $showDetails).toggleStyle(.checkbox)
                if !floating {
                    Button { LiveContactsPanelController.forDevice(device).show() } label: {
                        Label("Float", systemImage: "macwindow.on.rectangle")
                    }.help("Open Floating Panel")
                }
            }.font(.caption)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LiveContactsReadout(device: device, frame: monitor.frame, transitions: monitor.transitions,
                    stale: monitor.lastReceived == 0 || ProcessInfo.processInfo.systemUptime - monitor.lastReceived > 2,
                    gestures: monitor.gestures, showIDs: showIDs, clearLog: monitor.clearGestureLog)
            }.frame(minHeight: floating ? (showDetails ? 100 : 245) : 340, idealHeight: floating ? (showDetails ? 150 : 285) : 380, maxHeight: .infinity)
            if showDetails {
                ScrollView { LiveContactsDetails(frame: monitor.frame, transitions: monitor.transitions) }
                    .frame(height: floating ? 125 : 175)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Button(monitor.isRecording ? "Stop Recording" : "Record 15 Seconds") {
                    message = nil
                    if monitor.isRecording { monitor.stopRecording() } else { monitor.startRecording() }
                }
                Button("Export…") { exportRecording() }
                    .disabled(monitor.recordedFrameCount == 0 || monitor.isRecording)
                Spacer()
                Button("Copy Readings") {
                    do {
                        let data = try monitor.snapshotData()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                        message = "Current readings copied."
                    } catch { message = error.localizedDescription }
                }
            }.controlSize(.small)
            Text(message ?? (monitor.isRecording ? "Recording… \(monitor.recordedFrameCount) frames" :
                (monitor.recordedFrameCount > 0 ? "\(monitor.recordedFrameCount) frames ready to export." : "Contact size is not pressure. Recordings include contacts, app names and dispatched gestures.")))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .onAppear { if !floating { monitor.setVisible(true, owner: "settings") } }
        .onDisappear { if !floating { monitor.setVisible(false, owner: "settings") } }
    }
    private func exportRecording() {
        do {
            let data = try monitor.recordingData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "BetterGlideTool-\(device.monitoringTitle.replacingOccurrences(of: " ", with: "-"))-Live-Contacts.json"
            panel.begin { result in
                guard result == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic); message = "Recording exported." }
                catch { message = "Export failed: \(error.localizedDescription)" }
            }
        } catch { message = "Export failed: \(error.localizedDescription)" }
    }
}

/// No key or main-window eligibility: opening/updating this panel never changes
/// the browser used by application-specific gesture conditions.
final class LiveContactsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LiveContactsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class LiveContactsPanelController: NSObject, NSWindowDelegate {
    static let shared = LiveContactsPanelController(device: .trackpad)
    static let mouse = LiveContactsPanelController(device: .magicMouse)
    static func forDevice(_ device: GestureDevice) -> LiveContactsPanelController { device == .trackpad ? shared : mouse }
    private let device: GestureDevice
    private init(device: GestureDevice) { self.device = device; super.init() }
    private var panel: LiveContactsPanel?

    func show() {
        precondition(Thread.isMainThread)
        if panel == nil {
            panel = Self.makePanel(device: device)
            panel?.delegate = self
        }
        LiveContactsMonitor.forDevice(device).setVisible(true, owner: "panel")
        panel?.orderFrontRegardless()
    }
    static func makePanel(device: GestureDevice = .trackpad) -> LiveContactsPanel {
        let window = LiveContactsPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Live Contacts — \(device.monitoringTitle)"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        window.minSize = NSSize(width: 640, height: 390)
        window.contentView = LiveContactsHostingView(rootView:
            LiveContactsView(device: device, floating: true).frame(maxWidth: .infinity, maxHeight: .infinity))
        window.setFrameAutosaveName("LiveContactsPanel-v2-\(device.rawValue)")
        if !window.setFrameUsingName("LiveContactsPanel-v2-\(device.rawValue)") { window.center() }
        return window
    }
    func windowWillClose(_ notification: Notification) {
        LiveContactsMonitor.forDevice(device).setVisible(false, owner: "panel")
    }
}
