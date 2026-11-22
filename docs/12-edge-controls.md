[← Back to manual](../USAGE.md)

# Trackpad Edge Controls

Trackpad Edge Controls turns the physical outer rim of your trackpad into precision hardware sliders. Sliding a single finger along any edge allows smooth adjustment of system volume, display brightness, keyboard backlight, microphone gain, Night Shift warmth, scrolling, or music playback. A double-tap in any of the four corners can run an action of its own.

Configure everything in **Preferences → Edge Controls**. The page opens on a trackpad diagram showing what each edge and corner does, with the live volume and brightness filling the strips that control them; settings are sorted into categories along the top (Edges, Corners, While Sliding, Feedback), and clicking an edge or corner on the diagram opens its category. **Swap Sides** under the diagram swaps the left and right edge actions. Edge Controls can also be switched on and off from the menu bar menu (**Enable Edge Controls**).

## How It Works

1. **Physical Rim Sliders:** Each of the four edges (Left, Right, Top, Bottom) can be mapped to a dedicated action:
   - **Right Edge** *(default: System Volume):* Slide up to raise volume; slide down to lower volume.
   - **Left Edge** *(default: Display Brightness):* Slide up to brighten the display; slide down to dim it.
   - **Top / Bottom Edges** *(optional):* Assign to Keyboard Backlight, Microphone Input Gain, Night Shift, Scroll, or Media Strip.
2. **Native OSD Bezels:** BetterGlideTool triggers native macOS system display bezels (identical to the overlays displayed by physical media keys). This operates with 0.0% CPU overhead and zero latency.
3. **Tactile Haptic Ticks:** Each adjustment increment delivers a tactile tick via the trackpad Taptic Engine. **Feedback → Haptic Feedback** sets it to Off, Light, Medium (default) or Strong.

## Media Strip

Assigning an edge to **Media Strip**, usually the bottom one, turns it into playback controls:

- **Swipe along it** to skip a track: right (or up, on a side edge) for the next track, left or down for the previous one. One swipe skips one track, once the finger has travelled 15 mm. **Reverse Media Swipe** flips the direction.
- **Double-tap it** to play or pause. Only taps within 8 mm of the edge count, so ordinary taps near the bottom of the pad still click. **Double-Tap to Play or Pause** turns this off.

## Corners

Each corner can run an action on a double-tap: mute, play/pause, next or previous track, Mission Control, App Exposé, Show Desktop, Notification Center, Spotlight, an area screenshot, the screenshot toolbar, Lock Screen, or one of your Shortcuts. Corners are 12 mm squares, the same area edge slides keep clear of, so a corner tap and an edge slide never compete.

A tap is a touch that lifts within 0.3 s without moving more than 3 mm, and the two taps must land in the same corner within 0.45 s. With Tap to Click on, macOS would turn each tap into a click wherever the pointer is; BetterGlideTool swallows those clicks for taps in a corner that has an action (and on the media strip), so the double-tap never clicks anything. A physical click in a corner still works normally.

## While Sliding

| Setting | Meaning |
|---|---|
| **Where Side Slides Can Start** | Full Edge (default), or only the top or bottom ¾, half or quarter of the left and right edges. Only the landing point is checked; once a slide starts it can run the whole edge. |
| **Precise Sliding** | On (default): volume and brightness move in the system's quarter steps. Off: a full notch at a time. |
| **Only While Holding Fn or Option** | Slides only start when Fn or Option is held as the finger lands. Off by default. |
| **Pause While Typing** | The edges ignore a touch that lands within half a second of a key press, so a palm resting on the trackpad while typing never changes anything. On by default. |
| **Edge Width** | How far in from the edge a slide can start (see below). |
| **Sensitivity** | How much a slide changes volume, brightness and the other stepped controls for the same travel (0.5×–2×, default 1×). Scrolling has its own **Scroll Speed**. |
| **Start Distance** | How far you slide before the edge takes over (see below). |

## Edge Scrolling

Assigning an edge to **Scroll** turns that rim into a scroll strip, the way edge scrolling worked on older Windows trackpads.

**Every edge scrolls vertically,** including the top and bottom. A horizontal rim acts as a forward/back strip rather than a horizontal scrollbar, since vertical is what people actually want to scroll. Sliding up a side edge, or right along a top or bottom edge, moves forward through the document.

Direction matches the system's natural scrolling by default: content follows your finger, the same as a two-finger scroll. **Reverse Scroll Direction** switches to the scrollbar convention.

### What makes it smooth

Multitouch frames arrive at uneven intervals and each position carries a little sensor noise, so emitting each frame's travel directly reads as judder even when your finger moved evenly. BetterGlideTool buffers the travel and releases it on a steady 120 Hz clock, which cuts tick-to-tick judder by roughly 8× at a cost of about 22 ms of delay. Total distance is unchanged, so **Scroll Speed** still means exactly what it says.

Scrolling is also the one edge action with no haptic ticks and no quantization. The others are notched, moving in discrete steps with a tap for each; scrolling reads travel continuously, which is both what makes it smooth and what keeps it from buzzing the Taptic Engine every frame.

### Momentum

With **Glide After Lifting Your Finger** enabled, a flick keeps scrolling and coasts to a stop over about a second.

Momentum has to be earned: it only engages above roughly 25 mm/s of finger speed. A slow, deliberate drag settles the moment you lift, so being careful never costs you an overshoot. A finger that comes to rest before lifting never glides at all. The threshold is measured in finger travel, so it keeps meaning the same thing when you change Scroll Speed.

