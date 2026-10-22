# Changelog

## BetterGlideTool 3.0.0

The first BetterGlideTool release on its own, gathering 2.11.0 through 2.12.11.

- **Gestures that feel like BetterTouchTool**, measured against it: smoother edge scrolling; reliable swipes and thumb-arc swipes; TipTaps that act within a few milliseconds and never click through; Tip swipes that never scroll the page; one-finger Magic Mouse and two-finger trackpad swipes that fire on a flick and leave panning alone; and live circles on the Magic Mouse and trackpad.
- **Stage Manager and windows:** fast stage cycling with the strip hidden, and macOS window tiling for Fill, Center and Restore.
- **Live View** in the gesture editor demonstrates how to perform every gesture on both devices. Input Monitoring draws device-shaped surfaces with fading finger dots and can block gesture actions while you practise.
- **Tuning** is split into tabs for each device. **Settings…** (⌘,) opens General.
- **New default gestures** and an updated welcome tour.
- **A native Liquid Glass app icon**, rendered by macOS in Default, Dark, Clear and Tinted.
- The About section's **GitHub** button opens this project's repository.
- Removed: TrackPoint and the App Switcher. Apple Silicon only.

## BetterGlideTool 2.12.11 (local)

- New default gestures — what a new install starts with and what Reset to Defaults restores: trackpad three-finger clicks for Finder close and zoned screenshots, the four-finger maximize/full-screen ladder, Magic Mouse Stage Manager TipTaps and maximize/restore TipSwipes, and, in X, Safari, Brave, Craft and Helium, TipTaps for previous/next tab, swipes for new/close tab and flicks for Back/Forward on both devices, plus four-finger tap for middle click in Brave and Helium. The list is stored as Configuration-tab YAML and parsed by the same importer, so it matches an import exactly.
- The welcome tour describes the current app: gestures for the trackpad and Magic Mouse, Stage Manager, window tiling, tabs and shortcuts, per-app rules, Live View and tuning tabs. "Learn the moves" now cycles through the new starter gestures with the same Live View demonstration the gesture editor uses, and the menu bar page shows the actual menu bar icon (a hand over a trackpad) instead of a stand-in symbol.

## BetterGlideTool 2.12.10 (local)

- Tuning is split into tabs for each device, as in BetterTouchTool's settings, so each page fits without long scrolling. Trackpad: General (pointer speed, gesture sensitivity, Quick Setup), Swipes (distance, diagonal strictness, speed tiers), TipTaps (timing, sensitivity, spacing), Palm & Edges (accident protection and edge dead zones, now with each edge's slider here), Force Click (zones and preview), Repeating, and Advanced (raw values, shown open). Magic Mouse: General (on/off, connection, pointer speed, sensitivity), Taps & TipTaps, Swipes, Scrolling. Each device remembers its last tab. No setting was removed.

## BetterGlideTool 2.12.9 (local)

- BetterGlideTool ▸ Settings… (⌘,) opens the Preferences window on General. It used to open an empty "BetterGlideTool Settings" window, an unused placeholder scene that has been removed.

## BetterGlideTool 2.12.8 (local)

- Input Monitoring draws fingers the way BetterTouchTool's live view does: a solid purple dot per contact that fades and grows in as the finger lands, follows it, and fades out as it lifts — in the Input Monitoring tab and its Float window. The Float window itself is unchanged.
- New **Block Real Gesture Triggering** checkbox in Input Monitoring (tab and Float window), as in BetterTouchTool's live view: gestures are still recognised and appear in the Gesture Log, marked "Blocked", but their actions do not run, so you can practise them without side effects. It covers rule gestures, clicks, reciprocal swipes and continuous swipes, and applies only while an Input Monitoring view is open, so closing it never leaves gestures silently disabled.
- Builds no longer rewrite the committed compiled icon unless `AppIcon.icon` changed.

## BetterGlideTool 2.12.7 (local)

- A native Liquid Glass app icon. `assets/AppIcon.icon` is an Icon Composer document — a filled `hand.draw` glyph as a glass layer over a system-managed violet fill — compiled by Xcode's asset compiler into `Assets.car` and `CFBundleIconName`. macOS 26 and later render it like Apple's own icons in Default, Dark, Clear Light, Clear Dark and Tinted; macOS 13–15 get the matching flat `AppIcon.icns`. The old icon was a flat image with baked-in lighting, so it could not follow the dark or clear icon styles.
- `build.sh` compiles the icon when Xcode is installed, and otherwise uses the compiled copies in `assets/`.

## BetterGlideTool 2.12.6 (local)

- The Live View animates even with Reduce Motion on. With it on (as on this Mac), the view showed only a still of the finished stroke — and before 2.12.4, the old animation was still as well — so the demonstration never moved. BetterTouchTool plays its Live View regardless; the motion is the demonstration, and it plays only inside that box.
- Each demonstration loops as soon as its stroke has faded (0.6 s fade, 0.2 s pause) instead of after a fixed 2.6–2.9 s, so there is less blank time between repeats.

## BetterGlideTool 2.12.5 (local)

- The Live View only demonstrates how to perform the selected gesture, on a loop, as BetterTouchTool's does. It no longer switches to real input: with a hand on the Magic Mouse to work in Preferences, the resting finger kept replacing the demonstration. Real contacts stay in Input Monitoring.

## BetterGlideTool 2.12.4 (local)

- The Live View now demonstrates how to perform each gesture, drawn the way BetterTouchTool draws a circle: fingers land as purple dots, each finger's path builds up behind it, the finished stroke lingers with a faint mark where each finger lifted, then fades and repeats. Every gesture on both devices has its own script — taps and double-taps, clicks and force clicks with a press ripple, tap & hold, swipes in each direction and continuous left/right or up/down, circles, every TipTap and TipSwipe with its resting fingers, Magic Mouse regions (left, right, middle, above the Apple), trackpad corners and top/bottom taps, and trackpad zones. Touch the device and your own fingers take over in the same style; the box lights up when the gesture fires. With Reduce Motion, it shows the finished stroke still.
- The old animation (finger clusters, ghost trails, badges) is gone: the view went from 835 lines to about 230, plus the gesture scripts.

