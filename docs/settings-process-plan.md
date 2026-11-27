# Plan: run Settings in its own process

## Why

Measured on 3.2.1 (macOS 27.2, Apple Silicon), with `footprint`:

| State | Main app footprint |
|---|---|
| Settings never opened | 17 MB |
| Settings open, a few tabs visited | 85–86 MB peak |
| After closing Settings | 82–84 MB, for the rest of the session |

Dropping the window's SwiftUI contents on close (already done in
`PreferencesWindowRoot`) frees only ~4 MB. The rest is framework state that
lives until the process exits: Swift type metadata, SF Symbol artwork,
Objective-C method caches, text and Unicode tables, AttributeGraph data, plus
~20 MB of fragmented malloc pages. The only way to give it back is to draw
Settings in a process that quits when the window closes.

**Goal:** the main app stays within a few MB of 17 MB after Settings has been
opened and closed, with every Settings feature working as today.

## Shape

- **One executable, two modes.** The menu bar app launches its own bundle a
  second time with `--settings --parent-pid=<pid>` through
  `NSWorkspace.openApplication(at:configuration:)` with
  `createsNewApplicationInstance = true`.
  - Same code signature, so Accessibility status reads the same in both.
  - Same preferences domain, so `@AppStorage` page choices carry over.
  - Activity Monitor shows two "BetterGlideTool" processes. A helper bundle
    could rename the second one, but it would get its own TCC identity and
    preferences domain, so this plan doesn't use one.
- **Entry point.** `@main struct GestureApp` becomes `@main enum AppEntry`,
  which calls `SettingsApp.main()` or `GestureApp.main()` depending on the flag.
- **Settings process.** A regular app with a Dock icon and its own menu bar. It
  opens the Preferences window at launch and quits when that window closes. It
  quits if the parent process exits (`DispatchSource.makeProcessSource(.exit)`).
  It never starts the engine, the menu bar extra, hotkeys, onboarding or the
  update timer.
- **Main process.** It never creates Settings UI. "Settings…" in the menu bar
  and ⌘, either launch the Settings process or, if one is already running, ask
  it to come forward on a given tab. The main app stays an accessory app and
  never switches its own activation policy.

## Shared state: `config.yaml`

Today every edit goes `PreferencesStore` → `Settings.shared` →
`GlideConfigStore.scheduleSave()`, a full-file write 0.4 s later. Two processes
doing that can overwrite each other.

**Rule: one writer at a time.**
- While the Settings process runs, it is the only writer.
- The main app's own edits are forwarded to it as messages: the menu bar's
  Edge Controls switch, and `EdgeControlsController.saveSettings`. The Settings
  process applies them through `PreferencesStore`, so the UI shows them too.
- When no Settings process runs, the main app writes as today.

**Reload in the main app.**
- The main app watches `config.yaml` with a `DispatchSource` file-system watch
  that survives atomic replacement by re-opening on rename or delete.
- On a change it calls `GlideConfigStore.load()`, then replays the side effects
  the in-process edit paths trigger today. Stage 2 starts by listing them; the
  ones known so far:
  - the Edge Controls engine configuration and the `TouchTracker` cache
  - the multitouch minimum contact count
  - hotkey registration
  - native pointer speed
  - native gesture reconciliation
  - debug logging
  - launch at login

  A reload must never schedule a save.

**Saving before Settings quits.** The Settings process flushes its pending save
before it terminates, from `applicationWillTerminate` and on window close.

**Import and export.** These work as today in the Settings process, and the
main app picks up an import through the file watch.

## Live link: main ↔ Settings

A small `EngineLink` over a pair of named local mach ports (`CFMessagePort`).
The app isn't sandboxed, so no XPC service or launchd job is needed.
- Port names: `com.betterglidetool.app.engine` in the main app,
  `com.betterglidetool.app.settings.<pid>` in the Settings process.
