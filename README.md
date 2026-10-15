<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="Switchboard icon">
</p>

<h1 align="center">Switchboard</h1>

<p align="center">
  A menu-bar control panel for the monitors on a Mac mini.
</p>

---

Switchboard gives every external screen a **switch** and a set of **faders**:

- **Switch screens off and on.** Monitors that support DDC/CI go into
  hardware standby. Monitors that don't (common on portable monitors) are
  disconnected in software, as if the cable were pulled, and reconnected when
  you switch them back on.
- **Brightness, contrast and volume** over DDC/CI, with live percentage
  readouts.
- **Software dimming** (down to black) for monitors without DDC/CI.
- **Your keyboard's brightness keys work.** On a Mac mini macOS says "not
  supported"; with Switchboard they adjust the monitor under the pointer
  (and any screen mirroring it), with an on-screen brightness indicator.
  Hold ⇧⌥ for finer steps.
- **Off while locked or asleep:** per screen, switch it off when the Mac locks
  or sleeps and back on when you return.
- **Mirroring-aware:** shows "Mirrored to …" / "Mirror of …" like the system
  does.
- **Safe by design:** the last screen still on has no switch, Quit reconnects
  everything, and a crash or logout can never leave a screen stuck off.
- **Reset to Defaults** puts every screen back to normal and forgets all
  settings.

It's a native SwiftUI app with the macOS 26 Liquid Glass look, with no
dependencies and no network access.

## Requirements

- An **Apple Silicon Mac mini**. Switchboard is built for Macs without a
  screen of their own (it also runs on a Mac Studio). It isn't meant for
  MacBooks or iMacs.
- **macOS 26 (Tahoe)** or later.
- The Swift toolchain: the free **Command Line Tools** are enough
  (`xcode-select --install`). Full Xcode isn't needed.
- For hardware control, the monitor must support **DDC/CI**, and it must be
  enabled in the monitor's own on-screen menu. Some docks and adapters don't
  pass DDC through.

## Install

```bash
git clone https://github.com/BireshwarChakravarty/SwitchBoard.git
cd SwitchBoard
./make-app.sh
```

`make-app.sh` builds the app, signs it for your Mac (ad-hoc), and does a
**clean install** into `/Applications`. Before installing, it undoes anything
an earlier copy did: it reconnects screens, removes dimming, wakes monitors,
and deletes old settings and permissions. Then it launches Switchboard.

On first launch Switchboard turns on **Start at Login**. You can turn that
off in its menu.

Because the app is built on your Mac and not notarized, macOS may block the
first launch. Right-click **Switchboard** in Applications → **Open** →
**Open**, or allow it in System Settings → Privacy & Security.

To update, `git pull` and run `./make-app.sh` again.

## Using it

Click the monitor-and-switch icon in the menu bar.

| Control | What it does |
|---|---|
| Switch next to a screen | Switch it off (standby or disconnect) and on again |
| Sliders under a screen | Brightness, contrast, volume (DDC/CI) or Dim (software) |
| **Brightness Keys** | Keyboard brightness keys adjust your monitors (on by default) |
| **Start at Login** | Launch Switchboard when you log in |
| ↺ (counter-clockwise arrow) | Reset to Defaults (asks first) |
| ⟳ (clockwise arrow) | Re-scan screens |
| ⏻ (power) | Quit; reconnects and restores every screen first |

**Right-click a screen** for its options:

- **Hide Switch / Show Switch**: hide the switch of a screen you never turn off.
- **Switch Off By → DDC/CI Standby / Disconnecting**: Switchboard picks this
  itself. The first time a monitor doesn't answer DDC/CI it switches to
  disconnecting and remembers that.
- **Switch Off While Locked or Asleep**.

### Brightness keys

Brightness keys are on from the first launch. macOS only lets an app react
to them with **Accessibility** permission, so Switchboard asks for it on
launch:

1. In the prompt, click **Open System Settings**.
2. Turn on **Switchboard** under Privacy & Security → Accessibility.

The keys start working within a couple of seconds, with no relaunch needed.
Until then the Brightness Keys row shows **Needs Accessibility access**, with
a button straight to that setting.

