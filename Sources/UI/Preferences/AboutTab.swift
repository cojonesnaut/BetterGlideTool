import SwiftUI
import AppKit

/// About BetterGlideTool: the app, software updates, usage stats and links.
struct AboutTab: View {
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var updater = UpdateChecker.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var repository: URL {
        UpdateChecker.repositoryURL ?? URL(string: "https://github.com/cojonesnaut/BetterGlideTool")!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                updatesCard
                CardSection(title: "Stats", icon: "chart.bar") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(
                            value: "\(store.rules.count)",
                            label: "Total Gestures",
                            icon: "hand.draw",
                            color: .blue
                        )
                        StatCard(
                            value: "\(store.rules.filter(\.isActive).count)",
                            label: "Active Gestures",
                            icon: "bolt",
                            color: .green
                        )
                        StatCard(
                            value: "\(store.diagnostics.configuredFingerCounts)",
                            label: "Finger Sets Used",
                            icon: "hand.raised",
                            color: .purple
                        )
                        StatCard(
                            value: "\(store.diagnostics.openAppRulesMissingTarget)",
                            label: "Missing Apps",
                            icon: "exclamationmark.triangle",
                            color: .orange
                        )
                        StatCard(
                            value: "\(store.rules.filter { $0.reciprocalEnabled && $0.direction.hasSpeed }.count)",
                            label: "Reciprocal Pairs",
                            icon: "arrow.left.and.right",
                            color: .teal
                        )
                        StatCard(
                            value: "\(store.rules.filter { $0.modifierFilter != .any }.count)",
                            label: "Modifier Gestures",
                            icon: "command",
                            color: .indigo
                        )
                    }
                    .padding(12)
                }
                links
                Text("Released under the MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .onAppear { updater.checkIfDue() }
    }

    // MARK: - Hero

    private var hero: some View {
        GroupBox(label: Label("About", systemImage: "info.circle")) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("BetterGlideTool").font(.title3.weight(.semibold))
                        Text(L("Version %@", appVersion))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .materialPill()
                    }
                    Text("Trackpad and Magic Mouse gestures for macOS. Free and open source. Everything stays on your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    // MARK: - Updates

    private var updatesCard: some View {
        GroupBox(label: Label("Software Update", systemImage: "arrow.down.circle")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    SidebarIconTile(systemImage: "arrow.down.circle.fill", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for Updates")
                        updateSubtitle
                    }
                    Spacer(minLength: 12)
                    updateActions
                }
                if case .downloading(let fraction) = updater.state {
                    // Indeterminate when GitHub didn't send a content length.
                    if let fraction {
                        ProgressView(value: fraction).progressViewStyle(.linear)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }

    /// The update state, or when the last check ran while there's nothing to report.
    @ViewBuilder
    private var updateSubtitle: some View {
        switch updater.state {
        case .idle:
            Text(lastCheckedText)
                .font(.callout)
                .foregroundStyle(.secondary)
        default:
            updateStatus
        }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastCheck else { return L("Not checked yet") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return L("Last checked %@", formatter.localizedString(for: date, relativeTo: Date()))
    }

    @ViewBuilder
    private var updateActions: some View {
        switch updater.state {
        case .available(let update):
            HStack(spacing: 8) {
                Button("Release Notes") { NSWorkspace.shared.open(update.pageURL) }
                Button(update.canSelfInstall ? "Download & Install" : "Download") {
                    updater.downloadAndInstall(update)
                }
                .buttonStyle(.borderedProminent)
            }

        case .installed:
            Button("Relaunch Now") { updater.relaunch() }
                .buttonStyle(.borderedProminent)

        case .manualInstall(let dmg, _):
            Button("Open Installer") { updater.revealDownload(dmg) }
                .buttonStyle(.borderedProminent)

        case .downloading, .installing:
            EmptyView()

        case .idle, .checking, .upToDate, .failed:
            Button("Check Now") { updater.check() }
                .disabled(updater.state.isBusy)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.state {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.callout).foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("You're on the latest version", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)

        case .available(let update):
            Label("Update available — \(update.tag)", systemImage: "arrow.down.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.blue)
                .materialPill()
                .shimmer()

        case .downloading(let fraction):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(fraction.map { "Downloading… \(Int($0 * 100))%" } ?? "Downloading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.callout).foregroundStyle(.secondary)
            }

        case .installed(let version):
            Label("Updated to v\(version) — relaunch to finish", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

        case .manualInstall(_, let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Links

    private var links: some View {
        CardSection(title: "Links", icon: "link") {
            AboutLinkRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub",
                         detail: repository.host.map { "\($0)\(repository.path)" } ?? repository.absoluteString) {
                NSWorkspace.shared.open(repository)
            }
            Divider().padding(.leading, 46)
            AboutLinkRow(icon: "doc.text", title: "Release Notes", detail: L("What's new in each version")) {
                NSWorkspace.shared.open(repository.appendingPathComponent("releases"))
            }
            Divider().padding(.leading, 46)
            AboutLinkRow(icon: "ladybug", title: "Report an Issue", detail: L("Bugs and feature requests")) {
                NSWorkspace.shared.open(repository.appendingPathComponent("issues"))
            }
            Divider().padding(.leading, 46)
            AboutLinkRow(icon: "sparkles", title: "Welcome Tour", detail: L("Show the introduction again"),
                         opensExternally: false) {
                // The tour belongs to the menu bar app; show it there.
                if !AppMode.tellMenuBarApp(.showOnboarding) { OnboardingController.shared.show() }
            }
        }
    }
}

/// One line of the Links card: icon, name, a short detail and an arrow.
private struct AboutLinkRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: String
    var opensExternally = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 12)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: opensExternally ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
