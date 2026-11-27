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

**As built (stage 2): both save, both reload.** Instead of one writer and
forwarded edits, each process keeps saving its own edits as before and
watches the file (`ConfigSync`, `ConfigFileWatcher`, which watches the folder so
atomic saves are seen). When the other process saves,
`GlideConfigStore.reloadIfChangedExternally()` applies the new contents and
calls `PreferencesStore.reload()`, which already replays every engine side
effect of an in-process edit: rules and hotkeys, Magic Mouse and low-finger
input, Edge Controls, native gesture conflicts and pointer speed. It also
refreshes the TipTap edge-margin cache.
- A reload never writes. Saves are suppressed while it runs, and identical
  serialization means the other process sees nothing new.
- An unsaved local edit is never discarded. While a save is pending the
  reload waits; the local save lands 0.4 s later and the other process reloads
  it. The only loss is when both processes edit within the same 0.4 s, where
  the later save wins.
- The menu bar's Edge Controls switch needs no forwarding: its save reaches
  Settings like any other.

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

1. **Two modes.** *(Done.)* Add `AppEntry`, `SettingsApp`, launching and focusing the
   Settings process, parent-exit watch and quit-on-close. Settings works for
   anything that only edits config. Live views temporarily show "not
   connected".
2. **Config sync.** *(Done.)* Both processes watch the file and reload the
   other's saves with side-effect replay; Settings flushes on quit.
   `Verification/ConfigSyncTests.swift` checks: own saves ignored, external
   saves applied once without writing back, unsaved local edits kept, broken
   files ignored, atomic saves seen.
3. **EngineLink core.** *(Done.)* `EngineLink` sends one-way `Codable`
   messages over `CFMessagePort`s named with each process's pid. Built:
   "show this page" (and "check for updates") from the menu bar to an open
   Settings window; the welcome tour and the post-update relaunch from
   Settings to the menu bar app, falling back to running them locally if the
   menu bar app can't be reached. "Install Update…" in the menu installs in the
   menu bar app without opening Settings. The engine on/off switch lives only
   in the menu bar now, so it needs no message. Settings launches with window
   restoration off, after a live test showed a closed window being restored
   as a 135×149 sliver. `Verification/EngineLinkTests.swift` covers encoding,
   ordered delivery, missing listeners and exclusive names.
4. **Live streams.** *(Done.)* `LiveStream.swift`: Settings sends one
   subscription naming what's on screen (trackpad contacts, Magic Mouse
   contacts, status); the menu bar app turns those monitors on under its own
   owner name and streams only changes, at most 30 times a second, with the
   gesture log only when it changes. Recording, export, Copy Readings,
   Reconnect and the floating panel run in the menu bar app. Edge Controls
   volume and brightness are read by Settings itself; the active edge is
   streamed. The subscription ends when Settings unsubscribes, exits, or its
   port disappears, so Block Real Gesture Triggering can't outlive it; a busy
   Settings just gets the update on the next tick.
   `Verification/LiveStreamTests.swift` covers all of that.
5. **Cut over.** *(Done.)* The `Window("…Preferences")` scene is gone from
   `GestureApp`, along with the in-process teardown (`PreferencesWindowRoot`,
   `MemoryRelief`) that only existed to shrink it. Settings… and ⌘, open the
   Settings process; if that launch fails, an alert says so. The Permissions
   page now keys "may start System Events" on `AppMode.isSettings`.
   `PreferencesLayoutTests` still hosts `PreferencesWindow` in-process.
6. **Verify and measure.** *(Done, with two open items.)* Measured on
   2026-11-27, macOS 27.2, Apple Silicon:

   | Menu bar app | 3.3.0 (in-process Settings) | Settings process |
   |---|---|---|
   | Idle, Settings never opened | 17 MB | 19 MB |
   | After opening and closing Settings | 84 MB | 37 MB |

   - Settings itself uses about 51 MB while open and all of it goes when it
     quits.
   - Opening Settings takes 0.72–0.83 s from the request to a visible window
     (five runs), over the 0.5 s target.
   - Every page was clicked through by hand on the installed build; live
     contacts, the gesture log, blocking, recording and export, the floating
     panel and the edge and corner highlights all work.

   Open: the menu bar app keeps ~18 MB after Input Monitoring has streamed
   (recording and gesture log held for export, possibly the floating panel),
   and launch time could be trimmed.

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
