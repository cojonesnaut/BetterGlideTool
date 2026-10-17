[← Back to manual](../USAGE.md)

# App Switcher

The App Switcher is a hold-and-swipe interface to browse and switch between active applications. It is always on, reserved on **3-finger left/right swipes**. It has no settings page; it runs with fixed defaults (see below).

**How it works:** Swipe left or right with 3 fingers to browse apps, and release to switch. Lift fingers away from the surface to cancel. Swiping up or down selects specific windows within multi-window applications.

<p align="center">
  <img src="../assets/gesture_app_switcher.svg" alt="App Switcher 2D Spatial Navigation Gesture" width="680">
</p>

### Why Vertical Swipes for Window Switching?

Standard macOS app switching (`⌘Tab`) operates strictly at the application level. When an application has multiple open windows (such as multiple browser windows, terminal sessions, or project documents), targeting a specific window requires secondary shortcuts (such as `⌘\``) or Mission Control.

BetterGlideTool introduces **2D spatial navigation**:
- **Horizontal swipes (left/right):** Cycle through running applications.
- **Vertical swipes (up/down):** Navigate the window deck of the currently highlighted app.

This enables direct switching to any active window in a single trackpad motion.

### How to Use Window Switching

1. **Initiate the switcher:** Swipe left or right with 3 fingers and keep fingers in contact with the trackpad.
2. **Select an app:** Swipe horizontally to highlight the target application.
3. **Select a window:** If the application has multiple open windows, swipe **up or down** with 3 fingers to cycle through its window deck. Live window previews appear when Screen Recording permission is active; application icons display otherwise.
<br><img src="../assets/gestures/app_switcher.svg" width="320">
4. **Commit:** Release all fingers to focus the selected window immediately.
5. **Cancel:** Lift all fingers without making a selection.

The switcher shows its own overlay with live window thumbnails or app icons. If the overlay cannot be shown, it falls back to native `⌘Tab` events handled by macOS.

Because the switcher reserves 3-finger horizontal swipes, custom gestures on this trigger require a modifier key (such as Shift). The editor indicates when this applies.

Fixed behavior: Finder is skipped when it has no open windows, minimized windows of the selected app are restored on release, and selection changes are not animated (keeping CPU use low during swipes). The step distance and debounce between apps can still be adjusted in the configuration file (`tuning.app_switcher_step_threshold` and `tuning.app_switcher_debounce`). It can also be assigned to a trackpad edge in **Preferences → Edge Controls**.

---
[← Previous: Global keyboard shortcuts](04-keyboard-shortcuts.md) · [Back to manual](../USAGE.md) · [Next: Tuning & precision controls →](07-tuning.md)