## BetterGlideTool 2.12.3 (local)

- One Live View, as in BetterTouchTool: the gesture editor's animated demonstration and 2.12.2's separate live panel are now a single black box, for both the trackpad and the Magic Mouse. Solid purple dots demonstrate the selected gesture — swiping, tapping, holding, resting while one finger taps or swipes, or circling a faint guide — and give way to your real fingers, with a short trail, while you touch the device; the box lights up when the gesture fires. The old speed and modifier badges, glass chassis and keycaps are gone (the summary line below still names speed, zone and modifier).
- Input Monitoring draws the device: a Magic Mouse–shaped oval for the Magic Mouse and a wide rounded trackpad for the trackpad, with contacts placed on that surface.

## BetterGlideTool 2.12.2 (local)

- Live View in the gesture editor, after BetterTouchTool's: beside the animated demo, a small black panel shows the selected device's fingers as they touch it, with a short fading trail (so a circle's path is visible as you draw it), and flashes "Triggered" when the selected gesture fires. It reads the existing Live Contacts feed, which only runs while a view is watching it, so nothing is processed while Preferences is closed.

## BetterGlideTool 2.12.1 (local)

- Circles now work as in BetterTouchTool. They used to fire only on lift, and only for a nearly closed, evenly round loop, so most circles drawn on the Magic Mouse missed. A circle now fires while you draw, once the finger's heading has turned 0.8 of a full turn (BetterTouchTool's "Required Circles Before Trigger"), and again for every further full turn. As in BetterTouchTool, a first trigger must come within 2.5 s of the touch, so a slowly curving scroll never counts. A sharp reversal or turning back the other way starts over, and the loop must span at least 6% of the surface on each axis. Applies to the Magic Mouse and the trackpad; a straight one-finger swipe bound alongside a circle is still judged on lift, as a flick on the Magic Mouse.
- Circles dispatch immediately instead of waiting 40 ms for a possible click.
- Action menu icons: Center Window had no icon (its symbol does not exist); window actions now draw as windows — corner snaps show their corner, Center and Fill show the window's placement, Maximize/Restore and Full Screen show their direction, and Stage Manager actions show the stage strip.

## BetterGlideTool 2.12.0 (local)

- Add 1 Finger Circle Clockwise and Counter-Clockwise to the Magic Mouse, as BetterTouchTool offers them. Circles were trackpad-only; the Magic Mouse now uses the same recogniser (a closed loop spanning at least 10% of each axis, judged on lift). One finger also scrolls a Magic Mouse, so the page keeps scrolling while you draw, and when a circle and a one-finger swipe are both bound, a straight path is chosen on lift and counts as a swipe only if it was a flick (2.0 surface widths per second), as without a circle binding.
- The rest of the requested set was already available on the Magic Mouse: TipTap Middle (2 Fingers Fix); 3 Finger Tap, Double-Tap, Click and Swipe Up/Down/Left/Right; and 1 Finger Tap Above Apple.

## BetterGlideTool 2.11.13 (local)

- Swipes made with the fingers a device scrolls with — one finger on the Magic Mouse, two on the trackpad — now fire on speed, as flicks, and never withhold the scroll. Panning a TradingView chart sideways used to send the swipe's ⌘←/⌘→ too: on the trackpad every slow pan did (the scroll itself always reached the app), and on the Magic Mouse any pan past 0.29. Recorded on TradingView with spoken cues, slow pans peaked at 0.44–0.75 surface widths per second on the Magic Mouse and 0.32–0.50 on the trackpad, flicks at 3.5–9.6 and 6.1–7.1. A flick now needs 2.0 widths per second over at least 45 ms and 0.12 of travel. Replayed through the recogniser, none of the 11 recorded pans fire and every recorded flick does. Magic Mouse swipes with two or more fingers, and trackpad swipes with one or three or more, are unchanged.

## BetterGlideTool 2.11.12 (local)

- One-finger Magic Mouse swipes no longer block scrolling. A one-finger swipe left/right withheld all horizontal scrolling while a finger was down, so a TradingView chart in Brave could not be panned. Recorded under BetterTouchTool on the same chart, the scroll passes the whole time and the swipe fires on top of it, once the finger has travelled 0.29 of the surface — every stroke that reached 0.291 fired, none that stopped at 0.288 or less. BetterGlideTool now does the same: one-finger swipes reserve no scroll axis, and on the Magic Mouse they fire at 0.29 (or the swipe distance, if larger). Replaying BetterTouchTool's recorded pans, BetterGlideTool fires on the same eight strokes within 30 ms and on none of the four shorter pans. Trackpad one-finger swipes are unchanged.

## BetterGlideTool 2.11.11 (local)

Tip swipes (rest two fingers, swipe the left one up or down), measured from recordings of 30 strokes with per-finger touch data, the scrolls that reached the app and the window's frame:

- Stop Tip swipes scrolling the page. After the swiping finger lifts, the resting fingers start a new native scroll about 60 ms later, carrying that finger's momentum: 1,400–3,800 points reached the app after every Tip swipe. Magic Mouse scrolling is now withheld while two or more fingers are down, through its momentum and for 250 ms after, whenever a gesture of two or more fingers is bound — as BetterTouchTool's "disable scrolling with 2+ fingers" setting does. One-finger scrolling is unaffected.
- Stop a landing finger from cancelling the Tip swipe it starts. As the swiping finger touched down, the sensor merged it with the resting finger beside it for one frame: that finger jumped 0.05 sideways at 1.7× its size, then returned. It read as the resting hand moving, so the hand had to settle again and the stroke 45 ms later was rejected, then scrolled. A jump that swells the contact is now ignored for up to 50 ms; a real shift of the resting hand still re-settles at once.
- Measured: Fill and Center resized the window on every recognised stroke, with no click interference; replaying all 30 strokes through the recogniser, every one is now recognised.

