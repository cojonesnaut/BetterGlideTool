import SwiftUI

// ─────────────────────────────────────────────
// MARK: - KeyboardTab
//
// Global keyboard-shortcut bindings, laid out exactly like GesturesTab: a
// searchable list on the left with glass selection, the same rule rows and
// footer, and the full editor on the right. The list holds `isKeyboardBinding`
// rules and the editor swaps the gesture trigger for a shortcut recorder.
// Registered via HotkeyManager (Carbon hotkeys).
// ─────────────────────────────────────────────

struct KeyboardTab: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var selectedRule: GestureRule.ID? = nil
    @State private var searchText = ""
    @State private var renameTarget: GestureRule.ID? = nil
    @State private var renameText = ""

    private var visibleRules: [GestureRule] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.keyboardRules }
        return store.keyboardRules.filter {
            $0.displayName.lowercased().contains(q)
            || $0.action.rawValue.lowercased().contains(q)
            || ($0.triggerShortcut?.displayString.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        HSplitView {
            // ── Left: shortcut list ──
            VStack(spacing: 0) {
                listHeader

                // No `selection:`, so the chosen shortcut sits on glass rather
                // than the system's accent-coloured row highlight.
                List {
                    if !visibleRules.isEmpty {
                        Section {
                            ForEach(visibleRules) { rule in
                                RuleRow(rule: rule)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .glassSelection(selectedRule == rule.id,
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedRule = rule.id }
                                    .accessibilityAddTraits(selectedRule == rule.id ? .isSelected : [])
                                    .contextMenu {
                                        Button("Rename…") { beginRename(rule) }
                                        Button("Duplicate") { duplicate(rule.id) }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            if selectedRule == rule.id { selectedRule = nil }
                                            store.removeRule(rule.id)
                                        }
                                    }
                            }
                        } header: {
                            Label("Keyboard Shortcuts", systemImage: "keyboard")
                                .font(.caption.bold())
                        }
                    }
                }
                .listStyle(.inset)
                // Over the list rather than below it, so it centers at the same
                // height as the editor's empty state.
                .overlay { if visibleRules.isEmpty { listEmptyState } }

                Divider()

                HStack {
                    Button {
                        searchText = ""
                        selectedRule = store.addHotkey()
                    } label: {
                        Label("Add Shortcut", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(8)

                    Spacer()

                    Text("\(store.keyboardRules.filter(\.isActive).count) active · \(store.keyboardRules.filter { !$0.isDraft }.count) total")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(8)
                }
            }
            .frame(minWidth: 320, maxWidth: 400)

            // ── Right: editor ──
            Group {
                if let id = selectedRule,
                   let idx = store.rules.firstIndex(where: { $0.id == id }) {
                    RuleEditor(rule: $store.rules[idx], onDelete: {
                        selectedRule = nil
                        store.removeRule(id)
                    }, onDuplicate: { duplicate(id) })
                    .id(id)
                } else {
                    editorEmptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Rename Shortcut", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renameTarget { store.renameRule(id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Give this shortcut a name you'll recognize. Leave empty to go back to the automatic name.")
        }
    }

    /// A copy with the same key combination would clash with the original, so
    /// the copy starts with no shortcut; record a new one in the editor.
    private func duplicate(_ id: GestureRule.ID) {
        guard let newID = store.duplicateRule(id),
              let index = store.rules.firstIndex(where: { $0.id == newID }) else { return }
        store.rules[index].triggerShortcut = nil
        selectedRule = newID
    }

    private func beginRename(_ rule: GestureRule) {
        renameText = rule.name ?? ""
        renameTarget = rule.id
    }

    // MARK: List chrome

    private var listHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search shortcuts", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        .padding(10)
    }

    private var listEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "keyboard" : "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No shortcuts yet" : "No matches")
                .font(.headline)
            Text(searchText.isEmpty
                 ? "Click Add Shortcut to run an action from anywhere."
                 : "Try a different search.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Shortcut Selected")
                .font(.title2)
            Text("Select a shortcut from the list or click + to add one.")
                .foregroundStyle(.secondary)
        }
    }
}
