#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BetterGlideTool — build.sh
#  Compiles all Swift sources and produces BetterGlideTool.app
#  Compatible with macOS 13+ on Apple Silicon
#
#  Usage:
#    ./build.sh
#        Build the app only.
#
#    ./build.sh restart
#        Build the app, then quit any running instance and launch
#        the freshly built app.
#
#    ./build.sh restart-only
#        Skip compilation and launch the already-built app.
#
#    ./build.sh --release
#        Build an optimized Apple Silicon (arm64) app.
#
#    ./build.sh --dmg
#        Build an optimized Apple Silicon app and create a DMG.
#
#    ./build.sh --help
#        Show this usage information.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BetterGlideTool"
BUNDLE_ID="com.betterglidetool.app"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_EXECUTABLE="$MACOS/$APP_NAME"


# ─────────────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
BetterGlideTool build script

Usage:
  ./build.sh
      Build the app only.

  ./build.sh restart
      Build the app, then restart the running app using the
      freshly built binary.

  ./build.sh restart-only
      Skip compilation and restart the already-built app.

  ./build.sh --release
      Build an optimized Apple Silicon (arm64) app.

  ./build.sh --dmg
      Build an optimized Apple Silicon app and create a DMG.

Notes:
  - "restart" ALWAYS builds before restarting.
  - "restart-only" is the ONLY command that skips the build.
EOF
    exit 0
fi


# ─────────────────────────────────────────────────────────────
# Restart existing app
# ─────────────────────────────────────────────────────────────

# Quits any running instance and relaunches the currently built app.
restart_app() {
    echo "==> Quitting any running $APP_NAME instance"

    osascript -e "tell application \"$APP_NAME\" to quit" \
        >/dev/null 2>&1 || true

    pkill -x "$APP_NAME" \
        >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "==> Force quitting stubborn $APP_NAME process"
        pkill -9 -x "$APP_NAME" \
            >/dev/null 2>&1 || true
    fi

    if [[ ! -x "$APP_EXECUTABLE" ]]; then
        echo "ERROR: Built executable not found at:"
        echo "  $APP_EXECUTABLE"
        echo ""
        echo "Run ./build.sh first, then run:"
        echo "  ./build.sh restart-only"
        exit 1
    fi

    echo "==> Opening built $APP_NAME"
    open "$APP_BUNDLE"

    cat <<EOF

Done.

App bundle:
  $APP_BUNDLE

EOF
}


# ─────────────────────────────────────────────────────────────
# Restart-only
# ─────────────────────────────────────────────────────────────

# IMPORTANT:
# This intentionally skips compilation.
#
# Use:
#   ./build.sh restart
# for the normal "build + restart" workflow.
#
# Use:
#   ./build.sh restart-only
# ONLY when you want to launch the existing build again.
if [[ "${1:-}" == "restart-only" ]]; then
    restart_app
    exit 0
fi


# ─────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building $APP_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"


# ─────────────────────────────────────────────────────────────
# Check swiftc
# ─────────────────────────────────────────────────────────────

if ! command -v swiftc &>/dev/null; then
    echo "❌  swiftc not found. Install Xcode or Xcode Command Line Tools."
    echo "    Run: xcode-select --install"
    exit 1
fi

SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)
echo "Swift: $SWIFT_VERSION"


# ─────────────────────────────────────────────────────────────
# Clean previous build
# ─────────────────────────────────────────────────────────────

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"


# ─────────────────────────────────────────────────────────────
# Copy Info.plist
# ─────────────────────────────────────────────────────────────

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"

# Only opt into releases from this fork; local builds remain offline by default.
RELEASE_REPOSITORY="${BETTERGLIDETOOL_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
if [[ -n "$RELEASE_REPOSITORY" ]]; then
    if [[ ! "$RELEASE_REPOSITORY" =~ ^[A-Za-z0-9-]+/BetterGlideTool$ ]]; then
        echo "ERROR: Release repository must be OWNER/BetterGlideTool"
        exit 1
    fi
    /usr/libexec/PlistBuddy -c "Add :BetterGlideToolRepository string $RELEASE_REPOSITORY" "$CONTENTS/Info.plist"
fi


# ─────────────────────────────────────────────────────────────
# Copy app icon
# ─────────────────────────────────────────────────────────────

