import Foundation

@main
struct TrackpadRepeatTests {
    static var failures: [String] = []
    static func expect(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
    static func main() throws {
        struct Contact: Decodable { let id: Int32; let x, y, size: Double
            var point: MouseContact { .init(id: id, x: x, y: y, size: size) }
        }
        struct Frame: Decodable { let time: Double; let contacts: [Contact]; let sampledButtonDown: Bool }
        struct Fixture: Decodable { let frames: [Frame] }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var settings = MagicMouseSettings()
        settings.tipTapMinimumDuration = 0.07; settings.tipTapAnchorDuration = 0.2
        settings.tapMovement /= pow(2, (0.353453196347032 - 0.5) * 2)
        settings.tipTap.twoFingerSensitivity = 0.25
        settings.tipTap.twoFingerMinimumDistance = 0.02; settings.tipTap.threeFingerMinimumDistance = 0.02
        settings.tipTap.maximumDistance = 0.8; settings.tipTap.allowSensitiveTipTaps = false
        settings.bindings = [.tipTapTwoLeft: .missionControl, .tipTapTwoRight: .missionControl]
        let rest = fixture.frames[0].contacts.map(\.point)
        let left = fixture.frames[1].contacts.first { $0.id == 2 }!.point
        let middle = rest.first { $0.id == 6 }!, right = rest.first { $0.id == 4 }!
        func primed(_ profile: MagicMouseSettings) -> MagicMouseRecognizer {
            var r = MagicMouseRecognizer()
            _ = r.consume(rest, timestamp: 9, settings: profile)
            _ = r.consume(rest + [left], timestamp: 9.3, settings: profile)
            _ = r.consume(rest, timestamp: 9.42, settings: profile)
            _ = r.trackpadButtonChanged(0, isDown: true, timestamp: 9.9)
            _ = r.trackpadButtonChanged(0, isDown: false, timestamp: 10)
            return r
        }
        // The capture starts mid-session. Prime the reported resting chord;
        // model native edges from feedback changes, not as recorded raw events.
        var r = primed(settings)
        var outputs: [(Double, MagicMouseGesture)] = []
        for f in fixture.frames {
            let time = 10 + f.time
            if [0.144, 0.784, 1.136].contains(f.time) { _ = r.trackpadButtonChanged(0, isDown: true, timestamp: time) }
            if [0.328, 0.848, 1.152].contains(f.time) { _ = r.trackpadButtonChanged(0, isDown: false, timestamp: time) }
            if let result = r.consume(f.contacts.map(\.point), timestamp: time, settings: settings,
                                      physicalButtonDown: f.sampledButtonDown, allowsTrackpadButtonRecovery: true) {
                outputs.append((f.time, result))
            }
        }
        print("Recorded-contact replay outputs:", outputs.map { "\($0.0):\($0.1.rawValue)" })
        expect(outputs.map(\.0) == [0.112, 0.752, 1.072, 1.368, 1.776, 2.0], "Valid captured releases must fire; interrupted and 40 ms bounce releases must not")
        expect(outputs.first?.1 == .tipTapTwoLeft && outputs.dropFirst().allSatisfy { $0.1 == .tipTapTwoRight }, "Captured release sides must match")

        for mirror in [false, true] {
            let chord = [left, middle, right].map { MouseContact(id: $0.id, x: mirror ? 1 - $0.x : $0.x, y: $0.y, size: $0.size) }
            let a = chord[0], b = chord[1], c = chord[2]
            for button in 0...2 {
                var r = MagicMouseRecognizer()
                _ = r.consume([b,c], timestamp: 20, settings: settings)
                _ = r.consume(chord, timestamp: 20.3, settings: settings)
                _ = r.consume([b,c], timestamp: 20.42, settings: settings)
                _ = r.trackpadButtonChanged(button, isDown: true, timestamp: 20.45)
                _ = r.consume(chord, timestamp: 20.5, settings: settings, physicalButtonDown: true, allowsTrackpadButtonRecovery: true)
                _ = r.trackpadButtonChanged(button, isDown: false, timestamp: 20.55)
                expect(r.consume([a,b], timestamp: 20.6, settings: settings, allowsTrackpadButtonRecovery: true) == nil, "Rotated pair rearms without emitting interrupted action")
                expect(!r.liveContactRoles.values.contains("Blocked"), "Rotated pair recovers after button-up, mirror \(mirror), button \(button)")
                _ = r.consume(chord, timestamp: 20.85, settings: settings, allowsTrackpadButtonRecovery: true)
                expect(r.consume([a,b], timestamp: 20.97, settings: settings, allowsTrackpadButtonRecovery: true) == (mirror ? .tipTapTwoLeft : .tipTapTwoRight), "Next fresh stroke fires after rotated-pair recovery")
            }
        }
        // Exchanging anchors must not revive a held click, hard cancellation,
        // Magic Mouse session, unassigned pair, or an unrelated/moved hand.
        for scenario in 0..<7 {
            var profile = settings
            if scenario == 2 { profile.tipTapSpacingGeometry = .magicMouse }
            if scenario == 3 { profile.bindings = [.tipTapTwoLeft: .missionControl] }
            var r = primed(profile)
            _ = r.trackpadButtonChanged(0, isDown: true, timestamp: 10.01)
            _ = r.consume([left,middle,right], timestamp: 10.02, settings: profile, physicalButtonDown: true, allowsTrackpadButtonRecovery: true)
            if scenario == 1 { r.cancel() }
            if scenario != 0 { _ = r.trackpadButtonChanged(0, isDown: false, timestamp: 10.03) }
            var replacement = [left,middle]
            if scenario == 4 { replacement = [MouseContact(id: 98, x: 0.1, y: 0.1), MouseContact(id: 99, x: 0.3, y: 0.1)] }
            if scenario == 5 { replacement[1] = MouseContact(id: middle.id, x: middle.x, y: middle.y - 0.3) }
            if scenario == 6 { replacement[0] = MouseContact(id: 99, x: middle.x + 0.1, y: middle.y) }
            expect(r.consume(replacement, timestamp: 10.04, settings: profile, physicalButtonDown: scenario == 0, allowsTrackpadButtonRecovery: true) == nil, "Recovery never emits an action")
            expect(r.liveContactRoles.values.contains("Blocked"), "Invalid recovery stays blocked: \(scenario)")
        }
        if !failures.isEmpty { failures.forEach { print("FAIL:", $0) }; exit(1) }
        print("PASS: captured trackpad repeat regression and rotated-pair button recovery guards")
    }
}
