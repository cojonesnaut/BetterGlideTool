import Combine
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @State private var language = AppLanguage.current
    @State private var languageChanged = false
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Behavior section
                GroupBox(label: Label("Behavior", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsRow(label: "Window Targeting") {
                            Picker("", selection: Binding(get: { store.windowTargetingMode == .focusedThenCursor }, set: { b in store.updateWindowTargetingMode(b ? .focusedThenCursor : .cursorThenFocused) })) {
                                Text("Focused Window First").tag(true)
                                Text("Window Under Cursor First").tag(false)
                            }
                            .frame(maxWidth: 260)
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Debug Logging") {
                            Toggle("Write gesture details to Console", isOn: Binding(get: { store.debugLoggingEnabled }, set: store.updateDebugLogging))
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Launch at Login") {
                            Toggle("Start BetterGlideTool automatically when you log in", isOn: Binding(get: { store.launchAtLoginEnabled }, set: store.updateLaunchAtLogin))
                        }
                        Divider().padding(.leading, 12)

                        SettingsRow(label: "Language") {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("", selection: Binding(get: { language }, set: { value in
                                    AppLanguage.choose(value); language = value; languageChanged = true
                                })) {
                                    Text("System Language").tag(AppLanguage.system)
                                    // Each language is named in itself, so it can always be found.
                                    Text(verbatim: "English").tag(AppLanguage.english)
                                    Text(verbatim: "Türkçe").tag(AppLanguage.turkish)
                                }
                                .frame(maxWidth: 260)
                                if languageChanged {
                                    HStack(spacing: 8) {
                                        Text("Relaunch BetterGlideTool to use the new language.")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Button("Relaunch Now") { UpdateInstaller.relaunch(Bundle.main.bundleURL) }
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                }

                // Haptics
                hapticsCard

                // Native gesture conflicts
                nativeGesturesCard
            }
            .padding()
        }
        .onAppear { store.reload() }
    }

    // MARK: - Haptics

    private var hapticsCard: some View {
        GroupBox(label: Label("Haptics", systemImage: "waveform")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Haptic Feedback") {
                    Toggle("Vibrate trackpad on gesture recognition", isOn: Binding(get: { store.hapticFeedbackEnabled }, set: store.updateHapticFeedback))
                }

                ForEach(HapticEvent.allCases, id: \.self) { event in
                    Divider().padding(.leading, 12)
                    SettingsRow(label: LocalizedStringKey(event.displayName)) {
                        Picker("", selection: Binding(
                            get: { store.hapticAssignments[event] ?? event.defaultPattern },
                            set: { store.updateHapticPattern($0, for: event) })) {
                            ForEach(HapticPattern.allCases, id: \.self) { pattern in
                                Text(pattern.displayName).tag(pattern)
                            }
                        }
                        .frame(maxWidth: 200)
                        .disabled(!store.hapticFeedbackEnabled)
                    }
                }

                Divider().padding(.leading, 12)
                HStack {
                    Text("Selecting a pattern plays it on the trackpad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") { store.resetHapticAssignments() }
                        .disabled(!store.hapticFeedbackEnabled)
                }
                .padding(12)
            }
        }
    }

    // MARK: - Native Gesture Conflicts

    private var nativeGesturesCard: some View {
        GroupBox(label: Label("macOS Gesture Conflicts", systemImage: "exclamationmark.arrow.triangle.2.circlepath")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: "Auto-Disable") {
                    Toggle("Turn off macOS gestures that collide with BetterGlideTool gestures",
                           isOn: Binding(get: { store.autoDisableNativeGestures },
                                         set: store.updateAutoDisableNativeGestures))
                }

                if store.nativeConflicts.isEmpty {
                    Divider().padding(.leading, 12)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No conflicts — no active macOS gesture shares a trigger with your BetterGlideTool gestures.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else {
                    ForEach(store.nativeConflicts) { conflict in
                        Divider().padding(.leading, 12)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(conflict.native.title))
                                    .font(.callout.weight(.medium))
                                Text("Collides with: \(conflict.glideTriggers.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if !conflict.native.appliesWithoutLogout {
                                    Text("May need a log out & back in to fully take effect.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button("Disable") { store.disableNativeConflict(conflict) }
                                .help("Turns the native macOS gesture off (restarts the Dock)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    if store.nativeConflicts.count > 1 {
                        Divider().padding(.leading, 12)
                        HStack {
                            Spacer()
                            Button("Disable All Native Conflicts") { store.disableAllNativeConflicts() }
                        }
                        .padding(12)
                    }
                }

                // ── Re-enable anything BetterGlideTool turned off ──
                if !store.disabledNativeGestures.isEmpty {
                    Divider().padding(.leading, 12)
                    HStack {
                        Text("Disabled by BetterGlideTool")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.disabledNativeGestures.count > 1 {
                            Button("Re-enable All") { store.reEnableAllNativeGestures() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ForEach(store.disabledNativeGestures) { gesture in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slash.circle")
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(L(gesture.title))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Re-enable") { store.reEnableNativeGesture(gesture) }
                                .help("Restores the native macOS gesture to how it was before BetterGlideTool disabled it")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

}

// MARK: - Settings Row

struct SettingsRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            content()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: LocalizedStringKey
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            SidebarIconTile(systemImage: icon, size: 30)

            Text(value)
                .font(.title.bold())
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