## BetterGlideTool 2.11.10 (local)

- Close the last scroll leak after Magic Mouse swipes. A re-recording under 2.11.9 showed scrolls still starting 6–10 ms after the last finger lifted — scroll events trail touch frames — and those looked like a new scroll, so they and their momentum reached the app. A fired swipe's axes now stay held for 250 ms after the lift, or until the next touch, and the momentum that follows stays with them.
- Drop 2.11.9's attribution of device-less momentum: a probe showed momentum events do name their device, so it changed nothing.
- 2.11.9 measured: TipTaps act 3–6 ms after the lift (BetterTouchTool about 35 ms); no swipes missed; shortcuts carried no stray modifiers.

## BetterGlideTool 2.11.9 (local)

Measured against BetterTouchTool by recording the same Magic Mouse gestures under each app (touch frames plus the keys and scrolls that reached apps):

- Stop the page scrolling on after a swipe. Momentum after a lift is generated by the window server and names no device, so the swipe filter waved it through: a swipe's own motion was withheld, then about half a second of its momentum still moved the page (20 of 25 swipes; BetterTouchTool leaked after 9 of 17). Device-less momentum is now attributed to the device whose scroll came last.
- When fingers lift one at a time after a swipe, the finger left behind starts a new native scroll. The swipe's axes now stay reserved until every finger has lifted.
- Recognise thumb-arc swipes. Magic Mouse "up" swipes ran 53–60° from horizontal; the 1.5× axis rule missed the shallower ones that BetterTouchTool accepted. Swipes, Tip swipes and one-finger swipes now need the main axis to lead by 1.2× (about 50°).
- Shortcuts carry exactly their own modifiers. A synthetic key inherited the modifiers of the previous synthetic shortcut, so ⌃⇧Tab from a TipTap followed by a ⌘T swipe arrived as ⌘⌃⇧T.
- TipTaps dispatch without the 40 ms wait meant for whole-hand taps, which a physical click can trail. Recorded TipTaps acted about 46 ms after the lift (BetterTouchTool: median about 35 ms); this removes 40 ms of that.

## BetterGlideTool 2.11.8 (local)

- Stop Magic Mouse swipes from scrolling the page after the gesture. A swipe reserved its scroll axes only while every finger stayed down, but macOS's scroll continues past that: the last finger keeps scrolling after the first lifts, and a momentum run keeps the page moving after the lift. Once a swipe has reserved an axis it now stays reserved for the rest of that native scroll, until macOS ends the momentum or a new scroll begins (with a one-second backstop). Other axes, and ordinary scrolling afterwards, pass as before.

## BetterGlideTool 2.11.7 (local)

- Center Window now uses macOS's own window tiling (Window ▸ Move & Resize ▸ Center) on macOS 15 and later. macOS remembers a window's size from before it was tiled, so Center after Fill returns the window to that size, centred beside the Stage Manager strip — as BetterTouchTool's "macOS Window Tiling" actions do. The old frame-only centring could not: after a full-screen fill it left the window unchanged. macOS 13–14 keep the old centring.
- New actions "Fill Screen (macOS Tiling)" and "Restore Previous Size (macOS Tiling)", reciprocal to each other. They fall back to Maximize and Restore before macOS 15. Maximize Window is unchanged.
- Tiling is driven through macOS's Globe+Control shortcuts, which are the same in every language; a window under the cursor is brought forward first. Verified live: Fill then Center returned a 2440-pt-wide window to 2441 pt, centred.

## BetterGlideTool 2.11.6 (local)

- Remove the App Switcher entirely: the 3-finger gesture switcher, its overlay, window previews and glass backdrop, the edge-scrub action, its haptic events and tuning, and its guide. Plain 3-finger left/right swipes on the trackpad are no longer reserved and can be assigned like any other gesture; 4-finger left/right were already assignable. "Activate Next/Previous App" keeps its most-recently-used order.
- Screen Recording is no longer used for anything and is no longer requested or documented.
- Older configs keep importing: "Next/Previous App (App Switcher)" gestures are dropped, an `app_switcher` edge is switched off (not replaced by a default), and the switcher's haptic and tuning keys are accepted and ignored.

## BetterGlideTool 2.11.5 (local)

- Make Stage Manager cycling respond like a native switch. Each tap used to hold the request queue until focus was confirmed — polled at 40, 100, 200 ms and later — so the next tap waited 130–220 ms, and quick taps queued behind each other. The queue is now released as soon as the switch is issued; confirmation continues in the background and reports to that tap's own gesture-log entry. The cycle cursor already skips the in-flight target, so early taps still advance.
- Find the window to focus through WindowServer alone (its owner and display), instead of listing every window on the system and then the target app's accessibility windows. Selecting the window inside its app (main, focused, raised) now runs after the switch and is skipped if a newer tap has started. The accessibility path remains when native focus is refused or WindowServer cannot name the window's display.
- Measured live on an external main display with the strip hidden: the next tap is free 20–28 ms after a tap (was 132–223 ms) and focus reaches the new stage in 49–78 ms; four taps 200 ms apart each switched within ~70 ms. Pressing the stage thumbnail instead was tested and does nothing while the strip is hidden.

## BetterGlideTool 2.11.4 (local)

- Fix Stage Manager cycling failing with "No stage buttons found" whenever a window covers the stage strip. Stage Manager then slides the strip off the screen edge (recorded at x = −240 on the main display), so every stage button's frame overlapped no display — or a neighbouring one — and discovery rejected them all. Stages are now assigned to the display of their per-display `sm.space` container (or an unnamed group sized to a display), falling back to the button's own frame only without one. Verified live: three forward cycles from a covered strip on an external main display.

## BetterGlideTool 2.11.3 (local)