# assets/AppIcon.icon is the Icon Composer document: a glass hand over a
# system-managed fill, which macOS 26 renders as Liquid Glass in Default, Dark,
# Clear and Tinted. Xcode's asset compiler turns it into Assets.car (the
# layered icon) and AppIcon.icns (the flat icon for macOS 13–15). Without
# Xcode, the compiled copies committed next to it are used.
ICON_DOC="$SCRIPT_DIR/assets/AppIcon.icon"
XCODE_DEVELOPER="${XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ICON_TMP=""
if [[ -d "$ICON_DOC" && -d "$XCODE_DEVELOPER" ]] && DEVELOPER_DIR="$XCODE_DEVELOPER" xcrun --find actool >/dev/null 2>&1; then
    ICON_TMP="$(mktemp -d)"
    if DEVELOPER_DIR="$XCODE_DEVELOPER" xcrun actool "$ICON_DOC" --compile "$ICON_TMP" --platform macosx \
        --minimum-deployment-target 13.0 --app-icon AppIcon \
        --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null 2>&1 \
        && [[ -f "$ICON_TMP/Assets.car" && -f "$ICON_TMP/AppIcon.icns" ]]; then
        # Refresh the committed copies only when the icon itself changed: the
        # compiler's output differs byte-for-byte on every run.
        if [[ ! -f "$SCRIPT_DIR/assets/AppIcon.car" ]] || [[ -n "$(find "$ICON_DOC" -newer "$SCRIPT_DIR/assets/AppIcon.car" -print -quit)" ]]; then
            cp "$ICON_TMP/Assets.car" "$SCRIPT_DIR/assets/AppIcon.car"
            cp "$ICON_TMP/AppIcon.icns" "$SCRIPT_DIR/assets/AppIcon.icns"
        fi
        echo "Icon: compiled AppIcon.icon with Xcode's asset compiler (Liquid Glass)"
    else
        echo "Icon: asset compiler failed; using the committed compiled icon"
    fi
fi
ICON_SOURCE="$SCRIPT_DIR/assets"; ICON_CAR="$ICON_SOURCE/AppIcon.car"
if [[ -n "$ICON_TMP" && -f "$ICON_TMP/Assets.car" && -f "$ICON_TMP/AppIcon.icns" ]]; then
    ICON_SOURCE="$ICON_TMP"; ICON_CAR="$ICON_TMP/Assets.car"
fi
if [[ -f "$ICON_CAR" ]]; then
    cp "$ICON_CAR" "$RESOURCES/Assets.car"
fi
if [[ -f "$ICON_SOURCE/AppIcon.icns" ]]; then
    cp "$ICON_SOURCE/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "Icon: Assets.car and AppIcon.icns copied"
fi


# ─────────────────────────────────────────────────────────────
# Copy localizations
# ─────────────────────────────────────────────────────────────

# Localization/<language>.lproj/Localizable.strings: English text is the key,
# so English needs no table; Turkish is in tr.lproj.
for lproj in "$SCRIPT_DIR"/Localization/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$RESOURCES/"
done


# ─────────────────────────────────────────────────────────────
# Collect Swift sources
# ─────────────────────────────────────────────────────────────

SOURCES=()

while IFS= read -r -d $'\0'; do
    SOURCES+=("$REPLY")
done < <(
    find "$SCRIPT_DIR/Sources" -name "*.swift" -print0
)


# Verify all sources exist
for src in "${SOURCES[@]}"; do
    if [[ ! -f "$src" ]]; then
        echo "❌  Missing source: $src"
        exit 1
    fi
done


# ─────────────────────────────────────────────────────────────
# Determine SDK
# ─────────────────────────────────────────────────────────────

echo "Compiling…"

SDK_PATH="$(xcrun --show-sdk-path)"

# xcrun can resolve to a CommandLineTools SDK whose Swift module
# was built by a newer compiler than the installed swiftc.
#
# The active Xcode bundles an SDK matching its own swiftc, so
# prefer it when present; fall back to xcrun on CLT-only machines.
XCODE_SDK="$(
    xcode-select -p 2>/dev/null
)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

[[ -d "$XCODE_SDK" ]] && SDK_PATH="$XCODE_SDK"


# ─────────────────────────────────────────────────────────────
# Determine build mode
# ─────────────────────────────────────────────────────────────

IS_RELEASE=0

for arg in "$@"; do
    if [[ "$arg" == "--release" || "$arg" == "--dmg" ]]; then
        IS_RELEASE=1
    fi
done

