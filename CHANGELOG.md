# Changelog

All notable changes to Switchboard are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/BireshwarChakravarty/SwitchBoard/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/BireshwarChakravarty/SwitchBoard/releases/tag/v1.0.0