- Fix 2.11.2's tap-to-click filter, which stopped working within seconds. It compared clicks with touches through a fixed offset between the multitouch frame clock and system uptime, but the two run at different rates (0.989× measured on a MacBook Air), so the error grew by about 10 ms a second and every tip lift soon looked too old to match. Clicks are now placed on the frame clock using the most recent frame. A recorded session puts every TipTap's click 6–26 ms after its tip lifts this way; 2.11.2's estimate passed the 250 ms window within about 30 seconds.

## BetterGlideTool 2.11.2 (local)

- Swallow the tap-to-click macOS generates for a TipTap's tapping finger. It arrives 30–90 ms after the tip lifts while the resting fingers stay down; left through, it clicked whatever was under the pointer (pausing videos, following links) and fired matching click rules. It is identical to a physical click in every event field, so it is told apart by timing against the touch data. A press with a finger held down, a click well after the lift, or one with no resting TipTap session still goes through untouched.
- Stop that click from cancelling the next TipTap. The recognizer read it as a physical press, so rapid taps were dropped or needed the resting fingers lifted. Replaying the recorded 2.10.24 session now fires seven TipTaps instead of six.
- Compare native button events with touch frames on one clock. The multitouch frame clock and system uptime have different origins, so the rearm-after-button recovery never matched and a TipTap could stay blocked until every finger lifted.

## BetterGlideTool 2.11.1 (local)

- Remove TrackPoint entirely: its preferences page, settings, touch feed, engine, cursor integrator, guide and illustrations. One-finger frames now reach the app only when edge controls, low-finger rules or Live Contacts need them, so ordinary cursor work stays inside the multitouch bridge again. Edge corners no longer widen around a TrackPoint zone.
- Remove the App Switcher preferences page and its settings. The switcher itself stays, fixed at the defaults it shipped with: three-finger left/right swipes are always reserved for it, Finder without windows is skipped, minimized windows are restored on release, and selection changes are not animated. It is still assignable to a trackpad edge. Step distance and debounce remain in `tuning` in the config file. The native ⌘Tab path is kept as the fallback when the overlay cannot be shown.
- Older config files keep importing: `app_switcher:` and `trackpoint:` blocks are accepted and ignored, and are no longer written on export.
- The in-app Screen Recording shortcut lived on the removed App Switcher page; grant it in System Settings → Privacy & Security → Screen Recording for window previews.

## BetterGlideTool 2.11.0 (local)

- Post edge scrolling as trackpad-style scroll events instead of mouse-wheel events: flagged continuous, with began/changed/ended phases while the finger is down and a separate momentum run for the coast. Point deltas carry exact fractional travel, so apps apply it as-is with their native rubber-banding instead of re-smoothing whole-pixel wheel steps. TrackPoint scrolling keeps the wheel path.
- Drive edge-scroll output from the display's own refresh (macOS 14+) instead of a fixed 120 Hz timer, which beat against 60 Hz and other non-120 Hz displays. macOS 13 keeps the timer. Lengthen the momentum coast from 0.25 s to 0.4 s, close to a native two-finger flick.
- Move volume, display brightness and keyboard backlight edge sliders in the system's quarter steps (64 levels instead of 16), still shown on the native indicator. Haptics fire once per full notch. Microphone and Night Shift steps are unchanged.
- Measure swipe speed on the trackpad's hardware frame timestamps rather than main-thread arrival time. Skip frames where one finger briefly drops out (up to 50 ms) instead of discarding the swipe; a sustained drop now re-targets the lower finger count when it has swipe rules. Only frames with real movement count toward the direction-coherence veto, so noise from resting fingers no longer blocks the swipe that follows.
- Release and DMG builds are Apple Silicon (arm64) only; Intel Macs are no longer a build target.
- A swipe frame that falls below three contacts still ends the touch session as before. Live feel on physical hardware still needs a hands-on check.

## BetterGlideTool 2.10.28 (local)

- Focus Stage Manager member windows through the existing exact-window WindowServer bridge, followed by AX focus/raise, instead of activating the entire application. Keep focus confirmation; API acceptance alone is not success.
- Resolve member-window display ownership through WindowServer before falling back to AX geometry. Inactive stages can have offscreen AX positions. Keep rejecting members owned by another display or with no identifiable display.
- Preserve cycle order through temporary strip omissions. Track requested and confirmed stages separately so a failed target does not trap every subsequent tap. Remember member IDs to recognize a manually focused stage even when it disappears from the recent strip.
- Batch stage-discovery attributes per accessibility node and begin focus confirmation after 40 ms instead of imposing a 120 ms minimum on every request. Preserve serialized requests and the bounded timeout.
- Show each monitored Stage Manager gesture's queued, discovering, activating, succeeded or failed result in the gesture log. Export correlated target/member IDs, display, focus before/after, route, discovery timing and total elapsed time. Complete the correct recorded event even if another gesture arrives or recording stops. Report queue overflow explicitly.
- Automated regressions cover transient stage lists, failed-target progression, direction changes, manual focus, display isolation and asynchronous result export. Physical Stage Manager behavior still needs a live check on the updated app.

## BetterGlideTool 2.10.27 (local)

- Redesign both Input Monitoring pages and floating panels from the supplied BetterTouchTool video: compact controls, a large dark touch surface with soft purple contact dots, and a newest-first gesture/action log on the right.
- Move raw contact IDs/coordinates/state and lift events into Details; keep Show IDs optional and put Input Diagnostics in a disclosure below the live view. Keep recording/export/copy controls available. Use contact size for dot size without claiming calibrated pressure or an unfiltered sensor stream.
- Log dispatched rules, physical-click rules, reciprocal/continuous actions and App Switcher gestures with times and target app names; preserve repeated identical gestures as separate entries. Bound the visible log to 80 entries and include recorded gesture events in contact exports. Clearing the visible log does not erase a recording.
- Coalesce live contact display updates at up to 60 Hz. Preserve independent device panels, nonactivating behavior and existing gesture recognition.

## BetterGlideTool 2.10.26 (local)