if [[ "$IS_RELEASE" == 1 ]]; then
    # Apple Silicon only: release builds are not made for Intel Macs.
    ARCHS=(arm64)
    SWIFT_OPT="-O"

    echo "Mode: Release (Apple Silicon, Optimized)"
else
    ARCHS=($(uname -m))
    SWIFT_OPT="-Onone"

    echo "Mode: Debug (Native arch only, Fast build)"
fi


# ─────────────────────────────────────────────────────────────
# Compile
# ─────────────────────────────────────────────────────────────

BINARIES=()

for arch in "${ARCHS[@]}"; do
    echo ""
    echo "==> Compiling $arch"

    out="$BUILD_DIR/$APP_NAME-$arch"

    # Multitouch bridge
    c_out="$BUILD_DIR/GlideMultitouchBridge-$arch.o"

    clang \
        -O3 \
        -target "$arch-apple-macosx13.0" \
        -isysroot "$SDK_PATH" \
        -c \
        "$SCRIPT_DIR/Sources/Gestures/Components/GlideMultitouchBridge.c" \
        -o "$c_out"

    # WindowServer bridge
    c2_out="$BUILD_DIR/GlideWindowServerBridge-$arch.o"

    clang \
        -O3 \
        -target "$arch-apple-macosx13.0" \
        -isysroot "$SDK_PATH" \
        -c \
        "$SCRIPT_DIR/Sources/Actions/Components/GlideWindowServerBridge.c" \
        -o "$c2_out"

    if swiftc \
        $SWIFT_OPT \
        -target "$arch-apple-macosx13.0" \
        -sdk "$SDK_PATH" \
        -import-objc-header "$SCRIPT_DIR/Sources/App/Internal/Glide-Bridging-Header.h" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework IOKit \
        -framework CoreGraphics \
        -framework UniformTypeIdentifiers \
        -o "$out" \
        "${SOURCES[@]}" \
        "$c_out" \
        "$c2_out" \
        2>&1
    then
        BINARIES+=("$out")
    elif [[ "$arch" == "$(uname -m)" ]]; then
        echo "❌  Native $arch build failed"
        exit 1
    else
        echo "⚠️  Skipping optional $arch build on this machine"
    fi
done


# ─────────────────────────────────────────────────────────────
# Create final app executable
# ─────────────────────────────────────────────────────────────

if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "❌  No app binary was produced"
    exit 1

elif [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$MACOS/$APP_NAME"

else
    lipo \
        -create \
        "${BINARIES[@]}" \
        -output "$MACOS/$APP_NAME"
fi

echo "✅  Compile succeeded"


# ─────────────────────────────────────────────────────────────
# Code sign
# ─────────────────────────────────────────────────────────────

echo "Signing…"

DEV_ID_CERT=$(
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n \
        's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -1
)

if [[ -z "$DEV_ID_CERT" ]]; then
    DEV_ID_CERT=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n \
            's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
            | head -1
    )
fi

IDENTITY="${DEV_ID_CERT:--}"


if [[ "$IDENTITY" == "-" ]]; then

    echo "⚠️  No Developer ID or Apple Development cert — ad-hoc signing."
    echo "    Downloaded copies need Settings → Privacy & Security → Open Anyway (once)."

    codesign \
        --force \
        --sign - \
        --entitlements "$SCRIPT_DIR/BetterGlideTool.entitlements" \
        "$APP_BUNDLE"

else

    echo "Identity: $IDENTITY"

    codesign \
        --force \
        --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$SCRIPT_DIR/BetterGlideTool.entitlements" \
        "$APP_BUNDLE"

fi


# ─────────────────────────────────────────────────────────────
# Verify signature
# ─────────────────────────────────────────────────────────────

codesign --verify --strict "$APP_BUNDLE"

if ! codesign \
    -d \
    --entitlements - \
    --xml \
    "$APP_BUNDLE" 2>/dev/null \
    | grep -q "com.apple.security.automation.apple-events"
then
    echo "❌  Entitlements missing after signing" >&2
    exit 1
fi

echo "✅  Signed"


