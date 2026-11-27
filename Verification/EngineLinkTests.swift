import Foundation

/// The message link between the menu bar app and the Settings process
/// (EngineLink). Runs both ends in this process on test-only port names.
@MainActor
func verifyEngineLink() {
    func spin(until done: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }
    let name = "com.betterglidetool.verification.link.\(getpid())"
    let messages: [LinkMessage] = [
        .show(tab: PrefsTab.about.launchArgument, device: PreferencesDevice.magicMouse.launchArgument, checkForUpdates: true),
        .show(tab: nil, device: nil, checkForUpdates: false),
        .showOnboarding,
        .relaunchAfterUpdate(appPath: "/Applications/BetterGlide Tool ü.app"),
    ]

    // Every message survives encoding exactly.
    for message in messages {
        let data = try! PropertyListEncoder().encode(message)
        precondition(EngineLink.decode(data) == message, "\(message) round-trips")
    }
    precondition(EngineLink.decode(Data("not a message".utf8)) == nil, "garbage decodes to nothing")

    // Nobody listening: the send reports failure, so callers can fall back.
    precondition(!EngineLink.send(.showOnboarding, to: name, timeout: 0.2), "send to a missing listener fails")

    // Delivered in order on the main run loop.
    var received: [LinkMessage] = []
    precondition(EngineLink.listen(on: name) { received.append($0) }, "listener starts")
    precondition(!EngineLink.listen(on: name) { _ in }, "a name can't be taken twice")
    // The receiver here is this same thread, so let each message arrive
    // before the next; across processes the other main thread drains them.
    for (index, message) in messages.enumerated() {
        precondition(EngineLink.send(message, to: name), "\(message) is delivered")
        spin { received.count == index + 1 }
    }
    precondition(received == messages, "messages arrive intact and in order (got \(received))")

    // Launch arguments name every page and device, and read back.
    for tab in PrefsTab.allCases {
        precondition(!tab.launchArgument.contains(" ") && PrefsTab.fromLaunchArgument(tab.launchArgument) == tab)
    }
    for device in PreferencesDevice.allCases {
        precondition(PreferencesDevice.fromLaunchArgument(device.launchArgument) == device)
    }

    // After stopping, the name is free again and sends fail.
    EngineLink.stopListening(on: name)
    precondition(!EngineLink.send(.showOnboarding, to: name, timeout: 0.2), "stopped listener receives nothing")
    precondition(EngineLink.listen(on: name) { _ in }, "the name can be reused")
    EngineLink.stopListening(on: name)

    print("PASS: engine link: every message round-trips and arrives in order, missing listeners are reported, names are exclusive and reusable, page and device launch arguments read back")
}
