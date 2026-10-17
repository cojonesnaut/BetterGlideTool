# BetterGlideTool

A renamed fork of [Glide by Vatsal057](https://github.com/Vatsal057/Glide): a native macOS utility for trackpad and Magic Mouse gestures, window management, edge sliders, TrackPoint mode, and global shortcuts.

BetterGlideTool retains Glide's gesture engine and uses its own app name, bundle identifier (`com.betterglidetool.app`), configuration directory, and release artifacts. The original MIT license and copyright are preserved in [LICENSE](LICENSE). The upstream history, changelog, artwork, and internal implementation names are retained for attribution and easier upstream merges.

## Build

Requires macOS 13 or later and Xcode Command Line Tools.

Clone [cojonesnaut/BetterGlideTool](https://github.com/cojonesnaut/BetterGlideTool), then build:

```sh
git clone https://github.com/cojonesnaut/BetterGlideTool.git
cd BetterGlideTool
```

From this repository's directory:

```sh
./build.sh
open build/BetterGlideTool.app
```

For an optimized universal app (Apple Silicon and Intel):

```sh
./build.sh --release
```

To create `build/BetterGlideTool.dmg`:

```sh
./build.sh --dmg
```

Drag the app into Applications and grant **BetterGlideTool** Accessibility access when prompted. Screen Recording is optional for window thumbnails. Automation is used for configured AppleScript and menu actions. Run only one gesture utility at a time to avoid competing gesture handlers.

## Features and configuration

- Customizable multi-finger trackpad swipes, clicks, force-clicks, and holds.
- Magic Mouse regional taps and one- through four-finger swipes, with middle-click, window, app, and media actions.
- Window snapping, maximizing, restoring, and a spatial app switcher.
- Trackpad edge controls for volume, brightness, and scrolling.
- TrackPoint pointer mode and global keyboard shortcuts.
- Native preferences, configuration import/export, and launch at login.

Open the menu bar hand icon for preferences. See the [usage manual](USAGE.md) and [detailed guides](docs/).

Settings are stored at `~/Library/Application Support/BetterGlideTool/config.yaml`. Existing Glide settings are left untouched. Import an exported Glide YAML configuration through Preferences to copy settings deliberately.

## Fork releases and updates

Local builds do not contact Glide's release feed. Until a BetterGlideTool repository is configured, automatic update checks are disabled and a manual check explains that releases are not configured.

Build with the fork repository name to enable its own update feed:

```sh
BETTERGLIDETOOL_REPOSITORY=cojonesnaut/BetterGlideTool ./build.sh --dmg
```

The included GitHub Actions release workflow uses `GITHUB_REPOSITORY` automatically when a `v*` tag is pushed. It packages `BetterGlideTool-vX.Y.Z.dmg` with a SHA-256 checksum. A release must be published before update checks can find it. Signing and notarization depend on the build machine's credentials; local builds use ad-hoc signing when no certificate is available.

## Attribution

Original project: [Vatsal057/Glide](https://github.com/Vatsal057/Glide). Copyright (c) 2026 Vatsal057. Licensed under the [MIT License](LICENSE).

## Build toolchain note

The local Apple Silicon build was verified with the macOS 26.5 SDK. If the macOS 27 Command Line Tools SDK reports a missing `SwiftUIMacros` plugin, select an installed compatible SDK:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
```

## Magic Mouse

Open **Preferences → device dropdown → Magic Mouse**. Support is enabled by default when the main gesture engine is active and Accessibility permission is granted. A two-finger tap produces a middle click; a three-finger tap opens Mission Control. One-finger taps and two-finger swipes are opt-in, with separate action assignments and sensitivity controls.

The new input provider, recognizer, settings, and preferences are Swift. It reuses the existing action engine and shared multitouch ABI, adds no third-party libraries, and uses IOKit device notifications instead of a new polling timer. Recognition runs on incoming touch frames; only completed actions cross to the main queue. Mouse and trackpad state stay separate.

See [Magic Mouse setup and behavior](docs/13-magic-mouse.md). Force-click, haptics, TrackPoint, and trackpad edge sliders remain trackpad features.

## Verification

```sh
bash Verification/run.sh
```

The checks cover touch recognition, accidental-click rejection, device isolation, and configuration import/export. They compile and run without enabling gesture handling or requesting permissions. Set `SDKROOT` as described above if your installed Command Line Tools need the older SDK.

## Device-specific gestures

Choose **Trackpad** or **Magic Mouse** from the top-left preferences dropdown. Device controls are separate; keyboard shortcuts and app-wide settings are under Shared. Both devices use the same gesture list and editor, with separate rules. Single- and two-finger taps and directional swipes are available on both devices. Filter to **1** or **2**, choose **Add Gesture**, and assign an action. New bindings remain inactive until configured.

Low-finger trackpad actions are discrete and leave native pointing, scrolling, and tap-to-click intact. Use a modifier on custom swipes to distinguish them from ordinary movement. TrackPoint and active edge controls take priority. No new polling timer is used; the trackpad only enables low-contact recognition when a matching rule is active.

## Local version 2.6.0

Both device menus include **2 Finger Tap**, **2 Finger Double-Tap**, **TipTap Left (1 Finger Fix)**, **TipTap Right (1 Finger Fix)**, and **2 Finger Click**, using the original gesture naming. Under **Conditions → Apps**, select multiple apps to run the same gesture in any of them. **Choose Apps…** also adds apps that are not running. Existing single-app conditions and Magic Mouse assignments migrate automatically.

When double-tap is assigned, a single two-finger tap waits up to 300 ms to distinguish it. For TipTap, rest one finger for at least 250 ms by default, then tap and lift another finger to its left or right while keeping the first finger down. TipTap ignores taps shorter than 80 ms by default; adjust both times separately for each device under **Tuning → TipTap timing**. Two-finger physical clicks require macOS to identify the event's device; unidentified events retain native behavior.

### Accessibility permission after replacing the app

The app refreshes its permission status when preferences regain focus and offers **General → Recheck Permission**. It no longer automatically prompts on every launch. The General page shows the path of the running app, so an approved copy can be distinguished from another build.

Local builds are ad-hoc signed. Replacing one changes its code identity, and macOS can retain an enabled Accessibility entry for the old build. If **Recheck Permission** still reports no access, quit all copies, replace the app in Applications, remove the old BetterGlideTool entry from **System Settings → Privacy & Security → Accessibility**, add the installed copy again, and relaunch it. The app cannot grant itself access. A stable signing certificate is needed to avoid permission renewal caused by changing ad-hoc signatures.

## Local version 2.7.0: device tuning and app rules

Choose a device at the top left, then **Tuning**. Both devices have **Gesture sensitivity** (Easier to trigger → Harder to trigger) and **Pointer speed**, with a numeric multiplier and **Reset** to 1×. Each device stores independent values. Gesture sensitivity scales the existing swipe distance and low-finger tap tolerance; the midpoint preserves previous tuning. Trackpad advanced controls remain available below the new card.

Pointer speed adjusts native HID acceleration parameters only on identified Magic Mouse or trackpad services. It does not warp the cursor or replace the macOS acceleration curve; the displayed factor is a tuning control, not an exact physical speed multiplier. Original values are captured before adjustment and restored at 1×, when gestures pause, or on normal quit. Changes are applied when the engine is active. A status message reports unsupported services or rejected settings. Baselines are retained for recovery after an unexpected exit; disconnected devices are restored when they reappear while the app runs. No new repeating timer is added.

App-specific gestures now override matching **Any App** rules even when the general rule appears later. App filters also gate mouse scroll reservation and low-finger recognition, including double-tap arbitration. Switching apps discards a pending gesture so it cannot fire in the next app.

For a clean Magic Mouse test, quit BetterTouchTool and other gesture utilities, launch the new BetterGlideTool build, and open **Magic Mouse → Tuning**. **Touch input** should change from waiting to receiving frames, and **Last gesture** should update when recognition succeeds. Being connected alone does not confirm touch delivery. This release includes callback routing and stopped-device recovery fixes; a successful physical gesture test with this build is still needed.

### Spaces and Stage Manager actions

The action picker includes **Spaces** and **Stage Manager** groups with animation-free left/right Space switching, moving a window one desktop left/right, stage activation by position or target apps/window title, forward/backward cycling, a stage context menu, and Stage Manager/Recent Apps toggles. These actions are available to both input devices.

Stage position follows the visible Recent Apps strip from top to bottom. Target matching requires all selected app names and any window-title text to appear in the stage's accessible label; hidden stages or labels that macOS does not expose cannot be matched. Enable Stage Manager and Recent Apps first.

Space/window operations depend on private macOS APIs and can be rejected by macOS. Animation-free switching has an explicit **Allow native animated fallback** option, off by default, using the configured Mission Control shortcut. Full-screen Spaces are not valid destinations for moving a window. Automated checks validate configuration and selection logic; live desktop actions still need a hands-on compatibility check.

### Three-finger gestures and scroll direction

Both devices support **3 Finger Tap**, **3 Finger Double-Tap**, **3 Finger Click**, **3 Finger Swipe Up/Down/Left/Right**, **TipTap Left/Middle/Right (2 Fingers Fix)**, and **TipSwipe Left Finger Up/Down (2 Fingers Fix)**. Trackpad's existing force-click and continuous gestures remain available. App Switcher reserves plain three-finger horizontal trackpad swipes while enabled; disable it or choose a modifier for custom horizontal bindings.

For two-fixed-finger gestures, rest two fingers for the device's configured TipTap rest time, then tap a third finger to the left, between them, or to the right. For TipSwipe, move the left finger vertically while the other two stay still. Lift all fingers before repeating. Brief touches, moving/lifting an anchor, and physical clicks cancel the gesture.

Under **Magic Mouse → Tuning → Scrolling**, invert the vertical and horizontal axes separately relative to macOS's current direction. Both switches default off and affect only events identified as Magic Mouse. Native phases and momentum remain intact; unknown senders and trackpads pass through unchanged. The switches work even without any gesture bindings, while Magic Mouse input is enabled.

Smooth scrolling and its speed/response controls are intentionally omitted: [Vorssaint's smoothing service](https://github.com/vorssaintapp/vorssaint-utils/blob/main/Sources/Vorssaint/Services/SmoothScrollService.swift) explicitly bypasses Magic Mouse and trackpad input. This implementation adds no third-party source, dependency, or repeating timer. Physical gestures still require hands-on validation on the connected devices.

## Magic Mouse one- and four-finger additions (2.10)

The one-finger menu includes **1 Finger Tap**, **1 Finger Tap Left**, **1 Finger Tap Right**, **1 Finger Middle Click**, **1 Finger Tap Middle**, and **1 Finger Tap Above Apple**. Middle Click means a physical press with one finger in the central strip; Tap Middle only requires touch and lift. Each gesture has its own action assignment.

The four-finger menu offers **4 Finger Click** and **4 Finger Swipe Up/Down/Left/Right**. All new gestures are opt-in. See the [Magic Mouse guide](docs/13-magic-mouse.md) for tap regions and overlap handling. Automated checks cover the new recognizers and rule routing; physical hardware validation remains necessary.

## Trackpad additions and TipTap controls (2.10)

Trackpad now also offers one-finger clockwise/counter-clockwise circles, the four corner clicks, **3 Finger Tap Top/Bottom**, horizontal **TipSwipe Left Finger Left/Right (2 Fingers Fix)**, **4 Finger Tap**, **4 Finger Double Tap**, and **TipTap Left/Right (3 Fingers Fix)**. Existing four-finger click, force-click and swipes remain available. Circles execute on lift; if a one-finger swipe is also assigned, the completed path chooses one action.

Each device’s **Tuning → TipTaps** has separate contact-size sensitivity controls. Trackpad adds finger-movement and spacing controls; Magic Mouse adds **Allow sensitive TipTaps**, initially off to reduce accidental touches. Timing controls above still apply. These settings do not change macOS preferences. See the [gesture and tuning notes](docs/14-trackpad-additions.md).

## Configuration backups (2.10.1)

**Configuration → Export Copy…** includes both devices’ gestures, conditions, actions and all current tuning controls, including TipTap timing/sensitivity/spacing, pointer speed and scroll inversion. It exports current edits immediately and atomically replaces the chosen backup. Import validates the supported block-style YAML before applying it; malformed or unsupported files are rejected without changing settings. A failed save restores the prior in-memory configuration. macOS Accessibility and login-item registration remain OS-managed, rather than transferable permissions.
