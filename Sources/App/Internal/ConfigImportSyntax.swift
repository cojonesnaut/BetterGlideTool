import Foundation

/// Validate the block-style YAML used by exports before the compatibility parser
/// can replace missing/malformed fields with defaults. Unsupported syntax fails
/// as a whole; it must never turn a partial parse into a successful import.
enum ConfigImportSyntax {
    private enum Kind { case object, gestures, list, text, number, integer, boolean }
    private struct Frame {
        let indent: Int
        let path: String
        let kind: Kind
        var childIndent: Int?
    }
    private static let gestureLists: Set<String> = [
        "app_filters", "stage_apps", "menu_path", "shortcut_modifiers", "advanced_keyboard", "trigger_shortcut_modifiers",
        "continuous_update_negative_shortcut_modifiers", "continuous_update_positive_shortcut_modifiers", "continuous_end_shortcut_modifiers",
        "continuous_begin_keyboard", "continuous_update_negative_keyboard", "continuous_update_positive_keyboard", "continuous_end_keyboard"
    ]
    private static let gestureIntegers: Set<String> = [
        "fingers", "stage_position", "shortcut_key_code", "trigger_shortcut_key_code",
        "continuous_update_negative_shortcut_key_code", "continuous_update_positive_shortcut_key_code", "continuous_end_shortcut_key_code"
    ]
    private static let gestureBooleans: Set<String> = ["draft", "keyboard_binding", "reciprocal", "continuous", "allow_animated_fallback"]
    private static let gestureStrings: Set<String> = [
        "type", "name", "direction", "device", "speed", "action", "app_filter", "window_state", "modifier_filter", "zone", "app_path",
        "stage_window_title", "shortcut_name", "script", "haptic", "reciprocal_action",
        "continuous_update_negative_action", "continuous_update_positive_action", "continuous_end_action"
    ]
    // Derive settings keys/types from the exporter so every newly exported tuning
    // field is automatically accepted. Gesture optional payloads are listed above.
    private static let schema: [String: Kind] = {
        var result: [String: Kind] = [:]
        var parents: [(Int, String)] = []
        for raw in GlideConfigSerializer.serialize(GlideConfig()).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let indent = raw.prefix { $0 == " " }.count
            while let last = parents.last, last.0 >= indent { parents.removeLast() }
            let key = String(line[..<colon])
            let path = (parents.last.map { $0.1 + "." } ?? "") + key
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let kind: Kind = key == "gestures" ? .gestures : (value.isEmpty ? .object :
                (["true", "false"].contains(value) ? .boolean : (Double(value) != nil ? .number : .text)))
            result[path] = kind
            if value.isEmpty { parents.append((indent, path)) }
        }
        result["touchpad.gesture_schema_version"] = .integer
        // Retired sections. The App Switcher's settings page and the TrackPoint were
        // removed in 2.11.0; files exported before that still carry these blocks and
        // must keep importing. The parser skips them.
        let retired: [String: [String: Kind]] = [
            "app_switcher": [
                "enabled": .boolean, "style": .text, "fingers": .integer, "skip_windowless_finder": .boolean,
                "restore_minimized_on_commit": .boolean, "animations_enabled": .boolean
            ],
            "trackpoint": [
                "enabled": .boolean, "activation_mode": .text, "zone": .text, "zone_size": .number,
                "activation_delay": .number, "activation_movement": .number, "double_tap_window": .number,
                "dead_zone": .number, "push_range": .number, "max_speed": .number, "acceleration": .number,
                "haptic_feedback": .boolean, "scroll_enabled": .boolean, "scroll_speed": .number,
                "invert_scroll": .boolean, "smoothing": .number
            ]
        ]
        for (section, fields) in retired {
            result["touchpad.\(section)"] = .object
            for (key, kind) in fields { result["touchpad.\(section).\(key)"] = kind }
        }
        result["touchpad.tuning.candidate_frames"] = .integer
        result["touchpad.speed.speed_sample_count"] = .integer // retired legacy field
        result["touchpad.tuning.force_click_corner_margin"] = .number
        return result
    }()

    /// Only unquoted comments are removed; '#' in app names/scripts is data.
    static func withoutComment(_ text: String) -> String {
        var quote: Character?, escaped = false, previous: Character?
        for index in text.indices {
            let ch = text[index]
            if escaped { escaped = false; previous = ch; continue }
            if ch == "\\" && quote == "\"" { escaped = true }
            else if let current = quote { if ch == current { quote = nil } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "#" && (previous == nil || previous!.isWhitespace) { return String(text[..<index]) }
            previous = ch
        }
        return text
    }

    static func isValid(_ lines: [String]) -> Bool {
        var stack: [Frame] = []
        var seen = Set<String>()
        var record = 0
        var hasSettings = false
        for raw in lines {
            let body = raw.trimmingCharacters(in: .whitespaces)
            if body.isEmpty || body.hasPrefix("#") { continue }
            if body == "---" || body == "..." { return false }
            guard !raw.prefix(while: { $0.isWhitespace }).contains("\t") else { return false }
            let indent = raw.prefix { $0 == " " }.count
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
            if let last = stack.last {
                if let expected = last.childIndent, expected != indent { return false }
                stack[stack.count - 1].childIndent = indent
            }
            var text = body
            var parent = stack.last?.path ?? ""
            var fieldIndent = indent
            if body.hasPrefix("- ") {
                guard let frame = stack.last else { return false }
                text = String(body.dropFirst(2))
                if frame.kind == .list { guard validScalar(text, kind: .text) else { return false }; continue }
                guard frame.kind == .gestures else { return false }
                record += 1
                parent += ".@\(record)"
                // The first mapping field is two columns past the list dash.
                stack.append(Frame(indent: indent, path: parent, kind: .object))
                fieldIndent += 2
            } else if stack.last?.kind == .list || stack.last?.kind == .gestures { return false }
            guard let colon = text.firstIndex(of: ":") else { return false }
            let key = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let path = parent.isEmpty ? key : parent + "." + key
            guard seen.insert(path).inserted else { return false }
            let kind: Kind?
            if parent.hasPrefix("touchpad.gestures.@"), !parent.dropFirst("touchpad.gestures.@".count).contains(".") {
                kind = gestureLists.contains(key) ? .list : (gestureIntegers.contains(key) ? .integer :
                    (gestureBooleans.contains(key) ? .boolean : (gestureStrings.contains(key) ? .text : nil)))
            } else if parent == "touchpad.haptics" {
                kind = HapticEvent(rawValue: key) != nil ? .text : nil
            } else { kind = schema[path.replacingOccurrences(of: "touchpad.edgecontrols", with: "touchpad.edge_controls")] }
            guard let kind else { return false }
            if parent.isEmpty && (key != "touchpad" || indent != 0) { return false }
            if kind == .object || kind == .list || kind == .gestures {
                guard value.isEmpty || (kind == .object ? value == "{}" : value == "[]") else { return false }
                if value.isEmpty { stack.append(Frame(indent: fieldIndent, path: path, kind: kind)) }
            } else {
                guard validScalar(value, kind: kind) else { return false }
            }
            if parent == "touchpad" { hasSettings = true }
        }
        return hasSettings && seen.contains("touchpad")
    }
    private static func validScalar(_ value: String, kind: Kind) -> Bool {
        guard !value.isEmpty else { return false }
        switch kind {
        case .number: return Double(value)?.isFinite == true
        case .integer: return Int(value) != nil
        case .boolean: return ["true", "false", "yes", "no", "0", "1"].contains(value.lowercased())
        default:
            if let quote = value.first, quote == "\"" || quote == "'" {
                let characters = Array(value)
                guard characters.count >= 2 else { return false }
                var index = 1
                while index < characters.count {
                    let ch = characters[index]
                    if ch == "\\" && quote == "\"" {
                        index += 1
                        guard index < characters.count, ["\\", "\"", "n", "r", "t"].contains(characters[index]) else { return false }
                    } else if ch == quote {
                        if quote == "'", index + 1 < characters.count, characters[index + 1] == "'" { index += 1 }
                        else { return index == characters.count - 1 }
                    }
                    index += 1
                }
                return false
            }
            return !value.contains(": ") && !["[", "{", "|", ">", "&", "*", "!"].contains(String(value.prefix(1)))
        }
    }
}
