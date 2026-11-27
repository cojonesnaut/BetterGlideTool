import SwiftUI
import AppKit

// ─────────────────────────────────────────────
// MARK: - Icon & widget style
//
// System Settings › Appearance › "Icon & widget style" is saved in the global
// preferences domain. Apple doesn't document the keys, so anything unexpected
// falls back to the Default style rather than failing. Values seen on
// macOS 26/27: AppleIconAppearanceTheme = RegularDark, ClearDark, TintedLight…
// (style + Light/Dark, no suffix or "Automatic" = follow the appearance);
// AppleIconAppearanceTintColor = a colour name, or "Other" with the colour in
// AppleIconAppearanceCustomTintColor as "r g b a".
// ─────────────────────────────────────────────

struct IconAppearance: Equatable {
    enum Style: Equatable { case regular, clear, tinted }

    var style: Style = .regular
    /// `nil` follows the window's light/dark appearance.
    var forcedDark: Bool? = nil
    var tint: Color = Color(nsColor: .controlAccentColor)

    static func current() -> IconAppearance {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return IconAppearance(theme: globalString("AppleIconAppearanceTheme"),
                              tintName: globalString("AppleIconAppearanceTintColor"),
                              customTint: globalString("AppleIconAppearanceCustomTintColor"))
    }

    init(style: Style = .regular, forcedDark: Bool? = nil, tint: Color = Color(nsColor: .controlAccentColor)) {
        self.style = style
        self.forcedDark = forcedDark
        self.tint = tint
    }

    init(theme: String?, tintName: String?, customTint: String?) {
        let theme = theme ?? ""
        if theme.hasPrefix("Clear") { style = .clear }
        else if theme.hasPrefix("Tinted") { style = .tinted }
        else { style = .regular }
        if theme.hasSuffix("Dark") { forcedDark = true }
        else if theme.hasSuffix("Light") { forcedDark = false }
        tint = Self.tintColor(name: tintName, custom: customTint)
    }

    private static func tintColor(name: String?, custom: String?) -> Color {
        if name == "Other", let custom {
            let parts = custom.split(separator: " ").compactMap { Double($0) }
            if parts.count >= 3 { return Color(red: parts[0], green: parts[1], blue: parts[2]) }
        }
        switch name?.lowercased() {
        case "blue":     return Color(nsColor: .systemBlue)
        case "purple":   return Color(nsColor: .systemPurple)
        case "pink":     return Color(nsColor: .systemPink)
        case "red":      return Color(nsColor: .systemRed)
        case "orange":   return Color(nsColor: .systemOrange)
        case "yellow":   return Color(nsColor: .systemYellow)
        case "green":    return Color(nsColor: .systemGreen)
        case "graphite", "gray", "grey": return Color(nsColor: .systemGray)
        default:         return Color(nsColor: .controlAccentColor)
        }
    }

    private static func globalString(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? String
    }
}

/// Keeps `IconAppearance` current. The system posts nothing documented when
/// the style changes, so it re-reads when the app comes forward and, while a
/// Settings window is open, every second and a half.
@MainActor
final class IconAppearanceMonitor: ObservableObject {
    static let shared = IconAppearanceMonitor()

    @Published private(set) var appearance = IconAppearance.current()

    private var timer: Timer?
    private var viewers = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
    }

    /// Call when a window showing icon tiles appears; pair with `stopWatching`.
    func startWatching() {
        viewers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopWatching() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let latest = IconAppearance.current()
        if latest != appearance { appearance = latest }
    }
}

// ─────────────────────────────────────────────
// MARK: - Icon tile
// ─────────────────────────────────────────────

/// Icon drawn as a small rounded tile with a monochrome glyph, used for the
/// sidebar and every other Settings icon. It follows the Mac's icon & widget
/// style the way app icons do:
///   • Default — solid gray tile, light or dark with the window
///   • Dark    — the dark tile even in light mode
///   • Clear   — Liquid Glass tile with a white (dark) or black (light) glyph
///   • Tinted  — glass coloured with the tint and a white glyph (light), or a
///               near-black tile with the glyph in the tint (dark)
/// The tile keeps its own colours on a selected row, so the glyph never takes
/// the accent colour.
struct SidebarIconTile: View {
    let systemImage: String
    var size: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var icons = IconAppearanceMonitor.shared

    var body: some View {
        let appearance = icons.appearance
        let dark = appearance.forcedDark ?? (colorScheme == .dark)
        let shape = RoundedRectangle(cornerRadius: (size * 0.27).rounded(), style: .continuous)

        tile(appearance, dark: dark, shape: shape)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: (size * 0.5).rounded(), weight: .semibold))
                    .foregroundStyle(glyphColor(appearance, dark: dark)))
            .animation(.easeInOut(duration: 0.25), value: appearance)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ appearance: IconAppearance, dark: Bool, shape: RoundedRectangle) -> some View {
        switch appearance.style {
        case .regular:
            shape
                .fill(LinearGradient(
                    colors: dark ? [Color(white: 0.30), Color(white: 0.22)]
                                 : [Color(white: 1.0), Color(white: 0.93)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10),
                                            lineWidth: 0.5))
                .shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: 0.5, y: 0.5)
        case .clear:
            GlassSurface(shape: shape, tint: dark ? Color.black.opacity(0.25) : Color.white.opacity(0.35))
                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.18 : 0.45), lineWidth: 0.5))
        case .tinted where dark:
            shape
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(appearance.tint.opacity(0.30), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
        case .tinted:
            GlassSurface(shape: shape, tint: appearance.tint.opacity(0.85))
                .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
    }

    private func glyphColor(_ appearance: IconAppearance, dark: Bool) -> Color {
        switch appearance.style {
        case .regular: return dark ? .white : Color(white: 0.2)
        case .clear:   return dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72)
        case .tinted:  return dark ? appearance.tint : .white
        }
    }
}
