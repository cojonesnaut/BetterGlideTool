import Foundation

/// The gestures a new install starts with, and what "Reset to Defaults"
/// restores. Kept in the same YAML the Configuration tab imports and exports,
/// and parsed by the same importer, so the defaults can never drift from what
/// an import of this list would produce.
enum DefaultGestures {
    static let rules: [GestureRule] = GlideConfigParser.parse(yaml: yaml)?.toRules() ?? []

    static let yaml = #"""
touchpad:
  gesture_schema_version: 1
  gestures:

    # 3-finger click → Close Window
    - type: click
      device: trackpad
      app_filters:
        - "com.apple.finder"
      fingers: 3
      action: "Close Window"
      app_filter: "com.apple.finder"

    # 3-finger force_click → Screenshot (Full → Clipboard)
    - type: force_click
      device: trackpad
      fingers: 3
      action: "Screenshot (Full → Clipboard)"
      zone: top_left
      app_filter: null

    # 3-finger force_click → Screenshot (Area → Clipboard)
    - type: force_click
      device: trackpad
      fingers: 3
      action: "Screenshot (Area → Clipboard)"
      zone: top_right
      app_filter: null

    # 4-finger swipe up (normal) → Maximize Window
    - type: swipe
      device: trackpad
      direction: up
      fingers: 4
      speed: normal
      action: "Maximize Window"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false

    # 4-finger swipe up (normal) → Enter Fullscreen
    - type: swipe
      device: trackpad
      direction: up
      fingers: 4
      speed: normal
      action: "Enter Fullscreen"
      window_state: maximized
      app_filter: null
      app_path: null
      reciprocal: true
      continuous: false

    # 4-finger swipe down (normal) → Restore/Un-maximize Window
    - type: swipe
      device: trackpad
      direction: down
      fingers: 4
      speed: normal
      action: "Restore/Un-maximize Window"
      window_state: maximized
      app_filter: null
      app_path: null
      reciprocal: true
      continuous: false

    # 4-finger swipe down (normal) → Exit Fullscreen
    - type: swipe
      device: trackpad
      direction: down
      fingers: 4
      speed: normal
      action: "Exit Fullscreen"
      window_state: fullscreen
      app_filter: null
      app_path: null
      reciprocal: true
      continuous: false

    # 3-finger tip_tap_two_left → Stage Manager: Cycle Through Stages (Forward)
    - type: tip_tap_two_left
      device: magicMouse
      fingers: 3
      action: "Stage Manager: Cycle Through Stages (Forward)"
      app_filter: null
      stage_position: 1
      stage_window_title: ""
      allow_animated_fallback: false

    # 3-finger tip_tap_two_right → Stage Manager: Cycle Through Stages (Backwards)
    - type: tip_tap_two_right
      device: magicMouse
      fingers: 3
      action: "Stage Manager: Cycle Through Stages (Backwards)"
      app_filter: null
      stage_position: 1
      stage_window_title: ""
      allow_animated_fallback: false

    # 3-finger tip_swipe_left_up → Maximize Window
    - type: tip_swipe_left_up
      device: magicMouse
      fingers: 3
      action: "Maximize Window"
      app_filter: null

    # 3-finger tip_swipe_left_down → Restore/Un-maximize Window
    - type: tip_swipe_left_down
      device: magicMouse
      fingers: 3
      action: "Restore/Un-maximize Window"
      app_filter: null

    # 1-finger swipe right (normal) → Keyboard Shortcut…
    - type: swipe
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: right
      fingers: 1
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 123
      shortcut_modifiers:
        - command

    # 1-finger swipe left (normal) → Keyboard Shortcut…
    - type: swipe
      name: "Shortcut: ⌘Right"
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: left
      fingers: 1
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 124
      shortcut_modifiers:
        - command

    # 2-finger tip_tap_left → Keyboard Shortcut…
    - type: tip_tap_left
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      fingers: 2
      action: "Keyboard Shortcut…"
      app_filter: null
      shortcut_key_code: 48
      shortcut_modifiers:
        - shift
        - control

    # 2-finger tip_tap_right → Keyboard Shortcut…
    - type: tip_tap_right
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      fingers: 2
      action: "Keyboard Shortcut…"
      app_filter: null
      shortcut_key_code: 48
      shortcut_modifiers:
        - control

    # 2-finger swipe down (normal) → Keyboard Shortcut…
    - type: swipe
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: down
      fingers: 2
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 13
      shortcut_modifiers:
        - command

    # 2-finger swipe up (normal) → Keyboard Shortcut…
    - type: swipe
      device: magicMouse
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: up
      fingers: 2
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 17
      shortcut_modifiers:
        - command

    # 2-finger swipe right (normal) → Keyboard Shortcut…
    - type: swipe
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: right
      fingers: 2
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 123
      shortcut_modifiers:
        - command

    # 2-finger swipe left (normal) → Keyboard Shortcut…
    - type: swipe
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: left
      fingers: 2
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 124
      shortcut_modifiers:
        - command

    # 3-finger tip_tap_two_left → Keyboard Shortcut…
    - type: tip_tap_two_left
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      fingers: 3
      action: "Keyboard Shortcut…"
      app_filter: null
      shortcut_key_code: 48
      shortcut_modifiers:
        - shift
        - control

    # 3-finger tip_tap_two_right → Keyboard Shortcut…
    - type: tip_tap_two_right
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      fingers: 3
      action: "Keyboard Shortcut…"
      app_filter: null
      shortcut_key_code: 48
      shortcut_modifiers:
        - control

    # 3-finger swipe down (normal) → Keyboard Shortcut…
    - type: swipe
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: down
      fingers: 3
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 13
      shortcut_modifiers:
        - command

    # 3-finger swipe up (normal) → Keyboard Shortcut…
    - type: swipe
      device: trackpad
      app_filters:
        - "app.parall.mac.8aafa524c5a9d90f51c2078b1ce4523c"
        - "com.apple.Safari"
        - "com.brave.Browser"
        - "com.lukilabs.lukiapp"
        - "net.imput.helium"
      direction: up
      fingers: 3
      speed: normal
      action: "Keyboard Shortcut…"
      app_filter: null
      app_path: null
      reciprocal: false
      continuous: false
      shortcut_key_code: 17
      shortcut_modifiers:
        - command

    # 4-finger tap → Middle Click
    - type: tap
      device: trackpad
      app_filters:
        - "com.brave.Browser"
      fingers: 4
      action: "Middle Click"
      app_filter: null

    # 4-finger tap → Middle Click
    - type: tap
      device: trackpad
      app_filters:
        - "net.imput.helium"
      fingers: 4
      action: "Middle Click"
      app_filter: null
"""#
}
