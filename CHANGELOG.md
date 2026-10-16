# Changelog

All notable changes to Switchboard are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.0.2] - 2026-10-17

### Changed
- The menu shows just the version, such as *Version 2.0.2*, without a build
  number. Pre-releases still show their full label, such as
  *Version 2.1.0-beta.1*. The app's bundle version now matches it too.

## [2.0.1] - 2026-10-17

### Changed
- The menu shows the build number with the version, such as
  *Version 2.0.1 (34)*, so any two builds can be told apart.
- Reorganised the source code by area, with one view per file. No change in
  behaviour.
- Releases are now cut from a single `VERSION` file, with notes taken from
  this changelog.

## [2.0.0] - 2026-10-16

First published as 1.1.0 (with two 1.1.0 betas) and renamed 2.0.0.

### Added
- **iPhone Remote** (Settings → iPhone Remote, off by default). Control your
  screens from an iPhone on the same network: a web page you add to the Home
  Screen, with power switches, brightness, contrast, volume, resolution and
  All Screens brightness. Changes made on the Mac show up within seconds.
- **Siri shortcuts.** Add Shortcuts… builds "<Screen> On", "<Screen> Off" and
  "Toggle <Screen>" for each screen with a power switch, and "Screen
  Brightness", which asks for a number. They're signed on the Mac with Apple's
  `shortcuts` tool and opened in the Shortcuts app; iCloud syncs them to the
  iPhone, and Siri reads out the result. The page also offers links for your
  own shortcuts.
- **Pairing.** A phone pairs once with a six-digit code shown on the Mac and
  gets a random key; only its SHA-256 hash is stored. Five wrong codes replace
  the code. Forget All unpairs every device, and Reset to Defaults turns the
  remote off.
- The remote follows the menu's rules: a hidden power switch can't be used
  remotely, and the last screen that's on can't be switched off.

### Changed
- Updated the build's GitHub Actions (checkout and upload-artifact v7).

## [1.0.3] - 2026-10-16

### Fixed
- Permissions no longer need granting again after every update, and macOS's
  permission prompts appear once rather than on every launch. The app is
  signed with a stable identity (its bundle identifier), so Input Monitoring
  and Device Control access carry over to new versions. Updating from 1.0.2
  or earlier needs one last re-grant.

### Changed
- **Reset to Defaults** moved into Settings, with inline confirmation, and
  now also sets each DDC/CI monitor's contrast to 50%, the usual factory
  value.
- Removed the per-screen factory reset buttons. The DDC/CI factory-reset
  commands are optional and many monitors ignore them.
- Removed the Reset and Refresh buttons from the footer; Switchboard refreshes
  by itself when screens change.

## [1.0.2] - 2026-10-16

### Fixed
- Switching off a mirrored screen could black out the screen it mirrors. The
  **Black Out** switch-off method darkened a screen through its gamma table,
  which a mirror shares with its source. It has been removed: screens set to
  it now disconnect, which leaves other screens on. Software dimming also no
  longer writes to screens that are switched off.

### Changed
- When a monitor ignores **Restore All Settings**, Switchboard remembers that
  it doesn't support DDC/CI factory resets. Its options then explain this and
  offer **Set Contrast to 50%** (the usual factory contrast) instead of resets
  that can't work. Reset to Defaults clears this.

## [1.0.1] - 2026-10-16

### Fixed
- Restoring factory settings did nothing: actions in the pop-up options menu
  didn't run from the menu-bar window. Screen options (**⋯**) now open inline
  in the screen's card, with a segmented Switch Off By control, switches and
  buttons. Right-click still offers the same options as a menu.
- Restoring factory settings now always reports its result: progress while it
  runs, then the values the monitor reports afterwards, or that the monitor
  ignored the command, couldn't be reached, or didn't report back.

### Changed
- Rewrote the README and added contributor documentation, issue templates and
  a security policy.
- Updated the CI checkout action to a Node 24 version, and enabled Dependabot
  for workflow updates.
- Added `CFBundleInfoDictionaryVersion` to the app's Info.plist.

## [1.0.0] - 2026-10-16

First public release.

### Added
- Power switch for every external screen: DDC/CI standby, or a software
  disconnect for monitors without DDC/CI. Other screens stay on.
- Combined brightness (DDC/CI backlight with software dimming below its
  minimum), contrast, volume and resolution controls, plus an All Screens
  brightness slider.
- Brightness keys for external screens, including Apple keyboards, with an
  on-screen indicator; volume and mute keys for monitor speakers.
- Match Light & Dark Mode, switch off while locked or asleep, Start at Login.
- Restore a monitor's factory brightness and contrast, or all its factory
  settings, with a check that the monitor responded.
- Reset to Defaults, and a `--reset` command-line option.
- Liquid Glass interface modelled on Control Center.
- Unit tests and continuous integration on macOS 26.

[Unreleased]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v2.0.2...HEAD
[2.0.2]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.3...v2.0.0
[1.0.3]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/BireshwarChakravarty/SwitchBoard/releases/tag/v1.0.0
