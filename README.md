# Dynamo

A menubar switch that keeps your Mac awake. One click, one lightning bolt, no preferences window.

Dynamo is a ~60-line native AppKit app that wraps `caffeinate -dimsu`. That's the whole idea. It has no
dependencies, no Xcode project, no launch agent, and no settings — it builds with a single `swiftc`
invocation and lives entirely in your menubar.

## Usage

| Action | Result |
|---|---|
| **Left-click** the bolt | Toggles wakefulness on/off |
| **Right-click** the bolt | Shows current state and a Quit item |

| Icon | Meaning |
|---|---|
| Hollow bolt (`bolt`) | Idle — your Mac sleeps normally |
| Filled bolt (`bolt.fill`) | Live — display and system sleep are blocked |

Hover the icon for a tooltip if you can't tell the two glyphs apart at a glance.

## What it actually does

When you switch it on, Dynamo spawns:

```
/usr/bin/caffeinate -dimsu -w <dynamo's own pid>
```

| Flag | Prevents |
|---|---|
| `-d` | Display sleep |
| `-i` | System idle sleep |
| `-m` | Disk idle sleep |
| `-s` | System sleep (while on AC power) |
| `-u` | Declares user activity, so the display stays on |

The `-w <pid>` is the part worth knowing about. It tells `caffeinate` to wait on Dynamo's process and
exit when it goes away. Dynamo already terminates the child on toggle-off and on clean quit, but `-w`
covers the ugly cases — a force quit, a crash, a `kill -9`. Without it you can end up with an orphaned
`caffeinate` silently holding a power assertion forever, and the only clue is a Mac that mysteriously
refuses to sleep. This is the single most common bug in homegrown caffeinate wrappers.

To confirm it's working:

```bash
pmset -g assertions | grep -E 'PreventUserIdleDisplaySleep|PreventSystemSleep|PreventUserIdleSystemSleep'
```

All three should read `1` while the bolt is filled.

## Build

Requires the Xcode command line tools (`xcode-select --install`). Nothing else.

```bash
./build.sh
open Dynamo.app
```

`build.sh` compiles `main.swift`, assembles the `.app` bundle, writes `Info.plist`, and ad-hoc
codesigns the result. It deletes and recreates `Dynamo.app` in place every run, so the bundle is a
build artifact and is gitignored.

The build targets `arm64-apple-macos13.0`. Change the `-target` in `build.sh` if you need Intel or an
older minimum.

## Install

Because `build.sh` wipes the bundle in place, copy it somewhere stable before wiring it up:

```bash
cp -R Dynamo.app /Applications/
```

Then add `/Applications/Dynamo.app` under **System Settings → General → Login Items** to start it at
login.

## Notes

- `LSUIElement` plus `NSApplication.setActivationPolicy(.accessory)` keeps Dynamo out of the Dock and
  out of the menu bar. The status item is the entire user interface.
- The right-click menu is attached and immediately detached around the click. If the menu stayed
  attached to the status item, AppKit would pop it on left-click too and you'd lose the one-click
  toggle.
- `-s` only prevents sleep on AC power. On battery, macOS will still sleep the system; the display
  assertions continue to apply.
- Ad-hoc signing (`codesign --sign -`) gives the app a stable identity across rebuilds, which keeps
  macOS from re-prompting or re-evaluating it every time you rebuild.

## Family

Part of a personal RelOps tooling set — a fleet dashboard, a couple of iOS monitoring apps, a fleet
CLI. Dynamo is by far the least ambitious of them, which is the point.
