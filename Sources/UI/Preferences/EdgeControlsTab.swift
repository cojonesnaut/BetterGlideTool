import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeControlsTab
//
// Trackpad Edge Controls: an at-a-glance trackpad with live levels on its
// edges, then short cards for edges, corners, sliding and feedback.
// ─────────────────────────────────────────────────────────────────────────────

/// An edge or corner picked on the diagram, so the matching row lights up.
enum EdgeControlsSelection: Hashable {
    case edge(TrackpadPhysicalEdge)
    case corner(TrackpadCorner)
}

struct EdgeControlsTab: View {
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var controller = EdgeControlsController.shared
    @State private var selection: EdgeControlsSelection? = nil
    @State private var levels: [EdgeAction: Double] = [:]

    /// Categories along the top, as on the Tuning page.
    enum Page: String, CaseIterable, Identifiable {
        case edges = "Edges", corners = "Corners", sliding = "While Sliding", feedback = "Feedback"
        var id: String { rawValue }
    }
    @AppStorage("edgeControlsPage") private var page: Page = .edges

    private let levelTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var settings: EdgeControlsSettings { store.edgeControls }

    var body: some View {
        // Only the category picker sits outside the scroll view, exactly as on
        // the Tuning page. Anything else up here — the header's wrapping text
        // in particular — feeds its ideal height into the window's size and,
        // with `.contentMinSize` resizability, can stretch the whole window's
        // content past the screen, pushing the sidebar and page up under the
        // title bar. Keep it that way.
        VStack(spacing: 0) {
            if settings.enabled {
                GlassSegmentedPicker("Edge Controls category", selection: $page,
                                     options: Page.allCases.map { ($0, L($0.rawValue)) }, fillsWidth: true)
                .padding(.horizontal)
                .padding(.vertical, 10)
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    if settings.enabled {
                        switch page {
                        case .edges:
                            glanceCard
                            edgesCard
                            if settings.usesScroll { scrollCard }
                        case .corners:
                            glanceCard
                            cornersCard
                        case .sliding:
                            slidingCard
                        case .feedback:
                            feedbackCard
                        }

                        HStack {
                            Spacer()
                            Button("Reset Edge Controls to Defaults") {
                                withAnimation { store.resetEdgeControls() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.enabled)
        .onChange(of: selection) { newValue in
            // Clicking the diagram opens the category that holds that setting.
            switch newValue {
            case .edge: page = .edges
            case .corner: page = .corners
            case nil: break
            }
        }
        .onAppear(perform: refreshLevels)
        .onReceive(levelTimer) { _ in refreshLevels() }
        .liveStatus()   // the active edge comes from the menu bar app
    }

    private func refreshLevels() {
        guard settings.enabled else { return }
        var next: [EdgeAction: Double] = [:]
        for action in Set(TrackpadPhysicalEdge.allCases.map { settings.action(for: $0) }) {
            if let level = EdgeLiveLevels.level(for: action) { next[action] = level }
        }
        if next != levels { levels = next }
    }

    // MARK: - Header

    private var headerCard: some View {
        EdgeCard {
            HStack(alignment: .top, spacing: 12) {
                EdgeIconTile(systemName: "rectangle.inset.filled", tint: .primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edge Controls")
                        .font(.headline)
                    // This header scrolls with the page; see `body` for why it must
                    // never sit outside the scroll view again.
                    Text("Slide one finger along an edge of the trackpad to change volume, brightness and more, or double-tap a corner to run an action.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: binding(\.enabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(14)
        }
    }

    // MARK: - At a Glance

    private var glanceCard: some View {
        EdgeSection(title: L("At a Glance"), icon: "rectangle.and.hand.point.up.left") {
            VStack(spacing: 10) {
                TrackpadGlanceView(
                    settings: settings,
                    levels: levels,
                    activeEdge: controller.activeEdge,
                    firedCorner: controller.firedCorner,
                    selection: $selection
                )
                .frame(height: 210)

                HStack {
                    Text("Live levels. Click an edge or corner to find its setting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        store.updateEdgeControls { s in
                            let left = s.leftEdge
                            s.leftEdge = s.rightEdge
                            s.rightEdge = left
                        }
                    } label: {
                        Label("Swap Sides", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(settings.leftEdge == settings.rightEdge)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Edges

    private var edgesCard: some View {
        EdgeSection(title: L("Edges"), icon: "square.dashed") {
            VStack(spacing: 0) {
                ForEach(Array([TrackpadPhysicalEdge.left, .right, .top, .bottom].enumerated()), id: \.element) { index, edge in
                    if index > 0 { EdgeRowDivider() }
                    edgeRow(edge)
                }

                if settings.usesMedia {
                    EdgeRowDivider()
                    EdgeToggleRow(
                        title: L("Double-Tap to Play or Pause"),
                        subtitle: L("Double-tap the media strip, close to the edge."),
                        isOn: binding(\.mediaDoubleTapPlayPause)
                    )
                    EdgeRowDivider()
                    EdgeToggleRow(
                        title: L("Reverse Media Swipe"),
                        subtitle: settings.mediaReverseSwipe
                            ? L("Swipe left or down for the next track.")
                            : L("Swipe right or up for the next track."),
                        isOn: binding(\.mediaReverseSwipe)
                    )
                }
            }
        }
    }

    private func edgeRow(_ edge: TrackpadPhysicalEdge) -> some View {
        let action = settings.action(for: edge)
        return EdgeRow(
            icon: action.iconName,
            iconTint: action == .none ? .secondary : .primary,
            title: edge.displayName,
            subtitle: action.hint,
            isHighlighted: selection == .edge(edge),
            isActive: controller.activeEdge == edge
        ) {
            Picker("", selection: Binding(
                get: { settings.action(for: edge) },
                set: { value in store.updateEdgeControls { $0.setAction(value, for: edge) } }
            )) {
                ForEach(EdgeAction.allCases) { item in
                    Label(item.displayName, systemImage: item.iconName).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
        .onTapGesture { selection = .edge(edge) }
    }

    // MARK: - Corners

    private var cornersCard: some View {
        EdgeSection(title: L("Corners"), icon: "square.on.square.dashed") {
            VStack(spacing: 0) {
                ForEach(Array(TrackpadCorner.allCases.enumerated()), id: \.element) { index, corner in
                    if index > 0 { EdgeRowDivider() }
                    cornerRow(corner)
                }
                EdgeFootnote("Double-tap a corner to run its action. Taps in a corner that has an action never click, even with Tap to Click on.")
            }
        }
    }

    private func cornerRow(_ corner: TrackpadCorner) -> some View {
        let action = settings.cornerAction(for: corner)
        return VStack(spacing: 0) {
            EdgeRow(
                icon: action.iconName,
                iconTint: action == .none ? .secondary : .primary,
                title: corner.displayName,
                subtitle: action == .none ? L("Off") : L("Double-tap"),
                isHighlighted: selection == .corner(corner),
                isActive: controller.firedCorner == corner
            ) {
                Picker("", selection: Binding(
                    get: { settings.cornerAction(for: corner) },
                    set: { value in store.updateEdgeControls { $0.setCornerAction(value, for: corner) } }
                )) {
                    ForEach(Array(EdgeCornerAction.groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Divider() }
                        ForEach(group) { item in
                            Label(item.displayName, systemImage: item.iconName).tag(item)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .onTapGesture { selection = .corner(corner) }

            if action == .runShortcut {
                ShortcutChooserRow(
                    name: Binding(
                        get: { settings.shortcutName(for: corner) },
                        set: { value in store.updateEdgeControls { $0.setShortcutName(value, for: corner) } }
                    )
                )
            }
        }
    }

    // MARK: - While Sliding

    private var slidingCard: some View {
        EdgeSection(title: L("While Sliding"), icon: "hand.draw") {
            VStack(spacing: 0) {
                EdgeRow(icon: "arrow.up.and.down", iconTint: .primary,
                        title: L("Where Side Slides Can Start"),
                        subtitle: L("Left and right edges only. A slide can run the whole edge once it starts.")) {
                    Picker("", selection: binding(\.activeArea)) {
                        ForEach(EdgeActiveArea.allCases) { area in
                            Text(area.displayName).tag(area)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                EdgeRowDivider()
                EdgeToggleRow(title: L("Precise Sliding"),
                              subtitle: L("Volume and brightness move in quarter steps."),
                              isOn: binding(\.preciseSliding))
                EdgeRowDivider()
                EdgeToggleRow(title: L("Only While Holding Fn or Option"),
                              subtitle: L("Hold the key before your finger touches the edge."),
                              isOn: binding(\.requireModifier))
                EdgeRowDivider()
                EdgeToggleRow(title: L("Pause While Typing"),
                              subtitle: L("Edges ignore touches for a moment after a key press."),
                              isOn: binding(\.pauseWhileTyping))
                EdgeRowDivider()
                EdgeSliderRow(title: L("Edge Width"),
                              subtitle: L("How far in from the edge a slide can start."),
                              value: binding(\.marginMm),
                              range: EdgeControlsSettings.marginMmRange, step: 0.5,
                              readout: L("%@ mm", String(format: "%.1f", settings.marginMm)))
                EdgeRowDivider()
                EdgeSliderRow(title: L("Sensitivity"),
                              subtitle: L("How much a slide changes the level for the same distance."),
                              value: binding(\.sensitivity),
                              range: EdgeControlsSettings.sensitivityRange, step: 0.1,
                              readout: String(format: "%.1f×", settings.sensitivity))
                EdgeRowDivider()
                EdgeSliderRow(title: L("Start Distance"),
                              subtitle: L("How far you slide before the edge takes over. Raise it if edges trigger while you move the pointer."),
                              value: binding(\.activationTravelMm),
                              range: EdgeControlsSettings.activationTravelMmRange, step: 0.5,
                              readout: L("%@ mm", String(format: "%.1f", settings.activationTravelMm)))
            }
        }
    }

    // MARK: - Feedback

    private var feedbackCard: some View {
        EdgeSection(title: L("Feedback"), icon: "waveform") {
            VStack(spacing: 0) {
                EdgeRow(icon: "hand.tap", iconTint: .primary,
                        title: L("Haptic Feedback"),
                        subtitle: L("A tick as a slide moves, and a tap when a track skips or a corner runs.")) {
                    EmptyView()
                }
                GlassSegmentedPicker(L("Haptic Feedback"), selection: binding(\.hapticLevel),
                                     options: EdgeHapticLevel.allCases.map { ($0, $0.displayName) }, fillsWidth: true)
                .padding(.leading, 54)
                .padding(.trailing, 14)
                .padding(.bottom, 12)
                if !store.hapticFeedbackEnabled && settings.hapticLevel != .off {
                    EdgeFootnote("Haptic feedback is off for the whole app in General.")
                }
            }
        }
    }

    // MARK: - Scrolling

    private var scrollCard: some View {
        EdgeSection(title: L("Edge Scrolling"), icon: "arrow.up.arrow.down") {
            VStack(spacing: 0) {
                EdgeSliderRow(title: L("Scroll Speed"),
                              subtitle: L("How far the page moves for each millimetre of finger travel."),
                              value: binding(\.scrollSpeed),
                              range: EdgeControlsSettings.scrollSpeedRange, step: 1,
                              readout: L("%@ pt/mm", String(format: "%.0f", settings.scrollSpeed)))
                EdgeRowDivider()
                EdgeToggleRow(title: L("Glide After Lifting Your Finger"),
                              subtitle: settings.scrollMomentum
                                ? L("A flick keeps scrolling and coasts to a stop.")
                                : L("Scrolling stops the moment you lift."),
                              isOn: binding(\.scrollMomentum))
                EdgeRowDivider()
                EdgeToggleRow(title: L("Reverse Scroll Direction"),
                              subtitle: settings.invertScroll
                                ? L("Sliding up or right moves up the page.")
                                : L("Sliding up or right moves down the page, like natural scrolling."),
                              isOn: binding(\.invertScroll))
            }
        }
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<EdgeControlsSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { val in store.updateEdgeControls { $0[keyPath: keyPath] = val } }
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Building blocks
// ─────────────────────────────────────────────────────────────────────────────

/// A rounded panel, the page's one container style.
struct EdgeCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A small heading above a card.
struct EdgeSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            EdgeCard(content: content)
        }
    }
}

struct EdgeIconTile: View {
    let systemName: String
    var tint: Color = .primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .glassSelection(true, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct EdgeRowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

struct EdgeFootnote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

/// Icon tile, title and subtitle on the left, one control on the right.
struct EdgeRow<Control: View>: View {
    let icon: String?
    var iconTint: Color = .primary
    let title: String
    let subtitle: String
    var isHighlighted = false
    var isActive = false
    @ViewBuilder let control: () -> Control

    init(icon: String?, iconTint: Color = .primary, title: String, subtitle: String,
         isHighlighted: Bool = false, isActive: Bool = false,
         @ViewBuilder control: @escaping () -> Control) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.isHighlighted = isHighlighted
        self.isActive = isActive
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                EdgeIconTile(systemName: icon, tint: isActive ? .green : iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.green)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSelection(isHighlighted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct EdgeToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct EdgeSliderRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(readout)
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            // No `step:` — on macOS it draws a tick for every step. Values are
            // rounded to the step here instead.
            Slider(value: Binding(
                get: { value },
                set: { value = (($0 / step).rounded() * step).clamped(to: range) }
            ), in: range)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shortcut chooser
// ─────────────────────────────────────────────────────────────────────────────

/// The user's shortcuts from Shortcuts.app, read once when a picker first needs them.
final class ShortcutLibrary: ObservableObject {
    static let shared = ShortcutLibrary()
    @Published private(set) var names: [String] = []
    @Published private(set) var isLoading = false
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            var names: [String] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
            DispatchQueue.main.async {
                self.names = names
                self.isLoading = false
                self.loaded = true
            }
        }
    }
}

private struct ShortcutChooserRow: View {
    @Binding var name: String?
    @ObservedObject private var library = ShortcutLibrary.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Shortcut")
                .foregroundColor(.secondary)
            Spacer()
            Menu {
                if library.names.isEmpty {
                    Text(library.isLoading ? L("Loading Shortcuts…") : L("No Shortcuts Yet"))
                } else {
                    ForEach(library.names, id: \.self) { item in
                        Button(item) { name = item }
                    }
                }
                Divider()
                Button("Refresh List") { library.reload() }
            } label: {
                Text(name ?? L("Choose a Shortcut"))
            }
            .frame(width: 200)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help(L("Open Shortcuts"))
        }
        .padding(.leading, 54)
        .padding(.trailing, 14)
        .padding(.bottom, 10)
        .onAppear { library.loadIfNeeded() }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Trackpad at a glance
// ─────────────────────────────────────────────────────────────────────────────

private struct TrackpadGlanceView: View {
    let settings: EdgeControlsSettings
    let levels: [EdgeAction: Double]
    let activeEdge: TrackpadPhysicalEdge?
    let firedCorner: TrackpadCorner?
    @Binding var selection: EdgeControlsSelection?

    private let strip: CGFloat = 34
    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let corner = strip

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 16))
                    Text("Normal Pointer Area")
                        .font(.caption2)
                }
                .foregroundColor(.secondary.opacity(0.7))

                // Edges
                edge(.top, frame: CGRect(x: corner + 2 * gap, y: gap,
                                         width: w - 2 * corner - 4 * gap, height: strip))
                edge(.bottom, frame: CGRect(x: corner + 2 * gap, y: h - strip - gap,
                                            width: w - 2 * corner - 4 * gap, height: strip))
                edge(.left, frame: CGRect(x: gap, y: corner + 2 * gap,
                                          width: strip, height: h - 2 * corner - 4 * gap))
                edge(.right, frame: CGRect(x: w - strip - gap, y: corner + 2 * gap,
                                           width: strip, height: h - 2 * corner - 4 * gap))

                // Corners
                cornerTile(.topLeft, center: CGPoint(x: gap + corner / 2, y: gap + corner / 2))
                cornerTile(.topRight, center: CGPoint(x: w - gap - corner / 2, y: gap + corner / 2))
                cornerTile(.bottomLeft, center: CGPoint(x: gap + corner / 2, y: h - gap - corner / 2))
                cornerTile(.bottomRight, center: CGPoint(x: w - gap - corner / 2, y: h - gap - corner / 2))
            }
        }
    }

    private func edge(_ edge: TrackpadPhysicalEdge, frame: CGRect) -> some View {
        let action = settings.action(for: edge)
        let isOn = action != .none
        let isActive = activeEdge == edge
        let isSelected = selection == .edge(edge)
        let level = levels[action]
        // Green while the edge is being used; otherwise neutral, with assigned
        // edges drawn as glass rather than an accent-coloured wash.
        let tint: Color = isActive ? .green : .primary

        return ZStack(alignment: edge.isHorizontal ? .leading : .bottom) {
            if isOn && !isActive {
                GlassSurface(shape: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? tint.opacity(0.22) : Color.primary.opacity(0.04))
            }

            if let level {
                // The live level fills the strip from the bottom (or the left).
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(isActive ? 0.28 : 0.16))
                    .frame(width: edge.isHorizontal ? max(frame.width * level, 0) : nil,
                           height: edge.isHorizontal ? nil : max(frame.height * level, 0))
            }

            stripLabel(edge: edge, action: action, level: level)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isActive ? tint : (isSelected ? Color.primary.opacity(0.55) : Color.clear), lineWidth: 1.5)
        )
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selection = .edge(edge) } }
        .help(edge.displayName + " — " + action.displayName)
    }

    @ViewBuilder
    private func stripLabel(edge: TrackpadPhysicalEdge, action: EdgeAction, level: Double?) -> some View {
        let color: Color = action == .none ? .secondary.opacity(0.6) : .primary.opacity(0.8)
        if edge.isHorizontal {
            HStack(spacing: 6) {
                Image(systemName: action.iconName)
                Text(action == .none ? L("Off") : action.displayName)
                if let level { Text(percent(level)).monospacedDigit() }
            }
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .lineLimit(1)
        } else {
            VStack(spacing: 4) {
                Image(systemName: action.iconName)
                    .font(.system(size: 12, weight: .semibold))
                if let level {
                    Text(percent(level))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundColor(color)
        }
    }

    private func cornerTile(_ corner: TrackpadCorner, center: CGPoint) -> some View {
        let action = settings.cornerAction(for: corner)
        let isOn = action != .none
        let isSelected = selection == .corner(corner)
        // Green for a moment after its double-tap runs, like an edge mid-slide.
        let isActive = isOn && firedCorner == corner

        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isActive ? Color.green : (isSelected ? Color.primary.opacity(0.55) : Color.primary.opacity(isOn ? 0 : 0.18)),
                          style: StrokeStyle(lineWidth: isSelected || isActive ? 1.5 : 1, dash: isOn ? [] : [3, 3]))
            .glassSelection(isOn && !isActive, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(isActive ? RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.green.opacity(0.22)) : nil)
            .animation(.easeOut(duration: 0.2), value: isActive)
            .overlay(
                Image(systemName: isOn ? action.iconName : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isOn ? .primary.opacity(0.8) : .secondary.opacity(0.6))
            )
            .frame(width: strip, height: strip)
            .position(center)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selection = .corner(corner) } }
            .help(corner.displayName + " — " + action.displayName)
    }

    private func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}