# ─────────────────────────────────────────────────────────────
# Optional DMG
# ─────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--dmg" ]]; then

    echo "Creating DMG…"

    DMG_STAGE="$BUILD_DIR/dmg-stage"
    DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

    rm -rf "$DMG_STAGE" "$DMG_PATH"

    mkdir -p "$DMG_STAGE"

    cp -R "$APP_BUNDLE" "$DMG_STAGE/"

    ln -s /Applications "$DMG_STAGE/Applications"

    # The window shows a background (assets/dmg-background.png, drawn by
    # render_dmg_background.swift) with an arrow from the app to Applications
    # and the xattr line. Finder stores that layout in the volume's .DS_Store,
    # so the image is built writable, laid out through Finder, then compressed.
    # If Finder can't be scripted (no Automation permission, headless runner),
    # the DMG still ships, just without the custom layout.
    DMG_BACKGROUND="$SCRIPT_DIR/assets/dmg-background.png"
    if [[ -f "$DMG_BACKGROUND" ]]; then
        mkdir -p "$DMG_STAGE/.background"
        cp "$DMG_BACKGROUND" "$DMG_STAGE/.background/background.png"
        chflags hidden "$DMG_STAGE/.background"
    fi

    DMG_RW="$BUILD_DIR/$APP_NAME-rw.dmg"
    rm -f "$DMG_RW"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDRW -fs HFS+ "$DMG_RW" >/dev/null
    rm -rf "$DMG_STAGE"

    # Mounted in /Volumes so Finder lists it; the volume may come up as
    # "BetterGlideTool 1" if another copy is open, so take the name from the
    # mount point.
    DMG_MOUNT=""
    if [[ -f "$DMG_BACKGROUND" ]]; then
        DMG_MOUNT="$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$' | tail -1)"
    fi
    if [[ -n "$DMG_MOUNT" && -d "$DMG_MOUNT" ]]; then
        DMG_VOLUME="$(basename "$DMG_MOUNT")"
        if osascript >/dev/null <<OSA
tell application "Finder"
    tell disk "$DMG_VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {170, 140}
        set position of item "Applications" of container window to {470, 140}
        try
            set position of item ".background" of container window to {900, 600}
        end try
        close
        open
        delay 1
        close
    end tell
end tell
OSA
        then
            # Give Finder a moment to write .DS_Store before detaching.
            for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f "$DMG_MOUNT/.DS_Store" ]] && break; sleep 0.5; done
            echo "DMG: window laid out with background and arrow"
        else
            echo "⚠️  DMG: Finder couldn't be scripted; shipping without the background layout"
        fi
        rm -rf "$DMG_MOUNT/.fseventsd"
        sync
        for _ in 1 2 3 4 5; do hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 && break; sleep 1; done
        if [[ -d "$DMG_MOUNT/$APP_NAME.app" ]]; then hdiutil detach -force "$DMG_MOUNT" >/dev/null; fi
    fi

    hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
    rm -f "$DMG_RW"


    # Notarize + staple when a Developer ID cert and stored
    # notarytool credentials exist.
    #
    # Setup:
    #
    #   xcrun notarytool store-credentials betterglidetool-notary \
    #     --apple-id <email> \
    #     --team-id <TEAMID> \
    #     --password <app-specific-pw>

    if [[ -n "$DEV_ID_CERT" ]] && \
       xcrun notarytool history \
           --keychain-profile betterglidetool-notary \
           >/dev/null 2>&1
    then

        echo "Notarizing…"

        xcrun notarytool submit \
            "$DMG_PATH" \
            --keychain-profile betterglidetool-notary \
            --wait

        xcrun stapler staple "$DMG_PATH"

        xcrun stapler validate "$DMG_PATH"

        echo "✅  Notarized and stapled"

    else

        echo "ℹ️  Skipping notarization (needs a Developer ID cert +"
        echo "    'xcrun notarytool store-credentials betterglidetool-notary' setup)."

    fi

    echo "✅  DMG: $DMG_PATH"
fi


# ─────────────────────────────────────────────────────────────
# Print result
# ─────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  App bundle: $APP_BUNDLE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Next steps:"
echo "  1. Run:  open \"$APP_BUNDLE\""
echo "  2. macOS will prompt for Accessibility permission."
echo "  3. Go to System Settings → Privacy & Security → Accessibility"
echo "     and enable BetterGlideTool."
echo "  4. The hand icon will appear in your menu bar."

echo ""
echo "Optional — move to Applications:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo ""


# ─────────────────────────────────────────────────────────────
# Optional restart
# ─────────────────────────────────────────────────────────────

# "restart" means BUILD + RESTART.
#
# This is intentionally at the very end so the freshly compiled,
# signed app is what gets launched.
if [[ "${1:-}" == "restart" ]]; then
    echo "==> Build complete — restarting $APP_NAME"
    restart_app
fi