- Add Input Monitoring to the Trackpad and Magic Mouse sidebar sections. Move Trackpad Input and Live Contacts out of Tuning; move Magic Mouse input diagnostics to its new monitoring page while keeping enable/reconnect and sensitivity controls in Tuning.
- Add Magic Mouse live contact monitoring, a nonactivating floating panel, 15-second recordings, JSON export and Copy Readings. Each device has independent viewers, recording state, and saved panel placement. Recordings identify the device; mouse frames also identify the callback source so overlapping IDs on multiple mice do not become false transitions.
- Keep mouse monitoring available without an active app-specific gesture binding while mouse support and the gesture engine are enabled. Clear live contacts on disconnect/reconnect/stop. Gesture recognition behavior is unchanged.

## BetterGlideTool 2.10.25 (local)

- Fix paired trackpad TipTaps remaining blocked after a button interruption when the outer fingers exchange roles. After button-up, a stable shared middle contact and an opposite-side replacement can rearm the resting pair; the interrupted release emits no action and the new pair must settle.
- Validate quick returning fingers by full contact duration in paired Left/Right trackpad mode. A valid-duration tap is no longer rejected simply because it landed within 30 ms of the preceding release. Short bounces still fail the minimum-duration check; other modes retain their debounce behavior.
- Add a regression replay using the supplied 118-frame contact recording and explicit modeled button edges derived from its feedback, plus mirrored rotation and physical-click guard cases. The replay fails on 2.10.24 and recognizes six valid releases with this fix, excluding the interrupted release and a 40 ms bounce.
- Include system button samples and tracked trackpad button state in future Live Contacts JSON recordings, so they can be distinguished directly. Existing recordings remain readable. Native mouse clicks remain untouched.

## BetterGlideTool 2.10.24 (local)

- Add Live Contacts to Trackpad → Tuning with a normalized contact map, raw contact IDs/states, coordinates, contact size, recognizer roles, and recent inferred lift/landing events. Contact size is explicitly distinguished from pressure.
- Add a resizable, nonactivating floating panel that stays above ordinary app windows, including Brave, without taking keyboard focus. Monitoring remains available when the focused app has no low-finger bindings; closing the viewers restores normal bridge filtering.
- Add bounded 15-second contact recordings, JSON export and Copy Readings. Copy callback data safely, preserve all delivered frames for recordings and coalesce visual updates to 20 Hz. Closing all viewers or stopping input clears stale live contacts without deleting the captured recording.
- Add automated transition, recording limit, JSON precision, role, viewer lifetime, final release and native panel configuration checks. Gesture recognition behavior is unchanged.

## BetterGlideTool 2.10.23 (local)

- Correct paired trackpad TipTap Left/Right recognition to act on the outer finger that actually lifts from a settled three-finger hand. Alternating sides no longer treats that first lift merely as preparation for an additional tap cycle.
- Allow a stationary three-finger hold before the release without counting the entire resting period as an overlong tap. Preserve minimum settling/contact time, size, spacing, movement, click cancellation and bounce checks. Returning a finger and continuing to hold emit no action.
- Rebuild the resting pair from the two contacts still down after every recognized outer release. Apply this behavior when both two-fixed-finger Left and Right actions are assigned on trackpad; update the gesture help accordingly.
- Use the supplied 33-second BetterTouchTool demonstration and user-confirmed release semantics to correct prior test expectations. Synthetic alternating-release traces fail on 2.10.22 and pass with the change; video cannot supply exact hardware contact timing, IDs or pressure.

## BetterGlideTool 2.10.22 (local)

- Fix quick opposite-finger lifts being swallowed by the 60 ms anchor-dropout grace after the previously tapped finger has settled as a resting finger. Transfer that stable finger into the resting pair immediately and start the opposite tap timer on its next landing.
- Preserve release-triggered actions. Held/resting fingers emit no action and need no extra contact pressure; returning taps still satisfy their configured timing, movement and contact-size limits. Newly arriving replacements retain dropout protection.
- Reproduce the 2.10.21 failure with the user-described middle-finger-held rotation. Cover 25/45/90 ms lifts, 120 ms through three-second holds, both directions, same/new contact IDs, and light resting contact. Existing timeout, click, motion and dropout rejection tests remain active.

## BetterGlideTool 2.10.21 (local)

- Improve same-hand trackpad TipTap Left/Right rotation with the middle finger held down. Remember the last successful outer tap so its returning finger can become an anchor even without an all-three-down overlap frame, including fresh contact IDs after lift.
- Accept the opposite returning finger with a new ID near its previous position, then validate its fresh tap normally. Preserve the settled middle contact through the handoff instead of imposing another full anchor-settling delay.
- Require a successful prior outer tap, a stable middle contact and replacement, and a lift beyond the existing dropout grace. Reject middle-finger lifts, unrelated replacements, movement and cancelled/failed tap history; handoffs never execute an action.
- Add regressions reproducing the failure on 2.10.20, with repeated rotation in both directions, no/short/long overlap, fresh IDs on every landing, and negative dropout/movement checks.

## BetterGlideTool 2.10.20 (local)

- Fix trackpad TipTap lockout after native mouse-button events. Observe button-up as well as button-down, cancel the interrupted stroke, and rearm only after the button is released and the original resting chord remains alone. Fresh taps can repeat without lifting the resting fingers.
- Apply the same recovery to sampled button-state interruptions in the trackpad provider. Held buttons, held tapping fingers and unrelated hard cancellations cannot trigger recovery. Magic Mouse cancellation behavior stays unchanged. The event observer remains listen-only and returns native click events unchanged.
- Reproduce the reported button-event failure on 2.10.19; verify native left/right/other button lifetimes for all seven TipTaps, same-side repeats and sampled-state left/right alternation. Recognition checks and configuration round-trips pass; hardware fluidness still needs user verification.

## BetterGlideTool 2.10.19 (local)

