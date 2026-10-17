# Trackpad additions and TipTap tuning

## Gestures

- **1 Finger Circle Clockwise / Counter-Clockwise:** draw a closed loop, then lift. The path must span at least 10% of each sensor dimension and finish within three seconds. Very small loops, open arcs, backtracking and additional fingers are rejected. When one-finger swipes are also assigned, a straight path fires its swipe on lift instead of firing halfway around a circle. Normal pointer motion continues.
- **Corner Click Bottom Left / Bottom Right / Top Left / Top Right:** one finger in the outer 20% of both corresponding edges plus a physical click. The native click also passes through. Unidentified devices do not trigger custom corner clicks.
- **3 Finger Tap Top / Bottom:** the average initial position of all three contacts is in the upper/lower half. App conditions take priority, then regional rules, then the general three-finger tap. Double-tap arbitration still postpones the matching single tap.
- **TipSwipe Left Finger Left / Right (2 Fingers Fix):** rest two fingers, then place another to their left and slide it horizontally while both anchors stay still. Existing up/down TipSwipes remain available.
- **4 Finger Tap / 4 Finger Double Tap:** four contacts landing together; the double-tap interval remains 300 ms. Existing four-finger physical click, FORCE Click and directional swipes keep their original engine.
- **TipTap Left / Right (3 Fingers Fix):** rest three fingers, tap a fourth to their left/right, then lift the tapping finger while every anchor remains down. All fingers must lift before repeating.

TrackPoint, edge controls, App Switcher and macOS gestures can own overlapping inputs. Disable a conflicting assignment for a clean physical test. No system gesture setting is changed automatically.

## TipTaps in each device's Tuning page

Sensitivity uses the sensor's reported **contact size**, not calibrated force/pressure. Moving toward Harder Touch raises the minimum size reached by the tapping contact. The first, second and third sensitivity controls apply with one, two and three resting fingers respectively. Magic Mouse has the first two controls; its **Allow sensitive TipTaps** option lowers those thresholds, and defaults off to reject accidental light contacts.

Trackpad's **1 Finger TipTap: Allow Finger Movement** permits bounded drift for one-anchor TipTaps (up to 10% of the normalized surface instead of the ordinary tap tolerance). Multi-anchor TipTaps always require stable anchors. Minimum distance is horizontal separation from each anchor: Two Finger applies to one anchor plus the tapping finger; Three Finger applies to two or three anchors plus the tapping finger. Maximum distance is the straight-line distance from the tapping finger to every anchor at landing. Values are fractions of the sensor dimensions. Inconsistent minimum/maximum values are clamped.

Defaults follow the screenshot sensitivity values: trackpad 0.38 / 0.50 / 0.35, minimum spacing 0.03 and maximum spacing 0.55; mouse 0.50 / 0.30. Actual feel depends on contact-size reporting by the hardware. The existing fixed-finger rest and minimum tap-duration settings also apply, and actions fire on lift. Each TipTaps reset button resets only that device's new TipTap controls, preserving timing and pointer settings.

Settings are exported under `touchpad.device_tuning`. Old files acquire defaults automatically. Recognition has automated checks; contact thresholds, corner placement and gestures still need physical validation on the user's devices.

### TipTap repeat behavior (2.10.5)

One, two and three resting fingers can remain down between deliberate TipTaps. Each tapping-finger lift rearms the next stroke, with a 30 ms contact-bounce guard and the existing minimum duration/contact-size checks. A completed TipTap may switch apps without losing its resting anchors; an unfinished stroke is cancelled when the app changes. Each new tap uses the current app’s rules.

## Input Monitoring

Choose **Trackpad → Input Monitoring** in the preferences sidebar for Trackpad Input diagnostics and Live Contacts. These sections have moved out of Tuning. **Float** keeps the contact readings visible over the app being tested without taking its keyboard focus. The main view shows purple contacts and a latest-first gesture/action log. **Show IDs** labels dots, **Details** reveals numeric readings, and **Input Diagnostics** expands the status report. Record 15 Seconds captures contact frames, app names and dispatched gestures; Export saves JSON. Magic Mouse has an equivalent page with independent readings, recordings and panel placement. Contact size is not calibrated pressure.
