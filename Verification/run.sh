#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CHECK_DIR="$ROOT/build/verification"
mkdir -p "$CHECK_DIR"
SDK_PATH="$(xcrun --show-sdk-path)"
COMMON=(-target "$(uname -m)-apple-macosx13.0" -sdk "$SDK_PATH" -module-cache-path "$CHECK_DIR/module-cache")
swiftc "${COMMON[@]}" Sources/MagicMouse/MagicMouseSettings.swift Sources/MagicMouse/MagicMouseRecognizer.swift Verification/MagicMouseTests.swift -o "$CHECK_DIR/recognizer"
"$CHECK_DIR/recognizer"
# Build a headless executable against the actual app sources, replacing only the
# app's entry point so tests never launch gesture handling or change permissions.
sed '/^@main$/d' Sources/App/GestureApp.swift > "$CHECK_DIR/GestureApp.swift"
SOURCES=()
while IFS= read -r -d '' source; do
    [[ "$source" == "Sources/App/GestureApp.swift" ]] || SOURCES+=("$source")
done < <(find Sources -name '*.swift' -print0)
clang -target "$(uname -m)-apple-macosx13.0" -isysroot "$SDK_PATH" -c Sources/Gestures/Components/GlideMultitouchBridge.c -o "$CHECK_DIR/multitouch.o"
clang -target "$(uname -m)-apple-macosx13.0" -isysroot "$SDK_PATH" -c Sources/Actions/Components/GlideWindowServerBridge.c -o "$CHECK_DIR/windows.o"
swiftc "${COMMON[@]}" -import-objc-header Sources/App/Internal/Glide-Bridging-Header.h \
    -framework Cocoa -framework SwiftUI -framework IOKit -framework CoreGraphics -framework UniformTypeIdentifiers \
    "${SOURCES[@]}" "$CHECK_DIR/GestureApp.swift" Verification/ConfigurationTests.swift \
    "$CHECK_DIR/multitouch.o" "$CHECK_DIR/windows.o" -o "$CHECK_DIR/configuration"
"$CHECK_DIR/configuration"