### Settings

Tune these under **Preferences → Edge Controls → Edge Scrolling**, shown when an edge is set to Scroll:

| Setting | Meaning |
|---|---|
| **Scroll Speed** | Points of scroll per millimetre of finger travel (default 26, range 5–80). Lower is more precise; higher covers a long document in a single slide. |
| **Glide After Lifting Your Finger** | Whether a flick coasts to a stop (default on). Turn it off for tighter control over exactly where you land. |
| **Reverse Scroll Direction** | Off (default) is natural scrolling: sliding up a side edge, or right along a top or bottom edge, moves down the page. On gives the scrollbar convention. |



## The pointer holds still

Edge gestures run on a single contact, which means the finger working the slider is the same one macOS reads as pointer movement. Without intervention the cursor drifts off toward whichever screen edge you are sliding along.

So once an edge gesture takes over, BetterGlideTool freezes the pointer until you lift. This applies to every edge action, not just scrolling. For scrolling it also decides *where* the scroll lands, since scroll events go to the window under the pointer — freezing it keeps the scroll on the window it started over.

The freeze begins only when the gesture actually commits (see below). A touch near the rim that never commits leaves the cursor completely alone, so nothing is lost if you were only moving the pointer.

Freezing alone is not quite enough, though. The travel that *earned* the commit has already moved the cursor by then, and those events have been delivered — suppression cannot take them back. So on commit BetterGlideTool also puts the cursor back where your finger first landed. Without that, the pointer still crept a few millimetres' worth on every gesture, which is the drift you would otherwise keep seeing.

## Accidental Trigger Protection

Edge Controls apply several independent filters to separate rim gestures from ordinary pointer navigation. A touch has to pass all of them:

- **Edge-Origin Only:** Touches must start on the outer perimeter. A contact that begins on the main trackpad surface is excluded from edge actions for its entire lifetime, so sweeping into an edge never triggers anything.
- **Rim Proximity, with hysteresis:** The finger must start within the border zone (**Edge Width**, default 12 mm, adjustable 3–30 mm). Once a gesture has committed it keeps 10 mm more room than that before being dropped — see below.
- **No Corners:** A gesture cannot start in a corner. With any real margin the four edge zones overlap there, so "which edge is this?" has no correct answer. The exclusion is at least 12 mm, and always at least as deep as the margin, which is what makes the four zones provably non-overlapping.
- **Start Distance:** The finger must slide a minimum distance *along* the edge before anything fires (**Start Distance**, default 4 mm). This is the main dial if edge controls are triggering when you did not mean them to.
- **Direction Purity:** Travel along the edge must be at least twice any drift across it, so the slide has to run roughly parallel to the rim — within about 27°. A diagonal sweep away from the edge keeps steering the cursor no matter how much along-edge distance it covers, which is the most common source of accidental triggers.
- **Commit Near the Rim:** More than 3 mm of inward drift before committing cancels the gesture outright. The decision gets made close to where your finger landed, rather than after it has wandered.
- **Single-Contact Isolation:** Only single-finger touches are considered. A second finger immediately returns handling to native macOS gestures.

### Dropped frames

The sensor sometimes reports no contact for a frame or two while a finger is still sliding, most often right at the rim. A committed slide is held through a gap of up to 120 ms with the pointer still frozen; if the finger is seen again in time (same contact, or a new one within 8 mm of where the slide was) the slide simply carries on, otherwise it ends as if the finger had lifted when the gap began. Taps are not held, so a double-tap is never slower, and an edge scroll hands off to its glide at once, since the glide is judged on the finger's speed at the moment it lifts.

### Easier to keep than to start

Entering a gesture is strict, so edge controls stay out of the way of cursor work. Staying in one is deliberately not, because by then the finger has already proved its intent with a straight slide along the rim, and the cost of being wrong has flipped: a gesture dropped halfway through is worse than one held slightly too long.

This matters more than it sounds. Fingers do not track straight — sliding along a long edge, or along the top where the hand has to reach over, wanders several millimetres inward. If a committed gesture were held to the same threshold it entered on, it would be dropped mid-slide, and because dropping it also releases the pointer, the visible symptom is the cursor lurching back to life partway through the gesture. So a committed gesture gets 10 mm of extra depth.

The `--diag-edges` diagnostic reports this directly, per edge: how close your finger got, what fraction of the slide the gesture was held for, how far inward it drifted while held, and how many times it was dropped mid-slide.

### Tuning it

Both dials live under **Preferences → Edge Controls → While Sliding**:

| Setting | Meaning |
|---|---|
| **Edge Width** | How far inward from the rim a gesture may begin, and how far it may drift before being handed back (default 12 mm, range 3–30 mm). A deeper margin also keeps a long slide alive instead of cancelling partway, which itself shows up as the cursor starting to move again. |
| **Start Distance** | How far you must slide along an edge before it takes over (default 4 mm, range 2–15 mm). |

If edge controls fire when you did not intend them to, raise **Start Distance** first — it is the most direct lever. If gestures cancel partway through a slide, raise **Edge Width**. If they feel slow or reluctant to engage, move both the other way.

Note that raising the margin also deepens the corner exclusion, since the two are tied together to keep the edge zones from overlapping. At the maximum 30 mm margin the left and right edges still leave about 38 mm of usable strip.

---
[← Previous: Troubleshooting](11-troubleshooting.md) · [Back to manual](../USAGE.md)
