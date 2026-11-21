import Foundation

/// Looks up text that is built at runtime — action and gesture names, enum
/// display names, status messages — in the app's Localizable.strings. Literal
/// SwiftUI text is localized by SwiftUI itself; this covers the rest. Falls
/// back to the English key, so a missing translation shows English, never a key.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// `L` with `String(format:)` arguments, for keys like "%lld Finger %@".
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

/// The app's own language choice, independent of the Mac's. macOS reads the
/// `AppleLanguages` default at launch, so a change applies after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", turkish = "tr"
    var id: String { rawValue }

    static var current: AppLanguage {
        guard let chosen = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = chosen.first else { return .system }
        return first.hasPrefix("tr") ? .turkish : (first.hasPrefix("en") ? .english : .system)
    }

    static func choose(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}