- Messages are small `Codable` enums encoded as binary plists.
- Streams are subscription-based: the main app sends a stream only while a
  Settings view asks for it, mirroring today's `setVisible(_:owner:)`.

| Settings needs | Direction | Today it reads |
|---|---|---|
| Gestures active / paused, and toggling it | both | `EngineBridge.isEnabled` |
| Accessibility granted, re-check | read locally | `AXIsProcessTrusted` |
| Live contacts: frame, transitions, gesture events, recording | main → Settings, ~30 Hz while visible | `LiveContactsMonitor` (per device) |
| Block actions while monitoring | Settings → main | `GestureActionBlock.isOn` |
| Trackpad input status lines | main → Settings | `LowFingerTrackpadInput` |
| Magic Mouse status and connected count | main → Settings | `MagicMouseInput` |
| Edge Controls live levels, active edge, surface size | main → Settings, while the page is visible | `EdgeControlsController` |
| Stage Manager test status | main → Settings | `DesktopActions.stageStatus` |
| Show tab X / come forward | main → Settings | `PreferencesNavigator` |
| Forwarded config edits (menu bar) | main → Settings | `PreferencesStore` |
| Install update: quit main, replace, relaunch | Settings → main | `UpdateInstaller` |
| Show onboarding again | Settings → main | `OnboardingController` |

These can run locally in the Settings process: haptic previews
(`HapticEngine`), the Shortcuts list (`ShortcutLibrary`), the native gesture
toggles (`SystemGestureManager`), launch-at-login registration, update
*checking*, and reading native pointer speed.

The main app keeps its Carbon hotkeys while you record a shortcut in Settings,
exactly as now. The recorder doesn't pause them today either.

## Stages

Each stage ends with a build, `bash Verification/run.sh` and a check of the
affected Settings pages. Work happens on a branch, and nothing ships until
stage 6.

1. **Two modes.** Add `AppEntry`, `SettingsApp`, launching and focusing the
   Settings process, parent-exit watch and quit-on-close. Settings works for
   anything that only edits config. Live views temporarily show "not
   connected".
2. **Config sync.** Add the main app's file watch and reload with side-effect
   replay, the single-writer rule, and flush on Settings quit. New
   verification: edits from either side survive, nothing is clobbered, a
   reload doesn't write, and an atomic replace is seen.
3. **EngineLink core.** Ports, message encoding, connect and reconnect (either
   side may restart), the on/off switch, forwarded menu edits, show-tab,
   onboarding and update install. New verification: message round-trips and
   behaviour when one side is missing.
4. **Live streams.** Contacts (both devices), gesture events, block-actions
   switch, input status lines, Edge Controls levels and Stage Manager status.
   Check that streams stop when the page or window goes away.
5. **Cut over.** Remove the `Window("…Preferences")` scene from `GestureApp`.
   The main app no longer links Settings UI at runtime.
   `PreferencesLayoutTests` keeps hosting `PreferencesWindow` in-process with
   a scratch config, as it does now.
6. **Verify and measure.**
   - The main app's footprint at idle, with Settings open, and after closing,
     with a target of ≤ ~20 MB after closing.
   - The Settings process starting time, with a target of under ~0.5 s to a
     drawn window.
   - Every Settings page by hand, Live Contacts on the trackpad and Magic
     Mouse, an update install, and Settings → quit main → Settings quits.

## Risks

- **Config clobbering** if a write path is missed: the single-writer rule plus
  the stage 2 tests guard it. Back up `config.yaml` before every manual test.
- **Live views lagging** behind the engine because of IPC. Contacts are small;
  if 30 Hz isn't smooth, coalesce or raise the rate only while the panel is
  visible.
- **Opening Settings takes a fresh process launch,** typically a few hundred ms
  on Apple Silicon, versus showing an existing window today.
- **Engine-only singletons accessed by accident** in the Settings process: guard
  `EngineBridge.startEngine()` and the multitouch bridges so they refuse to
  start in Settings mode.
- **Updates:** the installer must quit both processes before replacing the
  bundle.
