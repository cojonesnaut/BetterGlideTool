import SwiftUI

struct InputMonitoringTab: View {
    let device: GestureDevice
    @ObservedObject private var trackpadInput = LowFingerTrackpadInput.shared
    @ObservedObject private var mouseInput = MagicMouseInput.shared
    @ObservedObject private var desktopActions = DesktopActions.shared

    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LiveContactsView(device: device)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                DisclosureGroup("Input Diagnostics", isExpanded: $showDiagnostics) {
                    TuningSection(title: "\(device.monitoringTitle) Input", icon: device == .trackpad ? "hand.draw" : "magicmouse") {
                        VStack(alignment: .leading, spacing: 10) {
                            if device == .trackpad {
                                LabeledContent("Touch input", value: trackpadInput.inputStatus)
                                LabeledContent("Active bindings", value: trackpadInput.contextStatus)
                                LabeledContent("Last TipTap result", value: trackpadInput.tipTapStatus)
                                LabeledContent("Last gesture", value: trackpadInput.lastGesture)
                                LabeledContent("Action", value: trackpadInput.actionStatus)
                            } else {
                                LabeledContent("Connection", value: mouseInput.status)
                                LabeledContent("Touch input", value: mouseInput.inputStatus)
                                LabeledContent("Last TipTap result", value: mouseInput.tipTapStatus)
                                LabeledContent("Last gesture", value: mouseInput.lastGesture)
                                if desktopActions.stageStatus != "Not tested yet." {
                                    LabeledContent("Last Stage Manager action", value: desktopActions.stageStatus)
                                }
                            }
                            Text("Try the gesture in its assigned app, then return here to see the last result. Use the floating panel to watch contacts while that app stays focused.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Copy Input Diagnostics") {
                                let lines = device == .trackpad ?
                                    [trackpadInput.inputStatus, trackpadInput.contextStatus, trackpadInput.tipTapStatus, trackpadInput.lastGesture, trackpadInput.actionStatus] :
                                    [mouseInput.status, mouseInput.inputStatus, mouseInput.tipTapStatus, mouseInput.lastGesture, desktopActions.stageStatus]
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(([device.monitoringTitle] + lines).joined(separator: "\n"), forType: .string)
                            }
                        }.padding(12).textSelection(.enabled)
                    }
                }.padding(.horizontal, 4)
            }.padding()
        }
    }
}
