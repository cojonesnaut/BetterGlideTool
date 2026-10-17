# Magic Mouse

Open **Preferences**, then choose **Magic Mouse** in the top-left device dropdown with your mouse connected by Bluetooth. Grant BetterGlideTool Accessibility permission, then keep the main **Gestures active** switch enabled. Open **Magic Mouse → Tuning** to see connection status and tuning controls. **Reconnect** refreshes detection if necessary. The gesture list, editor, conditions, and action picker use the same interface as Trackpad.

## Defaults

| Input | Default action |
| --- | --- |
| Two-finger tap | Middle click |
| Three-finger tap | Mission Control |
| One-finger tap on either side | Off |
| Two-finger swipe in any direction | Off |

Lift your fingers, then land them together briefly and lift again, without pressing the physical mouse button. Fingers that were already resting on the mouse do not count as a fresh tap. Physical clicks, scrolling, long rests, pointer travel, and excessive finger motion cancel a pending ordinary tap to prevent extra clicks.

Use **Conditions → Apps** to select multiple apps for one rule. The rule runs when any selected app is frontmost; an empty selection means Any App. **Choose Apps…** accepts multiple application bundles, including apps that are not running.

Each gesture can be assigned independently to left/right/middle click, window snapping and sizing, adjacent app activation, Mission Control, Show Desktop, playback, or volume controls. Left/right tap assignments divide the touch surface at its horizontal midpoint. Unassigned physical clicking and one-finger scrolling continue to work.

## Two-finger gestures on both devices

The Trackpad and Magic Mouse menus share these names:

- **2 Finger Tap**
- **2 Finger Double-Tap**
- **TipTap Left (1 Finger Fix)**
- **TipTap Right (1 Finger Fix)**
- **2 Finger Click**

Double-tap uses two taps within 300 ms in approximately the same area. Assigning double-tap delays single-tap dispatch until that interval expires; a recognized double-tap does not also fire the single-tap action.

For TipTap, keep one finger stationary for at least 250 ms by default, then place and lift another finger on the indicated side. Keep the first finger down throughout. The tapping finger must stay down for at least 80 ms by default. Adjust both times under the selected device’s **Tuning → TipTap timing**. Moving the fixed finger beyond its configured tolerance or lifting both cancels TipTap. After a successful tap, keep the anchor down and tap again; the initial rest delay is not repeated.

For two-finger click, hold two contacts on the surface and press the physical button. A confirmed native event from that device is required: another mouse's click cannot trigger a trackpad rule. If macOS cannot identify the sender, the custom click does not fire. Native clicks still pass through, so an assigned action can accompany the normal click. Tap-to-click does not substitute for this physical-click gesture.

## Swipes

For a two-finger swipe, both fingers must travel together in a clear direction. A pinch or one-finger scroll does not count. Each swipe fires once, and all fingers must lift before another gesture can fire.

When you assign custom swipes, turn off overlapping gestures under **System Settings → Mouse → More Gestures**. BetterGlideTool does not change those system settings automatically. Only the assigned axis of scrolling from an identified Magic Mouse is reserved for that finger count while a custom swipe session is active. Left/right bindings keep vertical scrolling working; up/down bindings keep horizontal scrolling working. Mixed-axis events retain the unassigned component and native scroll phases. Single-finger swipes are also available and off by default; assigning one uses the same surface motion as native one-finger scrolling. Other devices' scroll events pass through. If macOS cannot identify a scroll event's sender, it passes through too, so native scrolling may accompany the custom swipe on an unsupported OS or mouse revision.

## Sensitivity and storage

Both devices have a **Tuning** sidebar page with independent gesture sensitivity and native pointer speed. The sensitivity midpoint preserves previous thresholds; move left for easier gestures and right for more deliberate gestures. Pointer **Reset** returns to the captured native setting at 1×. The native acceleration curve remains in use, so the speed change depends on movement speed. The status below the pointer slider reports whether macOS accepted the adjustment.

App-specific rules take priority over Any App rules; a rule's app condition also controls whether it reserves native mouse scrolling. Quit competing gesture utilities such as BetterTouchTool before testing. Under **Magic Mouse → Input Monitoring**, expand **Input Diagnostics** to check **Touch input**, **Last gesture**, and the connection label. The live view shows purple contact dots and a latest-first gesture/action log. **Float** opens the compact panel; **Show IDs** labels dots and **Details** reveals raw readings. Copy Readings and 15-second JSON recording/export remain available. Connection and sensitivity controls remain in **Tuning**.


