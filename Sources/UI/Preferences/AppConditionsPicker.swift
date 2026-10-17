import SwiftUI
import UniformTypeIdentifiers

struct AppConditionsPicker: View {
    @Binding var rule: GestureRule
    @EnvironmentObject var store: PreferencesStore
    @State private var showing = false
    @State private var search = ""
    private var selected: [String] { rule.effectiveAppFilters }
    private var options: [RunningAppOption] {
        var apps = Dictionary(uniqueKeysWithValues: store.runningApps().map { ($0.bundleID, $0) })
        for id in selected where apps[id] == nil {
            apps[id] = RunningAppOption(bundleID: id, name: store.appFilterLabel(for: id))
        }
        return apps.values.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        LabeledContent("Apps") {
            Button(selected.isEmpty ? "Any App" : selected.count == 1 ? store.appFilterLabel(for: selected[0]) : "\(selected.count) Apps") { showing = true }
                .popover(isPresented: $showing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Run in any selected app").font(.headline)
                        TextField("Search apps", text: $search)
                        Button("Any App (Clear Selection)") { setApps([]) }
                        List(options) { app in
                            Toggle(app.name, isOn: Binding(
                                get: { selected.contains(app.bundleID) },
                                set: { on in setApps(on ? selected + [app.bundleID] : selected.filter { $0 != app.bundleID }) }
                            )).toggleStyle(.checkbox).help(app.bundleID)
                        }
                        HStack {
                            Button("Choose Apps…") { chooseApps() }
                            Spacer()
                            Button("Done") { showing = false }
                        }
                    }.padding().frame(width: 340, height: 370)
                }
        }
    }
    private func setApps(_ ids: [String]) {
        rule.appFilter = nil
        rule.appFilters = Array(Set(ids)).sorted()
    }
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add Apps"
        guard panel.runModal() == .OK else { return }
        setApps(selected + panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}
