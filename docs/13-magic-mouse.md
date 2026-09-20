# Magic Mouse

Open **Preferences → Magic Mouse** with your mouse connected by Bluetooth. Grant BetterGlideTool Accessibility permission, then keep the main **Gestures active** switch enabled. The status row identifies whether the mouse is connected. **Reconnect** refreshes detection if necessary.

## Defaults

| Input | Default action |
| --- | --- |
| Two-finger tap | Middle click |
| Three-finger tap | Mission Control |
| One-finger tap on either side | Off |
| Two-finger swipe in any direction | Off |

Lift your fingers, then land them together briefly and lift again, without pressing the physical mouse button. Fingers that were already resting on the mouse do not count as a fresh tap. Physical clicks, scrolling, long rests, pointer travel, and excessive finger motion cancel a pending tap to prevent extra clicks.

Each gesture can be assigned independently to left/right/middle click, window snapping and sizing, adjacent app activation, Mission Control, Show Desktop, playback, or volume controls. One-finger tap assignments divide the touch surface at its horizontal midpoint. Ordinary physical clicking and one-finger scrolling continue to work.

## Swipes

Two fingers must travel together in a clear direction. A pinch or one-finger scroll does not count. Each swipe fires once, and all fingers must lift before another gesture can fire.

When you assign custom swipes, turn off overlapping gestures under **System Settings → Mouse → More Gestures**. BetterGlideTool does not change those system settings automatically. Two-finger scrolling from an identified Magic Mouse is reserved while a custom swipe session is active. Other devices' scroll events pass through. If macOS cannot identify a scroll event's sender, it passes through too, so native scrolling may accompany the custom swipe on an unsupported OS or mouse revision.

## Sensitivity and storage

- **Maximum tap duration:** how quickly all fingers must lift.
- **Tap movement tolerance:** how much a finger may move during a tap, as a fraction of the sensor dimensions.
- **Swipe distance:** how far both fingers must travel before a swipe fires.

Mouse settings live under `touchpad.magic_mouse` in the existing `config.yaml` file and are included in import, export, and factory reset. The historical top-level key is retained for compatibility. Older configurations without this section receive the defaults above. Mouse assignments are independent of trackpad rules.

## Lifecycle and resource use

Mouse recognition is separate for each detected device, so contacts from two devices cannot combine. Pausing gestures, switching mouse support off, sleeping, or disconnecting discards pending actions. Bluetooth connection changes trigger a debounced device refresh; wake recovery uses the existing engine lifecycle. There is no new repeating polling loop and no third-party runtime dependency.

The mouse uses the same private macOS multitouch framework as the trackpad. Known Magic Mouse device families are selected explicitly; an external Magic Trackpad is not treated as a mouse. Missing system APIs disable mouse support gracefully. TrackPoint, physical edge sliders, pressure/force-click, and haptic feedback remain trackpad-only features.

## Validation scope

Automated checks cover tap/swipe recognition, physical-click and scroll cancellation, noisy and malformed inputs, device separation, YAML round-tripping, legacy configs, and the shared raw touch layout. A local device probe confirmed separate trackpad and Magic Mouse enumeration. Full physical gesture behavior still needs a hands-on check with Accessibility enabled; detection alone does not verify recognition or native gesture conflicts.

[Back to usage manual](../USAGE.md)
