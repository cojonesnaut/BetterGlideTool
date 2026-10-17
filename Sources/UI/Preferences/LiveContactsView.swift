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
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(red: 0.20, green: 0.13, blue: 0.23), Color(red: 0.105, green: 0.105, blue: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if !stale {
                        ForEach(frame.contacts) { contact in
                            ZStack {
                                Circle().fill(RadialGradient(colors: [Color.purple.opacity(0.35), Color.purple.opacity(0)], center: .center, startRadius: 2, endRadius: 25)).frame(width: 50, height: 50)
                                Circle().fill(RadialGradient(colors: [Color(red: 0.85, green: 0.57, blue: 0.89), Color(red: 0.61, green: 0.34, blue: 0.67)], center: .center, startRadius: 0, endRadius: 14))
                                    .frame(width: diameter(contact), height: diameter(contact))
                                if showIDs {
                                    Text("\(contact.id)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                                }
                            }
                            .position(x: 24 + min(1, max(0, contact.x)) * max(1, geometry.size.width - 48),
                                      y: 24 + (1 - min(1, max(0, contact.y))) * max(1, geometry.size.height - 72))
                            .accessibilityLabel("Contact \(contact.id), \(contact.role)")
                        }
                    }
                    if stale {
                        VStack(spacing: 7) {
                            Image(systemName: device == .trackpad ? "rectangle.and.hand.point.up.left" : "magicmouse")
                                .font(.title2)
                            Text("Touch the \(device == .trackpad ? "trackpad" : "Magic Mouse")")
                                .font(.callout)
                            Text("Keep gestures enabled to see contacts").font(.caption)
                        }.foregroundStyle(Color.white.opacity(0.42))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func diameter(_ contact: LiveContact) -> CGFloat {
        CGFloat(14 + min(1, max(0, contact.size)) * 10)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label(device.monitoringTitle, systemImage: device == .trackpad ? "rectangle.and.hand.point.up.left" : "magicmouse")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
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