- Recover a claimed trackpad TipTap session after an extra contact or tapping-contact ID change once only the original resting fingers remain. Cancel the interrupted stroke, then accept a fresh tap without requiring a whole-hand release. Resting fingers that moved must settle again.
- Report previously silent extra-contact, changed-tip, debounce, physical-button, invalid-frame and input-gap cancellations instead of retaining an old successful recognition.
- Preserve physical-click cancellation until full release, reject held tips and replacement resting fingers, and leave Magic Mouse recognition and saved tuning unchanged.
- Reproduce the repeat failure against 2.10.18 and cover recovery, interrupted strokes, anchor movement and button cancellation. These fixtures establish the code defect; the user’s supplied last-success diagnostic does not establish its cause on hardware.

## BetterGlideTool 2.10.18 (local)

- Make trackpad TipTap minimum spacing use surface distance, accepting vertically staggered fingers. Left/right selection uses the resting group center when no Middle TipTap is assigned; explicit Middle regions and maximum spacing limits remain effective.
- Allow 50% more bounded trackpad finger motion during TipTaps. Keep Magic Mouse geometry and movement behavior unchanged.
- Shorten debounce only for opposite-side trackpad taps, preserving same-side bounce protection.
- After a successful two-anchor trackpad TipTap, allow the stationary previous tapping finger to become an anchor when the opposite finger lifts beyond the 60 ms dropout grace and taps again. Transfers emit no action; the new tap must still satisfy duration, contact-size and movement checks.
- Add regressions that fail on the old implementation for staggered placement, rapid alternating taps, and same-hand outer-finger role exchange in both directions. Automated checks do not establish equivalence with BetterTouchTool on physical hardware.

## BetterGlideTool 2.10.17 (local)

- Package lighter trackpad TipTap defaults: all three contact-size thresholds 0.25, both minimum spacing values 0.02, maximum spacing 0.80. Trackpad TipTaps Reset to Defaults uses this profile. Existing explicit configuration values remain authoritative.
- Retain the 2.10.16 contact recovery fixes. Magic Mouse defaults and gesture timing are unchanged.

## BetterGlideTool 2.10.16 (local)

- Recover trackpad TipTaps from resting-contact gaps up to 60 ms and unambiguous nearby contact-ID changes. Apply to all seven TipTaps; keep tap duration, contact size, spacing and movement checks unchanged.
- A longer resting-contact loss cancels the pending tap, then lets the anchors settle and rearm without a whole-hand lift. The interrupted tapping finger must lift before rearming. Physical clicks and distant replacements cannot revive a cancelled tap.
- Preserve successful recognition feedback when a resting hand lifts normally after a completed trackpad TipTap.
- Regression tests reproduce the previous permanent cancellation, then cover same/new IDs, repeat taps, long loss, distant replacement, physical click and ordinary hand release for all seven variants. User confirmed 2.10.15 dispatches shortcuts; 2.10.16 recovery feel still needs a physical check.

## BetterGlideTool 2.10.15 (local)

- Stop native scroll events from vetoing a claimed trackpad TipTap; raw contact movement, duration and contact size remain authoritative. Ordinary taps still cancel on scrolling and physical trackpad clicks still cancel pending TipTaps. Ignore unrelated-device events in the trackpad observer.
- Add trackpad input diagnostics in Tuning, including app-scoped bindings, last recognition/rejection and action dispatch outcome. Preserve the last result when returning from the assigned app to preferences.
- Test native-event interference for all seven TipTaps, with physical click, moving-finger and ordinary-tap rejection checks. Live resolution of the reported failure remains unverified: the separate contact probe received no frames.

## BetterGlideTool 2.10.14 (local)

- Fix trackpad TipTaps losing stationary anchors: forward a bounded contact heartbeat while supplemental trackpad rules are enabled, so long rests no longer resemble an input timeout.
- Forward meaningful contact-size changes even when fingers stay still, allowing tap pressure to reach the recognizer. Preserve rate limits, final release delivery, saved tuning, and the movement-only filter when supplemental recognition is disabled.
- Exercise all seven trackpad TipTaps through the real C input filter into the Swift recognizer, including repeated taps with the same anchors. Add idle, throttling and disabled-feature regressions.

## BetterGlideTool 2.10.13 (local)

- Increase the menu-bar trackpad outline from 1.35pt to 1.8pt and its visible height to 14pt. Lower its top edge slightly and lift the hand by 0.5pt to align the visible icon with the neighboring menu-bar symbol. Preserve the native template tint and 20 × 18pt image canvas.

## BetterGlideTool 2.10.12 (local)

- Scope Stage Manager actions to the display containing the focused window, with pointer fallback only when no window is available. Filter both stage thumbnails and member windows, keep cycle history per display, and retain the original display for queued requests. Unknown/off-display geometry does not activate another display.
- Recover Magic Mouse two-anchor TipTaps from resting-contact dropout up to 60 ms and unambiguous nearby contact-ID changes. Longer loss cancels the pending tap and lets a settled chord rearm without lifting every finger. Physical clicks and distant/ambiguous replacements cannot inherit a stroke. Trackpad recognition and saved tuning values are unchanged.
- Add display-layout and contact-recovery regressions, including negative-coordinate monitors, focused window versus pointer, left/right repeat taps, long loss and physical-click cancellation.

## BetterGlideTool 2.10.11 (local)

- Fix the reported 2.10.10 Stage Manager crash: Accessibility focus setters can call this app's NSWindow code directly, so the entire window activation operation now runs on main. Discovery stays on the worker queue. Add a worker-to-main handoff regression.
- Skip an already focused stage when cycling, including when macOS exposes it in the stage list.
- Fix repeated TipTaps becoming blocked until all fingers lift after an application change during a stroke. Cancel the interrupted stroke while retaining its resting anchors. Add a regression that fails on 2.10.10 for one, two and three anchors; existing timing and sensitivity settings remain unchanged.

## BetterGlideTool 2.10.10 (local)

- Accept native stage groups that expose member window IDs without an AXPress thumbnail action. Resolve and focus the member AXWindow before activating its application.
- Verify focus against the requested group's member window IDs, so an unrelated window change cannot count as a successful stage switch.
- Allow time for the native transition before reporting failure, and report the actual activation route instead of telling users to enable already enabled settings. Show the latest Stage Manager result in Magic Mouse tuning.
- The user's 2.10.9 result confirms discovery succeeds but thumbnail activation does not switch focus. Live switching with the new member-window path still requires verification on the installed app.