- **Maximum tap duration:** how quickly all fingers must lift.
- **Tap movement tolerance:** how much a finger may move during a tap, as a fraction of the sensor dimensions.
- **Swipe distance:** how far both fingers must travel before a swipe fires.

Connection and sensitivity settings live under `touchpad.magic_mouse` in `config.yaml`. Gesture rules use the shared gesture list with `device: trackpad` or `device: magicMouse` and `app_filters` for multiple app bundle identifiers. Import, export, and factory reset include both devices. The historical top-level key is retained for compatibility. Legacy mouse assignments migrate once; `gesture_schema_version: 1` prevents deleted assignments from reappearing. Rules without a device remain trackpad rules, and legacy `app_filter` values remain supported.

## Lifecycle and resource use

Mouse recognition is separate for each detected device, so contacts from two devices cannot combine. Pausing gestures, switching mouse support off, sleeping, or disconnecting discards pending actions. Bluetooth connection changes trigger a debounced device refresh; wake recovery uses the existing engine lifecycle. There is no new repeating polling loop and no third-party runtime dependency.

The mouse uses the same private macOS multitouch framework as the trackpad. Known Magic Mouse device families are selected explicitly; an external Magic Trackpad is not treated as a mouse. Missing system APIs disable mouse support gracefully. TrackPoint, physical edge sliders, pressure/force-click, and haptic feedback remain trackpad-only features.

## Validation scope

Automated checks cover taps, double-tap arbitration, left/right TipTap, two-finger physical-click recognition, swipe recognition, click and scroll cancellation, noisy inputs, device separation, multi-app matching, YAML round-tripping, legacy migration, permission prompt gating, and the shared raw touch layout. The shared editors and multiple app selection were also checked in an isolated UI preview. A local device probe confirmed separate trackpad and Magic Mouse enumeration. Full physical gesture behavior still needs a hands-on check with Accessibility enabled; detection alone does not verify recognition or native gesture conflicts.

[Back to usage manual](../USAGE.md)

## Three-finger gestures (2.9)

The shared editor now includes the full three-finger set from the reference: tap, double-tap, click, four swipes, three TipTap positions with two fingers fixed, and left-finger up/down TipSwipe. Two-fixed-finger gestures use the device's existing TipTap timing. Keep the anchors stationary; after the tapping finger lifts, a fresh deliberate tap can repeat while those anchors stay down. Double-tap postpones the matching single tap by up to 300 ms; two- and three-finger taps cannot form one double-tap.

Magic Mouse Tuning also has vertical/horizontal scroll inversion. Transformations preserve native momentum and affect only confirmed Magic Mouse events. Smooth scrolling is omitted because Vorssaint's corresponding service leaves Magic Mouse untouched.

## One-finger regions and four-finger gestures (2.10)

**1 Finger Tap** covers the whole surface. **1 Finger Tap Left/Right** cover its two halves. **1 Finger Tap Middle** covers the central 20% of the width. **1 Finger Tap Above Apple** uses the lower central patch (35–65% across and 15–40% up from the bottom of the normalized sensor). These are fixed regions; their placement still needs confirmation on physical hardware.

App-specific rules take priority over Any App rules. Among rules in the same app scope, Above Apple takes priority over Middle, then Left/Right, then general Tap. Only rules matching their modifier and window conditions participate, and each tap executes at most one action. Existing left/right assignments are preserved.

**1 Finger Middle Click** requires a physical left-button press with one contact in the middle strip. It does not itself choose the Middle Click action: select that action if desired. **4 Finger Click** requires a physical left-button press with four contacts. When a matching rule exists and the sender is identified, these new gestures consume the native down/up/drag sequence; otherwise the native click passes through.

**4 Finger Swipe Up/Down/Left/Right** require all four contacts to travel together. Reordered touch frames, partial lifts and one moving finger cannot produce another swipe. Lift all fingers before repeating. Scroll reservation follows the same per-axis rules as other finger counts. New regions and four-finger gestures add no timers or external dependencies.