- Each press moves brightness one of 16 steps, like a built-in screen; hold
  **⇧⌥** for 64 finer steps. A brightness indicator appears at the top right.
- Keys adjust the monitor under the pointer, together with any screen
  mirroring it. If that screen can't be adjusted, they adjust your other
  monitors.
- DDC/CI monitors change their real backlight; others are dimmed in software.

If you rebuild the app, macOS treats it as a new app. `make-app.sh` clears
the old permission, so grant it again when asked.

## How it works

| Feature | Mechanism |
|---|---|
| Standby / wake | DDC/CI *Set VCP Feature* `0xD6` (power mode): `0x05` standby, `0x01` on |
| Brightness / contrast / volume | DDC/CI VCP `0x10` / `0x12` / `0x62`, read with *Get VCP Feature* |
| DDC transport | `IOAVService` I²C on Apple Silicon (private IOKit symbols), matched to each screen through the IORegistry and its EDID |
| Disconnect | `CGSConfigureDisplayEnabled` (undocumented), applied for the login session only |
| Dimming | Display gamma tables (`CGSetDisplayTransferByTable`) |
| Brightness keys | A `CGEventTap` on the system-defined brightness key events; indicator is a Liquid Glass `NSPanel` |
| Start at Login | `SMAppService` |

The DDC approach is the one used by the open-source
[m1ddc](https://github.com/waydabber/m1ddc) and
[MonitorControl](https://github.com/MonitorControl/MonitorControl) projects.
Switchboard is an independent project, not affiliated with them or with
BetterDisplay.

## Troubleshooting

Switchboard logs to the unified system log. Watch it live while you
reproduce a problem:

```bash
log stream --level debug --predicate 'subsystem == "app.switchboard.Switchboard"'
```

- **Brightness keys do nothing**: check Switchboard is on under Privacy &
  Security → Accessibility (after a rebuild, turn it off and on). In the
  log, `Brightness keys: listening` means the keys are being caught, and each
  press logs `Brightness key up/down`. If presses never appear, your keyboard
  doesn't send standard brightness keys.
- **"Not responding to DDC/CI"**: the monitor didn't answer. Enable DDC/CI in
  its menu, try another port or cable, or use **Switch Off By →
  Disconnecting**.
- **No sliders for a DDC monitor**: it didn't answer the read requests. Look
  for `no reply reading VCP` in the log; it gets a Dim slider instead.
- **A switch controls the wrong screen**: each DDC lookup logs every candidate
  port with its `EDID UUID` and match score. Please open an issue with those
  lines.
- **"Couldn't disconnect"**: macOS refused the software disconnect.
- **A screen stays off after a problem**: run
  `/Applications/Switchboard.app/Contents/MacOS/Switchboard --reset`, or log
  out and back in.

## Building from source

```text
Sources/Switchboard/
├── SwitchboardApp.swift      Menu-bar UI (Liquid Glass cards, rows, sliders)
├── DisplayController.swift   Screen list, switching, sliders, keys, automation
├── Arm64DDC.swift            DDC/CI over IOAVService (Apple Silicon)
├── DDC.swift                 VCP codes, packets, checksums, reply parsing
├── IOKitPrivate.swift        Bindings for the private IOAVService symbols
├── SoftwareDisconnect.swift  Software disconnect / reconnect
├── SoftwareDimmer.swift      Gamma-table dimming
├── BrightnessKeys.swift      Brightness-key event tap
├── BrightnessHUD.swift       On-screen brightness indicator
├── Displays.swift            CoreGraphics display lists
├── Preferences.swift         Per-screen and app settings
├── Reset.swift               Restore every screen (`--reset`, Reset to Defaults)
├── LoginItem.swift           Start at Login
└── MenuBarIcon.swift         The menu-bar icon, drawn in code
Resources/
├── Info.plist
├── AppIcon.icns              App icon (source: AppIcon.svg)
└── AppIcon.png
```

The code doesn't use SwiftUI's `@State`. On recent SDKs it's a compiler macro
whose plugin ships only with full Xcode, so avoiding it keeps the app
buildable with just the Command Line Tools.

## License

[MIT](LICENSE)
