# GestureKeys

A small, personal BetterTouchTool-style menu bar app: bind trackpad gestures to keyboard shortcuts,
system actions or shell commands.

- **Multi-finger swipes**: 2–5 fingers × up/down/left/right
- **Multi-finger rotation**: 2–5 fingers turned like a knob, left (counterclockwise) or right (clockwise). Since the
  hand stays in place, it doesn't set off macOS's own swipes the way 5-finger swipes can. Lift to fire the rotation
  itself, or keep the fingers down and drag ↑ ↓ ← → for four more commands per direction (8 per finger count).
- **Multi-finger taps**: 2–5 fingers, single, double, triple or 4× taps. A single tap only waits for a possible
  second tap when a double/triple tap with the same finger count is bound.
- **Drawn shapes**: hold a modifier (⌥ by default) and draw with one finger. It comes with circles, check, V, ^, Z, N, L,
  triangle and square, and you can record your own.
- **System actions** for inputs a keyboard doesn't have: Back / Forward (mouse side buttons), middle click,
  play/pause, next/previous track, volume, brightness, sleep display, Mission Control, App Exposé, Show Desktop.
  The last three replace the macOS gestures you turn off to use 4-finger swipes.
- **Per-app bindings**: a binding can be limited to one app; app-specific bindings win over "All apps".
- **Profiles**: separate sets of bindings (e.g. Work, Music, Presenting). Switch from the menu bar, the Gestures tab,
  or a gesture bound to *System Action › Next Profile*.

## Build & run

Needs only the Xcode Command Line Tools (`xcode-select --install`), macOS 14+.

```sh
make run            # build build/GestureKeys.app and launch it
make install        # copy to /Applications and launch
make test           # core logic self-test (swift run SelfTest)
make debug-touches  # print raw touches + detected gestures in the terminal
```

On first launch, grant **Accessibility** permission when prompted (System Settings › Privacy & Security ›
Accessibility). Without it macOS silently drops the synthesized key presses.

### Rebuilding and the Accessibility permission

macOS ties the Accessibility grant to the app's code signature. If the signature changes with each build
(ad-hoc signing), every rebuild looks like a new app and the app asks for permission again even though the
toggle looks on. To avoid this, run once per machine:

```sh
scripts/make-signing-identity.sh   # self-signed "GestureKeys Dev" cert in your login keychain
```

`build-app.sh` uses that certificate automatically, so the grant survives rebuilds. Without it the build falls
back to ad-hoc signing and prints a warning.

If it keeps asking even though permission is granted, an old entry is stuck. Clear it and grant again:

```sh
tccutil reset Accessibility com.donjmilligan.GestureKeys
```

## Using it

Click the menu bar icon › **Settings…**

1. **Gestures tab**: perform a gesture on the trackpad. It shows up as *Last gesture*, and **Bind Last
   Gesture…** opens the editor with it filled in. Click the shortcut field and press the keys to send.
2. **Shapes tab**: hold the activator and draw to see what's recognized and how confidently. To add a
   shape, type a name, click **Record New Shape**, then hold the activator and draw it. Add 2–3 samples per shape,
   drawn the way you naturally draw it. Direction and starting point matter (the green dot in a preview marks
   the start).
3. **Preferences**: drawing activator keys, match threshold, swipe distance, tap timing, launch at login.

### Turn off conflicting macOS gestures

GestureKeys can't stop macOS's own gestures from firing. In **System Settings › Trackpad › More Gestures**, turn off the
ones that use the finger counts you bind:

| You bind | Turn off |
| --- | --- |
| 4-finger swipes | Swipe between full-screen apps, Mission Control, App Exposé (if set to 4 fingers) |
| 5-finger swipes | Usually fine; if Mission Control or Spaces still trigger, turn those off too (or use 5-finger rotation instead) |
| 3-finger swipes | Three-finger drag (Accessibility › Pointer Control) and 3-finger swipes |
| 4/5-finger pinch | Launchpad, Show Desktop |

## Icon

The app and menu bar icons are generated at build time from `Resources/AppIcon.png` (the Drum Foundary logo) by
`scripts/make-icons.swift`. Replace that PNG (square, ideally 1024 px, transparent background) to change both.

## Config files

`~/Library/Application Support/GestureKeys/`

- `config.json`: settings, profiles and their bindings
- `shapes.json`: shape templates (64 normalized points per sample)

Both are pretty-printed JSON. Edit them only while the app is quit. If one fails to parse, it's moved aside as
`*.broken-<timestamp>` and the app starts with defaults.

Bindings live in `profiles[].bindings`; `activeProfileID` picks the profile in use. A config from before profiles
is moved into a profile called "Default" on first launch. Example bindings (5-finger swipe down → ⌘W; draw a check
in Safari → run a command):

```json
{
  "action": { "keyboardShortcut": { "combo": { "keyCode": 13, "modifiers": 8 } } },
  "enabled": true,
  "id": "BEF1AB03-B65E-43D0-A577-4EE099956A17",
  "trigger": { "swipe": { "direction": "down", "fingers": 5 } }
},
{
  "action": { "shellCommand": { "command": "open -a Notes" } },
  "appBundleID": "com.apple.Safari",
  "enabled": true,
  "id": "0C2F57D4-6A0B-4F7E-9A51-3C1B0E2D9F10",
  "trigger": { "shape": { "name": "Check ✓" } }
}
```

`keyCode` is a macOS virtual key code (W is 13). `modifiers` is a bitmask: ⌃ 1, ⌥ 2, ⇧ 4, ⌘ 8, fn 16.
System actions look like `{ "system": { "action": "back" } }`; the names are the cases of `SystemAction` in
`Sources/GestureCore/Model.swift`. Leave out `appBundleID` to apply a binding in every app. Other triggers look like `{ "tap": { "fingers": 3, "taps": 2 } }` (a 3-finger double tap) and
`{ "rotate": { "direction": "right", "fingers": 5, "then": "up" } }` (leave out `then` for a plain rotation).

## How it works

| Piece | File |
| --- | --- |
| Raw touch data from Apple's private `MultitouchSupport.framework` (loaded with `dlopen`, as BTT, Jitouch etc. do) | `Sources/CMultitouch` |
| Frames → swipe / rotate / tap / drawing events (per trackpad, measured in millimetres) | `Sources/GestureCore/GestureEngine.swift` |
| Shape recognition: a rotation-sensitive variant of the $1 Unistroke Recognizer | `Sources/GestureCore/ShapeRecognizer.swift` |
| Synthesizing key presses, mouse buttons and media keys (`CGEvent`), Mission Control etc. (private Dock call), shell commands | `Sources/GestureKeys/ActionRunner.swift` |
| Glue: per-app lookup, drawing overlay, HUD, cursor freeze while drawing | `Sources/GestureKeys/GestureController.swift` |

Since `MultitouchSupport` is private API, a future macOS update could break it. The touch struct layout is checked at
compile time (`CMultitouch.c`), and `make debug-touches` is the quickest way to see whether touches still arrive.
