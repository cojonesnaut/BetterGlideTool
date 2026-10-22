# BetterGlideTool icon

The app icon is `assets/AppIcon.icon`, an Icon Composer document: Apple's
`hand.draw.fill` symbol in white as a single Liquid Glass layer, over a
system-managed violet fill (automatic gradient from #9C7DF6). macOS 26 and later
render it natively in every appearance — Default, Dark, Clear (light and dark)
and Tinted — because the background is a fill the system can replace, not a
baked image.

`build.sh` compiles it with Xcode's asset compiler when Xcode is installed
(`/Applications/Xcode.app`, or `XCODE_DEVELOPER_DIR`), producing:

- `Assets.car` — the layered Liquid Glass icon (`CFBundleIconName`), and
- `AppIcon.icns` — the flat icon macOS 13–15 use (`CFBundleIconFile`).

Both are committed as `assets/AppIcon.car` and `assets/AppIcon.icns`, so builds
without Xcode still ship the same icon. Open `AppIcon.icon` in Icon Composer
(Xcode ▸ Open Developer Tool) to adjust it; the next build recompiles it.

Preview any appearance from the command line:

    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
        assets/AppIcon.icon --export-image --output-file clear-dark.png --platform macOS \
        --rendition ClearDark --width 1024 --height 1024 --scale 1

`Hand.png` and `Background.png` here are the older flat layers, kept for
reference; `render_icon.swift` regenerates them.
