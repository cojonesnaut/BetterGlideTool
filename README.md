# BetterGlideTool

A renamed fork of [Glide by Vatsal057](https://github.com/Vatsal057/Glide): a native macOS utility for trackpad gestures, window management, edge sliders, TrackPoint mode, and global shortcuts.

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

- Customizable multi-finger swipes, clicks, force-clicks, and holds.
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
