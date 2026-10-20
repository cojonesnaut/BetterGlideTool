# BetterGlideTool icon layers

`Hand.png` and `Background.png` are separate, unmasked 1024 × 1024 source layers.
Regenerate them with `swift assets/render_icon.swift assets/IconComposerLayers layers`.

The background gradient is sampled in sRGB from the reference at
https://macosicons.com/?icon=Z6DW2YmoxD: top #A28AF5, bottom #9871F7.
Only the colors are used; the reference glyph is not copied. The foreground is
Apple's `hand.draw` system symbol in white.

## Native Liquid Glass status

These PNG layers are artwork, not a compiled Liquid Glass icon. The local build
machine has Command Line Tools but no Xcode/actool or Icon Composer. Version
2.10.2 therefore ships the standard static AppIcon.icns, which works on macOS 13+.
It does not claim native layered, dark/clear/tinted Liquid Glass support.

To finish the native version on a machine with Xcode 26 or later:

1. Import the layers into Icon Composer on the 1024 × 1024 iOS/macOS canvas,
   background below the hand. Preserve their original positions and scale.
2. Keep the background opaque; apply the native glass material to the hand and
   preview Default, Dark, and Mono appearances. Let the system supply the mask.
3. Save an AppIcon.icon document, compile it with Xcode's asset compiler, and
   integrate its generated Assets.car, compatibility icon and icon metadata into
   the application bundle before signing.
4. Verify the actual installed Dock/Finder icon in the supported appearances.

The renderer deliberately omits baked-in highlights and shadows from these layers
so Icon Composer can provide the native material. The static compatibility icon
has restrained fixed lighting.

Apple's workflow: https://developer.apple.com/icon-composer/
