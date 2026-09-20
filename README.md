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
- Magic Mouse taps and two-finger swipes, with middle-click, window, app, and media actions.
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

Open **Preferences → Magic Mouse**. Support is enabled by default when the main gesture engine is active and Accessibility permission is granted. A two-finger tap produces a middle click; a three-finger tap opens Mission Control. One-finger taps and two-finger swipes are opt-in, with separate action assignments and sensitivity controls.

The new input provider, recognizer, settings, and preferences are Swift. It reuses the existing action engine and shared multitouch ABI, adds no third-party libraries, and uses IOKit device notifications instead of a new polling timer. Recognition runs on incoming touch frames; only completed actions cross to the main queue. Mouse and trackpad state stay separate.

See [Magic Mouse setup and behavior](docs/13-magic-mouse.md). Force-click, haptics, TrackPoint, and trackpad edge sliders remain trackpad features.

## Verification

```sh
bash Verification/run.sh
```

The checks cover touch recognition, accidental-click rejection, device isolation, and configuration import/export. They compile and run without enabling gesture handling or requesting permissions. Set `SDKROOT` as described above if your installed Command Line Tools need the older SDK.
