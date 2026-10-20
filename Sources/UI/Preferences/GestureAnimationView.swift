import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GestureAnimationView
//
// The gesture editor's Live View, after BetterTouchTool's: a black box that
// demonstrates how to perform the selected gesture as a looping touch session
// (GestureHowTo, drawn by GestureHowToLayer). Zone-restricted trackpad rules
// show their zone.
// ─────────────────────────────────────────────────────────────────────────────

struct GestureAnimationView: View {
    var device: GestureDevice = .trackpad
    var direction: GestureDirection
    var fingerCount: Int
    var zone: TrackpadZone
    var modifierFilter: ModifierFilter
    var speed: GestureSpeed
    var continuous: Bool
    var action: GestureAction
    var showLabel: Bool

    // The Live View box, BetterTouchTool-style: one black panel for every device.
    private let trackpadWidth: CGFloat = 168
    private let trackpadHeight: CGFloat = 112

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Initializers
    // ─────────────────────────────────────────────────────────────────────────

    init(
        rule: GestureRule,
        showLabel: Bool = true
    ) {
        self.device = rule.device
        self.direction = rule.direction
        self.fingerCount = rule.fingers
        self.zone = rule.zone
        self.modifierFilter = rule.modifierFilter
        self.speed = rule.speed
        self.continuous = rule.continuous
        self.action = rule.action
        self.showLabel = showLabel
    }

    init(
        direction: GestureDirection,
        fingerCount: Int,
        zone: TrackpadZone = .any,
        modifierFilter: ModifierFilter = .any,
        speed: GestureSpeed = .normal,
        continuous: Bool = false,
        action: GestureAction = .doNothing,
        showLabel: Bool = true
    ) {
        self.direction = direction
        self.fingerCount = fingerCount
        self.zone = zone
        self.modifierFilter = modifierFilter
        self.speed = speed
        self.continuous = continuous
        self.action = action
        self.showLabel = showLabel
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                    if zone != .any { zoneOverlay }
                    GestureHowToLayer(device: device,
                                      demo: GestureHowTo(direction: direction, fingers: fingerCount, device: device, zone: zone, speed: speed))
                }
                .frame(width: trackpadWidth, height: trackpadHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Live View")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if showLabel {
                gestureSummaryLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live View: shows how to perform \(direction.title(fingers: fingerCount))")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Zone Overlay
    // ─────────────────────────────────────────────────────────────────────────

    private var zoneOverlay: some View {
        let size = CGSize(width: trackpadWidth, height: trackpadHeight)
        let rect = zoneRect(in: size)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Zone tag anchored in bottom-leading corner of zone
            VStack {
                Spacer()
                HStack {
                    Text(zone.rawValue)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .padding(4)
        }
    }

    private func zoneRect(in size: CGSize) -> CGRect {
        let reachX: CGFloat = size.width * 0.46
        let reachY: CGFloat = size.height * 0.48

        switch zone {
        case .any:
            return CGRect(origin: .zero, size: size)
        case .topLeft:
            return CGRect(x: 5, y: 5, width: reachX, height: reachY)
        case .topRight:
            return CGRect(x: size.width - reachX - 5, y: 5, width: reachX, height: reachY)
        case .bottomLeft:
            return CGRect(x: 5, y: size.height - reachY - 5, width: reachX, height: reachY)
        case .bottomRight:
            return CGRect(x: size.width - reachX - 5, y: size.height - reachY - 5, width: reachX, height: reachY)
        case .topEdge:
            return CGRect(x: 5, y: 5, width: size.width - 10, height: size.height * 0.40)
        case .bottomEdge:
            return CGRect(x: 5, y: size.height - size.height * 0.40 - 5, width: size.width - 10, height: size.height * 0.40)
        case .leftEdge:
            return CGRect(x: 5, y: 5, width: size.width * 0.40, height: size.height - 10)
        case .rightEdge:
            return CGRect(x: size.width - size.width * 0.40 - 5, y: 5, width: size.width * 0.40, height: size.height - 10)
        }
    }

    private var speedColor: Color {
        switch speed {
        case .slow:   return .indigo
        case .normal: return .secondary
        case .fast:   return .orange
        case .any:    return .secondary
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Modifier Keycap
    // ─────────────────────────────────────────────────────────────────────────

    private var modifierInfo: (symbol: String, name: String)? {
        switch modifierFilter {
        case .shiftHeld:   return ("⇧", "Shift")
        case .controlHeld: return ("⌃", "Control")
        case .optionHeld:  return ("⌥", "Option")
        case .commandHeld: return ("⌘", "Command")
        default:           return nil
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Gesture Summary Label
    // ─────────────────────────────────────────────────────────────────────────

    private var gestureSummaryLabel: some View {
        HStack(spacing: 6) {
            // Trigger summary
            HStack(spacing: 4) {
                if modifierFilter.requiresModifierHeld, let mod = modifierInfo {
                    Text(mod.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text(direction.title(fingers: fingerCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if direction.hasSpeed {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(speed.rawValue.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(speedColor)
                }

                if zone != .any {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(zone.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Destination action indicator
            if action != .doNothing {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 3) {
                    Image(systemName: action.iconName)
                        .font(.system(size: 10))
                    Text(action.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
