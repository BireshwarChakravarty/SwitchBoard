<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="Switchboard app icon">
</p>

<h1 align="center">Switchboard</h1>

<p align="center">
  <strong>A menu-bar control panel for external displays on Apple Silicon Macs.</strong><br>
  Power, brightness, contrast, volume and resolution for every screen, in one place.
</p>

<p align="center">
  <a href="https://github.com/BireshwarChakravarty/SwitchBoard/actions/workflows/build.yml"><img src="https://github.com/BireshwarChakravarty/SwitchBoard/actions/workflows/build.yml/badge.svg" alt="Build and test"></a>
  <a href="https://github.com/BireshwarChakravarty/SwitchBoard/releases/latest"><img src="https://img.shields.io/github/v/release/BireshwarChakravarty/SwitchBoard?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Apple%20Silicon-required-000000" alt="Apple Silicon">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/BireshwarChakravarty/SwitchBoard" alt="MIT License"></a>
</p>

---

macOS gives an external monitor almost no controls: no power switch, no
brightness, and on a Mac mini the keyboard's brightness keys only report
"not supported". Switchboard fills that gap. It talks to monitors directly
over **DDC/CI**, the control channel built into DisplayPort, HDMI and USB-C,
and falls back to software where a monitor doesn't support it.

It's a native SwiftUI app with the macOS 26 Liquid Glass design. It has no
dependencies and makes no network connections.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Using Switchboard](#using-switchboard)
- [How it works](#how-it-works)
- [Privacy and safety](#privacy-and-safety)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Building from source](#building-from-source)
- [Contributing](#contributing)
- [License](#license)

## Features

**Power**
- Switch any external screen off and on from the menu bar.
- Monitors that support DDC/CI go into hardware standby. Monitors that don't,
  which includes many portable displays, are disconnected in software. Your
  other screens stay on either way.
- Optionally switch a screen off while the Mac is locked or asleep, and back on
  when you return.

**Picture**
- **Combined brightness:** one slider drives the monitor's real backlight, then
  continues below its minimum with software dimming. Monitors without DDC/CI
  are dimmed in software.
- **Contrast**, **volume** for monitor speakers, and **resolution**, using the
  same scaled sizes System Settings offers.
- **All Screens:** one brightness slider for every display at once.
- **Match Light & Dark Mode:** each screen remembers a brightness for each
  appearance and switches automatically.
- Restore a monitor's factory picture settings.

**Keyboard**
- Brightness keys adjust the screen under the pointer, together with any screen
  mirroring it, with an on-screen indicator. Hold <kbd>⇧</kbd><kbd>⌥</kbd> for
  finer steps.
- Volume and mute keys control monitor speakers, which macOS can't adjust over
  HDMI or DisplayPort.

**Design**
- Laid out like Control Center: a list of screens, large titled sliders for the
  selected screen, and a collapsible Settings section.
- Follows Light and Dark mode, and supports VoiceOver.

## Requirements

| | |
|---|---|
| **Mac** | Apple Silicon. Designed for Macs without a built-in display, such as Mac mini. |
| **macOS** | 26 (Tahoe) or later |
| **Monitors** | Any external display. Hardware controls require DDC/CI, which most monitors support but some ship with it turned off in their on-screen menu. Some docks and adapters don't pass DDC/CI through. |

## Installation

### Download

1. Download **Switchboard.zip** from the
   [latest release](https://github.com/BireshwarChakravarty/SwitchBoard/releases/latest).
2. Unzip it and move **Switchboard.app** to your Applications folder.
3. Open it. Switchboard is ad-hoc signed rather than notarized, so the first
   time, right-click the app and choose **Open**, then **Open** again.
   Alternatively, run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Switchboard.app
   ```

### Build from source

See [Building from source](#building-from-source).

## Getting started

Switchboard lives in the menu bar: look for the monitor icon with a switch on
its screen. On first launch it turns on **Start at Login** and asks for two
permissions, which the keyboard keys need:

| Permission | Where | Why |
|---|---|---|
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring | Reads Apple keyboards' brightness keys. macOS handles these inside its keyboard driver, so no app sees them otherwise. |
| **Device Control and Data Access** | System Settings → Privacy & Security → Device Control and Data Access (called **Accessibility** before macOS 27) | Catches the volume keys, and brightness keys from keyboards that send them as standard events. |

Turn **Switchboard** on in both lists. The keys start working within a few
seconds, with no need to relaunch. Everything else works without these
permissions.

> [!TIP]
> Quit other display utilities such as BetterDisplay, MonitorControl or Lunar
> while using Switchboard. They respond to the same keys and talk to the same
> monitors.

## Using Switchboard

### The menu

| Section | What it does |
|---|---|
| **Screens** | Every connected screen, with its status (for example *Mirrored to …* or *Disconnected*) and a power switch. Click a screen to show its controls. |
| **Selected screen** | Brightness, Contrast, Volume and Resolution sliders, with live values. The **⋯** button shows that screen's options in the card. |
| **Brightness · All Screens** | One slider for every screen. Shown when two or more screens can be adjusted. |
| **Settings** | Keyboard Keys, Match Light & Dark Mode, and Start at Login. |
| **Footer** | Reset to Defaults, Refresh Screens, and Quit. |

The last screen that's still on has no power switch, so you can never switch
every screen off at once.

### Screen options

Open them with **⋯** on the selected screen (they appear in the screen's card),
or by right-clicking a screen in the list.

| Option | Description |
|---|---|
| **Switch Off By** | How the screen is switched off: **DDC/CI Standby** (the monitor sleeps), **Disconnecting** (macOS stops using the screen), or **Blacking Out** (the picture goes black and the backlight stays on). Switchboard chooses automatically: the first time a monitor doesn't respond to DDC/CI, it switches to disconnecting and remembers the choice. |
| **Switch Off While Locked or Asleep** | Switches the screen off when the Mac locks or sleeps, and back on when you unlock it. |
| **Hide power switch** | Removes the switch for a screen you never turn off. |
| **Restore Brightness & Contrast** | Asks the monitor to restore its factory brightness and contrast. |
| **Restore All Settings** | Asks the monitor to reset everything, like the Reset option in its own menu. |

Both factory commands are optional in the DDC/CI standard. Switchboard reads
the monitor's settings back afterwards and shows the result under the screen's
name: the restored values, or that the monitor ignored the request.

### Keyboard keys

| Keys | Action |
|---|---|
| Brightness up / down (<kbd>F1</kbd> / <kbd>F2</kbd> on Apple keyboards) | One step of 16, like a built-in display. Hold the key to keep stepping. |
| <kbd>⇧</kbd><kbd>⌥</kbd> + brightness | One step of 64 |
| <kbd>fn</kbd> + <kbd>F1</kbd> / <kbd>F2</kbd> | Normal F1 and F2. This reverses if *Use F1, F2, etc. keys as standard function keys* is on. |
| Volume up / down, mute | Monitor speakers, when sound plays through them over HDMI or DisplayPort. Otherwise the keys work as usual. |

Brightness keys adjust the screen under the pointer, together with any screen
mirroring it. If that screen can't be adjusted, they adjust your other
screens. The status line under **Settings → Keyboard Keys** shows each key
Switchboard receives and what it did.

On Apple keyboards, macOS may still show its own "not supported" indicator
alongside Switchboard's. Reading the keyboard directly can't suppress it.

## How it works

| Feature | Implementation |
|---|---|
| Standby and wake | DDC/CI *Set VCP Feature* `0xD6` (power mode): `0x05` standby, `0x01` on |
| Brightness, contrast, volume | DDC/CI VCP `0x10`, `0x12` and `0x62`, read back with *Get VCP Feature* |
| Factory reset | DDC/CI VCP `0x06` (brightness and contrast) and `0x04` (all settings) |
| DDC/CI transport | I²C through `IOAVService` (private IOKit symbols on Apple Silicon), matched to each screen through the IORegistry and its EDID |
| Software disconnect | `CGSConfigureDisplayEnabled` (undocumented), applied for the app only. Other screens don't blank, and macOS reconnects the screen when the app quits. |
| Software dimming | Display gamma tables (`CGSetDisplayTransferByTable`) |
| Resolution | Scaled modes from `CGDisplayCopyAllDisplayModes`, applied with `CGConfigureDisplayWithDisplayMode` |
| Monitor speakers | Core Audio identifies HDMI or DisplayPort output without a volume control; the volume is set over DDC/CI |
| Brightness keys | `IOHIDManager` reads keyboards' brightness usages; a `CGEventTap` handles system media-key events |
| Start at Login | `SMAppService` |

The DDC/CI approach on Apple Silicon follows the open-source
[m1ddc](https://github.com/waydabber/m1ddc) and
[MonitorControl](https://github.com/MonitorControl/MonitorControl) projects.

## Privacy and safety

- **No network access.** Switchboard makes no network connections and collects
  no data.
- **Keyboard access is narrow.** Switchboard only acts on brightness, volume
  and mute keys. Every other key passes through untouched and is never stored
  or logged.
- **Nothing gets stuck.** A disconnected screen comes back when Switchboard
  quits, even if it crashes. Software dimming is undone the same way. The last
  screen that's still on can't be switched off.
- **Reversible.** **Reset to Defaults** reconnects every screen, removes
  dimming, wakes monitors from standby and clears all settings.
- **Undocumented interfaces.** DDC/CI on Apple Silicon and the software
  disconnect use private macOS functions. A future macOS update could change
  them, in which case those features stop working; the rest of the app is
  unaffected.

## Troubleshooting

Switchboard writes to the macOS unified log. To watch it while you reproduce a
problem:

```bash
log stream --level debug --predicate 'subsystem == "app.switchboard.Switchboard"'
```

| Problem | What to do |
|---|---|
| Keyboard keys do nothing | Check **Settings → Keyboard Keys**. A permission notice there links to the right page. If you've updated the app, turn Switchboard off and on again in both permission lists. Quit other display utilities. |
| *Not responding to DDC/CI* | Turn on DDC/CI in the monitor's own menu, or try another cable, port or adapter. Use **Switch Off By → Disconnecting** for monitors without DDC/CI. |
| Only a *Brightness (Software)* slider | The monitor didn't answer DDC/CI read requests. Look for `No reply reading VCP` in the log. |
| A control affects the wrong monitor | Each DDC/CI lookup logs every candidate port with its EDID UUID and match score. [Open an issue](https://github.com/BireshwarChakravarty/SwitchBoard/issues/new/choose) with those lines. |
| *Couldn't disconnect* | macOS rejected the software disconnect. Please open an issue with the log. |
| A screen stays off | Quit Switchboard: macOS reconnects it. If that doesn't help, run `/Applications/Switchboard.app/Contents/MacOS/Switchboard --reset`, or log out and back in. |

## Uninstalling

Quit Switchboard from its menu (this reconnects and restores every screen),
then run:

```bash
rm -rf /Applications/Switchboard.app
defaults delete app.switchboard.Switchboard
tccutil reset Accessibility app.switchboard.Switchboard
tccutil reset ListenEvent app.switchboard.Switchboard
```

If a **Switchboard** entry remains in System Settings → General → Login Items,
remove it there.

## Building from source

Requirements: macOS 26 and the Swift toolchain. The free Command Line Tools
are enough (`xcode-select --install`); full Xcode isn't required.

```bash
git clone https://github.com/BireshwarChakravarty/SwitchBoard.git
cd SwitchBoard
./make-app.sh
```

`make-app.sh` builds a release binary, wraps it in `Switchboard.app`, signs it
ad hoc, and performs a clean install into `/Applications`. Any earlier copy is
quit, its changes to your screens are undone, and its settings and permissions
are cleared before the new app launches.

| Command | Purpose |
|---|---|
| `swift build` | Debug build |
| `swift test` | Unit tests |
| `swift run` | Run without installing |
| `./make-app.sh` | Build and install into `/Applications` |
| `./make-app.sh --package` | Build `dist/Switchboard.zip` without installing |

Every push is built and tested on macOS 26 by
[GitHub Actions](.github/workflows/build.yml), and releases are published from
the same workflow.

### Project structure

```text
Sources/Switchboard/
├── SwitchboardApp.swift      Menu-bar app and user interface
├── DisplayController.swift   Screen list, power, brightness, keys and automation
├── Arm64DDC.swift            DDC/CI over IOAVService
├── DDC.swift                 VCP codes, packets, checksums and reply parsing
├── IOKitPrivate.swift        Bindings for the private IOAVService functions
├── SoftwareDisconnect.swift  Software disconnect and reconnect
├── SoftwareDimmer.swift      Gamma-table dimming
├── BrightnessCurve.swift     Combined hardware and software brightness scale
├── DisplayModes.swift        Resolutions
├── KeyboardReader.swift      Brightness keys read from keyboards (IOHIDManager)
├── MediaKeys.swift           Media-key event tap
├── LevelHUD.swift            On-screen brightness and volume indicator
├── AudioOutput.swift         Detects monitor speakers without volume control
├── Displays.swift            Display lists
├── Preferences.swift         Settings
├── Reset.swift               Restores every screen (--reset, Reset to Defaults)
├── LoginItem.swift           Start at Login
├── Log.swift                 Unified logging
└── MenuBarIcon.swift         Menu-bar icon, drawn in code
Tests/SwitchboardTests/       Unit tests
Resources/                    Info.plist and app icon (AppIcon.svg is the source)
```

## Contributing

Bug reports and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first, and include your macOS version,
monitor models and how they're connected when reporting a problem.

## License

Switchboard is released under the [MIT License](LICENSE).

Switchboard is an independent project. It isn't affiliated with Apple, or with
BetterDisplay, MonitorControl or Lunar.
