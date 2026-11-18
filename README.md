# MagicGestures

Custom gestures for the Apple Magic Mouse on macOS.

macOS only offers a handful of built-in Magic Mouse gestures. MagicGestures is a small menu bar app that reads the raw touches on the mouse's surface, recognises taps, swipes and edge slides, and runs whatever action you bind to them: a keyboard shortcut, a media key, a shell command or a mouse click.

## Requirements

- A Mac with a Magic Mouse connected
- Xcode or the Xcode Command Line Tools, for the Swift compiler (`xcode-select --install`)
- Developed and tested on macOS 27 on Apple silicon; the build targets whatever macOS you compile on

## Install

```sh
git clone https://github.com/ibretsam/MagicGestures.git
cd MagicGestures
sh install.sh
```

`install.sh` does four things:

1. Builds `MagicGestures.app` from `main.swift`.
2. Copies it to `/Applications`.
3. Copies the gestures in this repository's `config.json` to `~/.config/magicgestures/config.json`, unless you already have a config there.
4. Registers a launch agent so the app starts at login, and starts it.

Then grant it **Accessibility access** when macOS asks, or do it by hand in System Settings → Privacy & Security → Accessibility. Without it, gestures are recognised but no keys are sent and scrolling isn't blocked during edge slides. The menu shows a warning line until access is granted.

If you have an Apple Development signing certificate, the build uses it, and the Accessibility grant survives rebuilds. Otherwise the app is ad-hoc signed and macOS asks for access again after each rebuild: remove the old MagicGestures entry in the Accessibility list and add it again.

To build without installing, run `sh build.sh` and open the resulting `MagicGestures.app`.

## Uninstall

```sh
sh uninstall.sh
```

This removes the app and the login item. Your gestures in `~/.config/magicgestures` are kept; delete that folder to remove them too.

## Using it

MagicGestures lives in the menu bar as a hand icon. Its menu has:

| Item | What it does |
|---|---|
| Last gesture | Shows the most recent gesture it recognised, even one with nothing bound. Useful for learning gesture names. |
| Settings… | Opens the window for adding, editing and removing gestures, and for tuning. |
| Show Touch Viewer | Opens a live top-down view of the mouse showing each finger as you touch it. |
| Reset Viewer Outline | Starts the viewer's learned mouse outline over. |
| Pause / Resume | Stops actions from running without quitting. |
| Edit Config… | Opens the config file in TextEdit. |
| Reload Config | Re-reads the config file. It is also re-read automatically within a few seconds of a change. |
| Quit MagicGestures | Stops the app until the next login. |

### Adding a gesture

1. Open **Settings…** and press **Add Gesture…**.
2. Pick the gesture from the list, or press **Detect from Mouse** and perform it on the mouse.
3. Choose the action type and fill it in. For a shortcut you can press **Record** and then the key combination.
4. Press **Save**. It takes effect immediately.

"Detect from Mouse" can't detect a slide on an edge that has nothing bound yet; choose edge slides from the list.

### Gestures

| Name | Gesture |
|---|---|
| `tap1-left`, `tap1-middle`, `tap1-right` | One-finger tap on the left, middle or right of the mouse |
| `tap1` | One-finger tap anywhere (used when no zone-specific tap is bound) |
| `tap2`, `tap3` | Two- or three-finger tap |
| `swipe2-up`, `swipe2-down`, `swipe2-left`, `swipe2-right` | Two-finger swipe |
| `swipe3-up`, `swipe3-down`, `swipe3-left`, `swipe3-right` | Three-finger swipe |
| `edge-left-up`, `edge-left-down` | One finger sliding along the left edge |
| `edge-right-up`, `edge-right-down` | One finger sliding along the right edge |

"Up" means toward the front of the mouse.

Edge slides repeat as you slide instead of firing once. They are speed-sensitive: slow movement gives fine control, faster movement counts for more, and a flick keeps coasting after the finger lifts. Scrolling is blocked on an edge strip that has a slide bound.

Things to know when choosing gestures:

- Two-finger vertical swipes also scroll the page.
- Two-finger horizontal swipes overlap with the system's swipe between pages and full-screen apps.
- A two-finger tap also fires on the first tap of the system's two-finger double-tap.
- One-finger taps are the easiest to trigger by accident.
- A tap is ignored if a mouse button was clicked during or just before it.
- Tap to click: the system's one-finger double-tap (Smart zoom) still fires alongside a double-tap click. Turn it off in System Settings > Mouse if it gets in the way.

### Actions

