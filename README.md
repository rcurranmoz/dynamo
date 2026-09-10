<div align="center">

# ⚡ Dynamo

**A menubar switch that keeps your Mac awake.**

One click. One lightning bolt. No preferences window.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white)](https://developer.apple.com/documentation/appkit)
[![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen)](#build-it-yourself)
[![Lines of code](https://img.shields.io/badge/source-~60%20lines-blue)](main.swift)

</div>

---

## The whole app

```
┌─────────────────────────────────────────────┐
│  ☀︎  ⌘  ⚡  ⌥  Wed 10 Sep  9:41            │   ← hollow bolt: Mac sleeps normally
└─────────────────────────────────────────────┘
                 ↑ click

┌─────────────────────────────────────────────┐
│  ☀︎  ⌘  ⚡  ⌥  Wed 10 Sep  9:41            │   ← filled bolt: Mac stays awake
└─────────────────────────────────────────────┘
```

| | |
|---|---|
| **Left-click** the bolt | Toggle awake on / off |
| **Right-click** the bolt | Show current state + **Quit** |
| **Hollow** bolt | Idle — your Mac sleeps normally |
| **Filled** bolt | Live — display and system sleep are blocked |

That's the entire interface. There is no window, no Dock icon, no menu bar, and no settings.

## Why you might want it

- Long build, test run, or file copy that must not get interrupted by a sleeping machine.
- Screen-sharing or presenting and you'd rather the display not dim mid-sentence.
- You SSH into your desktop and need it to stay reachable.
- You just don't want to keep nudging the trackpad.

It's a friendly front-end for the `caffeinate` tool that already ships with macOS. Nothing is
installed system-wide, no background daemon is registered, and nothing runs unless you click it.

---

## Install it (for coworkers)

**Time: about 30 seconds.** You need the Xcode command line tools. Most people at Mozilla already
have them; if you're not sure, the first command below will tell you.

### Step 0 — one-time prerequisite

```bash
xcode-select -p
```

If that prints a path, you're set. If it errors, run this and accept the dialog:

```bash
xcode-select --install
```

### Step 1 — build and install

Copy and paste this whole block into Terminal:

```bash
git clone https://github.com/rcurranmoz/dynamo.git /tmp/dynamo && \
cd /tmp/dynamo && \
./build.sh && \
cp -R Dynamo.app /Applications/ && \
open /Applications/Dynamo.app
```

A lightning bolt appears in your menubar. Click it. Done.

> **Why build instead of downloading a `.app`?** Because building locally means macOS never puts the
> app in quarantine, so there's no "unidentified developer" warning, no Gatekeeper prompt, and no
> right-click → Open dance. It's genuinely the easier path here, and you can read all 60 lines of
> source first if you want to.

### Step 2 — start it automatically at login (optional)

1. Open **System Settings**
2. Go to **General → Login Items & Extensions**
3. Under **Open at Login**, click **+**
4. Choose **/Applications/Dynamo.app**

### Uninstall

Quit it from the right-click menu, then:

```bash
rm -rf /Applications/Dynamo.app
```

Remove it from Login Items too if you added it there. Nothing else is left behind — no preferences,
no daemons, no support folders.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No bolt in the menubar | Your menubar is probably full. Hold **⌘** and drag other icons to make room, or hide some via System Settings. |
| `xcode-select: error: ...` | Run `xcode-select --install` and accept the dialog, then retry Step 1. |
| `git: command not found` | Same fix — the command line tools include git. |
| Mac still sleeps on battery | Expected. The `-s` flag only blocks system sleep on AC power. Display sleep is still blocked either way. |
| Not sure it's actually on | Run the verification command below. |
| It stopped working after a macOS update | Rebuild: rerun the Step 1 block. |

### Verify it's really working

With the bolt **filled**, run:

```bash
pmset -g assertions | grep -E 'PreventUserIdleDisplaySleep|PreventSystemSleep|PreventUserIdleSystemSleep'
```

All three should read `1`. Toggle the bolt off and they drop back to `0`.

---

## How it works

When you switch it on, Dynamo spawns exactly one child process:

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
| `-w <pid>` | Makes `caffeinate` wait on Dynamo and exit when it does |

That last flag is the part worth knowing about. Dynamo already kills the child on toggle-off and on
clean quit, but `-w` covers the ugly cases: a force quit, a crash, a `kill -9`. Without it you can
orphan a `caffeinate` process that silently holds a power assertion forever, and the only symptom is
a Mac that mysteriously refuses to sleep, days later, with no icon anywhere to explain why. This is
the single most common bug in homegrown caffeinate wrappers.

---

## Build it yourself

```bash
./build.sh      # compiles main.swift, assembles the bundle, ad-hoc signs it
open Dynamo.app
```

`build.sh` deletes and recreates `Dynamo.app` in place on every run, so the bundle is a build
artifact and is gitignored. The build targets `arm64-apple-macos13.0` — change the `-target` line in
`build.sh` for Intel or an older minimum.

### Implementation notes

- `LSUIElement` plus `NSApplication.setActivationPolicy(.accessory)` keeps Dynamo out of the Dock and
  out of the menu bar. The status item is the entire user interface.
- The right-click menu is attached and immediately detached around the click. If the menu stayed
  attached to the status item, AppKit would pop it on left-click too, and the one-click toggle would
  be gone.
- Ad-hoc signing (`codesign --sign -`) gives the app a stable identity across rebuilds, so macOS
  doesn't re-evaluate it every time you rebuild.
- The icons are the SF Symbols `bolt` and `bolt.fill`, so they follow your menubar's light/dark
  appearance automatically.

---

## Family

Part of a personal RelOps tooling set — a fleet dashboard, a couple of iOS monitoring apps, a fleet
CLI. Dynamo is by far the least ambitious of them, which is the point.

<div align="center">
<sub>⚡ Built because the coffee cup icon was taken.</sub>
</div>