## BetterGlideTool 2.10.9 (local)

- Add Stage Manager discovery through WindowManager's group/list/button hierarchy and AXWindowsIDs membership, alongside named strip/pile discovery. The old name-only filter missed unnamed native stage buttons.
- Use member window IDs to distinguish stages and maintain identity across strip rebuilds; stop combining WindowManager stages with Dock proxies. Do not invoke AXAddToStage, which would alter stage membership.
- Report scan errors and element counts when discovery fails instead of assuming Stage Manager is disabled. Add classification and stage identity regressions.

## BetterGlideTool 2.10.8 (local)

- Fix Magic Mouse TipTap spacing rejecting ordinary wide three-finger chords. Mouse spacing now uses the sideways gap to the nearest resting finger, rather than a diagonal to every resting finger. This applies both when arming and throughout the tap.
- Preserve configured minimum/maximum values, rest timing, contact size, motion and release safeguards. Existing configs automatically use the mouse geometry when loaded; trackpad distance semantics remain unchanged.
- Clarify the mouse spacing control and add left/right, repeated-tap, staggered-position, custom-limit and per-device configuration regressions. Hardware equivalence with BetterTouchTool is not claimed by these tests.

## BetterGlideTool 2.10.7 (local)

- Fix missed repeat TipTaps after resting fingers shift: the same identified anchors can settle again without lifting the entire hand. Movement during a tap still rejects that stroke; missing anchors, physical clicks and context cancellation keep their safeguards.
- Reject early/bouncing contacts for their entire contact lifetime so a held finger cannot arm later when a timing limit expires.
- Magic Mouse tuning shows the last TipTap recognition result, including timing, movement, contact-size and spacing rejection reasons. Expose the existing per-mouse spacing settings without changing saved values or the config format.
- Add recovery and rejection regressions for one, two and three resting fingers, including the user's two-anchor timing. Hardware feel and Stage Manager switching still require live verification.

## BetterGlideTool 2.10.6 (local)

- Fix one-anchor TipTap bindings claiming a sequentially placed two-finger resting chord and blocking a third-finger TipTap. A settled, stationary chord can now promote to a configured higher-finger gesture, without executing the lower-finger action. Reproduced with browser tab TipTaps alongside global Stage Manager TipTaps.
- Preserve rest-duration, motion, click and scroll safeguards; cover promotion, repeated strokes and refreshed contact IDs in regression checks.
- Correct stale gesture help that still instructed users to lift all resting fingers between TipTaps.

## BetterGlideTool 2.10.5 (local)

- Rearm one/two/three-anchor TipTaps after each tapping-finger release while keeping resting fingers down. Preserve completed-stroke anchors across app activation, but cancel in-progress strokes and resolve fresh taps against the new app’s rules. Keep existing timing and size thresholds.
- Prevent another device’s scrolling from cancelling a Magic Mouse TipTap.
- Search Stage Manager through exported windows, contents and children; prefer stable stage identifiers/window IDs over temporary accessibility-object hashes. Prioritize WindowManager and bound discovery off the main thread.
- Serialize rapid stage requests and confirm a focused-window change before advancing the cycle. Add Test Action and status to Stage Manager action options. Live Stage Manager switching still requires validation on the installed macOS build.

## BetterGlideTool 2.10.4 (local)

- Slightly enlarge the menu bar icon, use a semibold hand and a thicker trackpad outline, and compensate for the SF Symbol’s internal padding to vertically center the visible artwork.

## BetterGlideTool 2.10.3 (local)

- Narrow the menu bar trackpad outline and proportionally scale the hand inside an 18pt template image. Add balanced vertical padding to align the artwork with neighboring menu bar symbols.

## BetterGlideTool 2.10.2 (local)

- Replace the ripple app icon with the native `hand.draw` symbol on violet sampled from the requested reference. Include full-resolution and Retina ICNS artwork.
- Add a trackpad outline behind the menu bar hand using a cached template image that follows system menu tinting.
- Preserve separate unmasked foreground/background artwork for Icon Composer. This CLT-only build uses the static compatibility icon; native Liquid Glass compilation requires Xcode and is not included in this DMG.

## BetterGlideTool 2.10.1 (local)

- Audit all current gesture and device-tuning fields across export, import and disk reload, including per-device TipTap controls, scroll inversion, multiple app conditions and desktop-action options.
- Preserve numeric precision, rule/app order, escaped strings, inactive action payloads and keyboard hold/release modifiers. Support reordered gesture fields and literal single-quoted strings.
- Export backups atomically from current settings, including pending edits. Exporting to the live path no longer deletes its source.
- Reject malformed/unsupported imports before applying them; report save failures and restore prior settings. Preserve explicit per-edge values alongside legacy force-click margins.

## BetterGlideTool 2.10.0 (local)

- Trackpad adds clockwise/counter-clockwise one-finger circles, four corner clicks, three-finger Tap Top/Bottom, horizontal left-finger TipSwipes with two fixed fingers, four-finger tap/double tap, and left/right TipTaps with three fixed fingers. Existing click/force-click/swipe handling is retained.
- Independent TipTap sensitivity controls use the tapping contact's sensor size. Trackpad includes optional one-anchor movement and minimum/maximum spacing. Magic Mouse includes the sensitive-TipTap option, off by default to reduce accidental activation.
- New TipTap settings persist in configuration and reset per device. Existing timing sliders remain in effect. Mouse dragging/tap-region/tap-duration/double-tap controls were not expanded, per the requested scope.

- Magic Mouse adds Tap Middle, Tap Above Apple, and physical Middle Click to the one-finger menu. Existing general/left/right tap rules retain their assignments and use the requested names.
- Add Magic Mouse four-finger physical click and directional swipes, with a four-finger list filter.
- Regional taps resolve once using app, modifier, and window conditions. Within the same app scope, Above Apple wins over Middle, then side, then general Tap.
- New physical click bindings consume the matched native left-button sequence; unassigned clicks pass through. New gestures are opt-in, with no added dependency or repeating timer.