| Action | Config form | Notes |
|---|---|---|
| Keyboard shortcut | `{ "keys": "cmd+shift+t" }` | Modifiers: `cmd`, `ctrl`, `opt`, `shift`, `fn`. Keys: letters, digits, punctuation, `up` `down` `left` `right`, `f1`–`f12`, `space`, `tab`, `return`, `escape`, `delete`, `home`, `end`, `pageup`, `pagedown`. |
| Media key | `{ "media": "playpause" }` | `playpause`, `next`, `previous`, `volumeup`, `volumedown`, `mute`. `volumeup-fine` and `volumedown-fine` move in quarter steps. |
| Shell command | `{ "shell": "open -a Safari" }` | Run with `/bin/sh -c`. |
| Mouse click | `{ "click": "left" }` | `left`, `right` or `middle`, at the pointer. Quick repeated left clicks count as double- and triple-clicks. |

Edge slide bindings can also set `"stepMM"`, the finger travel per repeat, which overrides `edgeStepMM` for that edge.

### Tap and drag

With a one-finger tap bound to a left click, you can drag without pressing the button:

1. Tap once on the thing you want to drag.
2. Straight away, touch the mouse again and keep your finger down.
3. Move the mouse to drag. Lift your finger to drop.

The drag starts once the second touch has lasted longer than a tap, or as soon as the mouse moves. A quick second tap is still a double-click. Turn this off with the "Tap and drag" switch in Settings → Tuning.

## The gestures in this repository

`config.json` holds the current setup:

| Gesture | Action |
|---|---|
| One-finger tap | Left click, or right click when tapped on the right side (tap to click) |
| Left edge, slide up / down | Volume up / down in fine steps, one step per 2.5 mm |
| Three-finger tap | Mission Control (`ctrl+up`) |
| Three-finger swipe up | Show Desktop (`f11`) |
| Three-finger swipe down | App Exposé (`ctrl+down`) |
| Three-finger swipe left / right | Previous / next tab (`cmd+shift+[` / `cmd+shift+]`) |

The keyboard shortcuts assume the default macOS shortcuts for Mission Control, Show Desktop and App Exposé.

## Config file

Everything is stored in `~/.config/magicgestures/config.json`. The Settings window writes this file, and you can also edit it by hand. It has two parts: `gestures`, a map from gesture name to action, and `settings`:

| Setting | Default | Meaning |
|---|---|---|
| `tapMaxSeconds` | 0.25 | Longest a touch can last and still count as a tap |
| `tapMaxMoveMM` | 2.5 | Furthest a finger can move during a tap |
| `swipeMinMM` | 10 | Distance every finger must travel for a swipe |
| `swipeWindowSeconds` | 0.35 | Time in which that distance must be covered |
| `cooldownSeconds` | 0.3 | Minimum gap between two gestures |
| `middleZoneWidth` | 0.2 | Width of the middle zone for one-finger taps, as a fraction of the mouse width |
| `edgeZoneWidth` | 0.18 | Width of each edge strip, as a fraction of the mouse width |
| `edgeStepMM` | 5 | Finger travel per repeat of an edge slide |
| `edgeStartMM` | 3 | Movement needed before an edge slide begins |
| `edgeAcceleration` | 1.0 | How much faster movement counts for more; 0 is strictly linear |
| `edgeMomentum` | 0.15 | Seconds a flick keeps coasting; 0 turns it off |
| `tapAndDrag` | true | Tap, then touch again and hold, to drag |

## Touch viewer

**Show Touch Viewer** opens a floating window with a top-down mouse. Fingers on the mouse appear as dots with short trails, and recognised gestures are named at the bottom. Dashed lines mark the tap zones, and bound edge strips are tinted.

The mouse reports touches as a plain rectangle, but its ends are rounded, so the viewer learns the outline from where you actually touch. Trace one finger around the whole edge of the mouse once to calibrate it. **Reset Viewer Outline** starts over.

## Troubleshooting

- **Gestures are recognised but nothing happens.** Accessibility access is missing. Check the menu for the warning line.
- **Nothing is recognised.** Check the menu says "Magic Mouse connected", and look at the log.
- **A gesture misfires or is hard to trigger.** Adjust the sliders in Settings → Tuning.
- **Log file:** `~/Library/Logs/MagicGestures.log` records every recognised gesture and config load. Run `/Applications/MagicGestures.app/Contents/MacOS/MagicGestures --debug` from a terminal to also print raw touch data.

## How it works, and its limits

- Touches are read through `MultitouchSupport`, a private Apple framework. It is undocumented and could change or break in a future macOS update.
- Keys and clicks are sent as synthetic events, and scrolling is blocked with an event tap. Both need Accessibility access.
- Any external multitouch device with a portrait-shaped sensor is treated as a Magic Mouse; trackpads are ignored.
- The whole app is one Swift file, `main.swift`, compiled directly with `swiftc`. There is no Xcode project.