## BetterGlideTool 2.9.0 (local)

- Both device menus expose the requested three-finger tap, double-tap, click, four swipes, left/middle/right TipTap with two fixed fingers, and left-finger up/down TipSwipe.
- Trackpad three-finger swipes/clicks keep the existing recognizer; new taps and fixed-finger gestures use dedicated arbitration to avoid duplicate actions. App Switcher still reserves unmodified horizontal trackpad swipes while enabled.
- Two-fixed-finger gestures share each device's TipTap timing and require all fingers to lift before repeating. Their previews show the two resting fingers.
- Magic Mouse Tuning adds independent vertical/horizontal scroll inversion, preserving native momentum, event phases, and trackpad scrolling.
- Smooth scrolling, speed and response controls are intentionally omitted: Vorssaint's smoothing service bypasses Magic Mouse and trackpads. No third-party source or dependency was added.

## BetterGlideTool 2.8.0 (local)

- Add Spaces and Stage Manager action groups matching the requested action names, with stage position, multiple target apps, and optional window-title settings.
- Animation-free Space switching and window moves use guarded macOS private APIs. Rejected actions report an error; animated Space fallback is explicitly opt-in.
- Stage selection uses the visible Recent Apps accessibility elements; Stage Manager and Recent Apps must be enabled. Compatibility requires a hands-on check on the installed macOS version.
- TipTap now requires 250 ms of fixed-finger rest and an 80 ms minimum tap by default, rejecting brief accidental touches. Both times are independently adjustable for trackpad and Magic Mouse in Tuning.

## BetterGlideTool 2.7.1 (local)

- Fix Magic Mouse left/right swipe bindings blocking vertical scrolling in the assigned app. Scroll suppression now removes only the assigned axis and preserves the other axis, precision fields, momentum, and phase-only events.


## BetterGlideTool 2.7.0 (local)

- Separate Tuning pages with gesture sensitivity and native pointer-speed controls for Magic Mouse and trackpad; 1× restores captured original tracking.
- App-specific bindings take priority over Any App bindings regardless of list order. Mouse scroll reservation and low-finger recognition follow the active app, and switching apps cancels pending gestures.
- Mouse callbacks use dedicated device registrations rather than assuming the callback identifier equals the enumeration handle. Stopped input streams are retried by the existing health check.
- Mouse Tuning distinguishes connection, touch delivery, and the last recognized action. Physical validation is still required with BetterTouchTool closed.


## BetterGlideTool 2.6.0 (local)

- Shared gesture editor for Trackpad and Magic Mouse, with separate device rules.
- Two-finger double-tap, left/right TipTap, and physical click on both devices.
- Multiple app conditions per gesture, preserving existing single-app filters.
- Migration of existing Magic Mouse assignments into the shared rule format.
- Fresh Accessibility status checks, explicit recheck, and one automatic prompt instead of repeated launch prompts. Ad-hoc builds can still require a new macOS grant after replacement.


## 2.3.0

Performance release. The app switcher used to be the most expensive thing Glide
did; it is now roughly seven times cheaper, and the app wakes the CPU far less
when you are not touching the trackpad.

### App switcher CPU

Holding a swipe through the switcher was measured at about **67 ms of CPU per
selection step** with five apps open — well over half a core for as long as the
swipe lasted, and worse the more apps you had running. It is now about
**9.5 ms per step**.

The cause was SwiftUI spring animations on the panel. A spring re-renders the
view it is attached to on every display frame for as long as it runs, and
selection steps arrive every 100 ms (`appSwitcherDebounce`) while a spring takes
roughly 500 ms to settle — so the curves overlapped and the panel re-laid out
continuously for the whole gesture. One of those springs was attached to the
entire panel, so it animated the layout of the app rail, the window shelf, every
card, and the glass measurement together.

Shortening the curves did not help, because the cost is per animated layout
pass rather than per second of animation. Removing them did.

- Selection now applies instantly, as the system ⌘-Tab panel and AltTab both do.
  Cards still scale when selected; the change just is not tweened.
- **New setting: Preferences → App Switcher → Presentation → "Animate
  selection"**, off by default.
  Turn it on to get the springs back, at roughly double the CPU per step.
  Accessibility's *Reduce Motion* still disables them regardless.

Also in the switcher:

- Glass slab frames are snapped to whole points. They were arriving from a
  SwiftUI `GeometryReader` mid-animation carrying values like
  `160.44298885476712`, changing in the low bits every layout pass, and each
  distinct frame made the WindowServer rebuild its glass.
- The window shelf's glass view is now reused and hidden rather than destroyed
  and rebuilt. It appears and disappears whenever the selection crosses between
  a single-window app and a multi-window one, which is most steps, and building
  an `NSGlassEffectView` makes the WindowServer stand up a whole glass surface.
- Rail icons are rasterised once per app and cached. Every open previously
  redrew a 320x320 bitmap for every running app, synchronously, before the panel
  could appear.

### Battery

- The event-tap health check was a 5 second repeating timer created once at
  launch and never invalidated — about 17,000 wake-ups a day, and it kept firing
  even with gestures switched off or the machine asleep. It now lives and dies
  with the gesture engine and runs every 30 seconds with generous slack, so
  macOS can fold it into a wake it was already making.
- The Accessibility permission poll no longer runs forever. It polls briskly for
  the first minute after launch, then stops; a later grant is still picked up by
  the existing `didBecomeActive` observer.
- The TrackPoint's 120 Hz cursor timer now suspends itself while your finger
  rests inside the dead zone and resumes the moment you push back out. A steady
  push is unaffected, so the cursor still glides without depending on new
  frames.
- The global mouse-up handler no longer schedules main-queue work on every click
  system-wide while the engine is stopped.

Idle CPU with the engine running and no input measures 0.07%.
