# Architecture

Switchboard is a single Swift package: one executable target and one test
target, with no third-party dependencies. It builds with the Command Line
Tools; full Xcode isn't required.

## Layout

```text
Sources/Switchboard/
├── App/
│   └── SwitchboardApp.swift      Entry point, menu-bar scene, --reset
├── Interface/
│   ├── MenuContent.swift         The menu's layout and footer
│   ├── ScreensCard.swift         Screen list, status lines, right-click options
│   ├── ScreenControlsCard.swift  Selected screen's sliders and options panel
│   ├── SettingsCard.swift        Settings, iPhone Remote, Reset to Defaults
│   ├── Components.swift          Metrics and shared controls (PillSlider, badges…)
│   ├── LevelHUD.swift            On-screen brightness and volume indicator
│   └── MenuBarIcon.swift         Menu-bar icon, drawn in code
├── Displays/
│   ├── DisplayController.swift   State and actions behind the whole UI
│   ├── Displays.swift            Display lists
│   ├── DisplayModes.swift        Scaled resolutions
│   ├── SoftwareDisconnect.swift  Disconnect and reconnect (app-scoped)
│   ├── SoftwareDimmer.swift      Gamma-table dimming
│   ├── BrightnessCurve.swift     Combined hardware + software brightness scale
│   ├── AudioOutput.swift         Detects monitor speakers without volume control
│   └── Reset.swift               Restores every screen
├── DDC/
│   ├── DDC.swift                 VCP codes, packets, checksums, reply parsing
│   ├── Arm64DDC.swift            DDC/CI over IOAVService, matched by EDID
│   └── IOKitPrivate.swift        Bindings for the private IOAVService functions
├── Keyboard/
│   ├── KeyboardReader.swift      Brightness keys read from keyboards (IOHIDManager)
│   └── MediaKeys.swift           Media-key event tap
├── Remote/
│   ├── RemoteControl.swift       Settings, pairing, API actions, state JSON
│   ├── RemoteServer.swift        Local-network HTTP server (NWListener)
│   ├── RemoteHTTP.swift          Request parsing and responses
│   ├── RemoteRoutes.swift        Routes and screen-name matching
│   ├── RemotePairing.swift       Pairing codes and hashed keys
│   ├── RemoteShortcuts.swift     Siri shortcut files, signed with `shortcuts sign`
│   └── RemotePage.swift          The iPhone web page (self-contained HTML)
└── Support/
    ├── Preferences.swift         UserDefaults-backed settings
    ├── LoginItem.swift           Start at Login (SMAppService)
    └── Log.swift                 Unified logging categories
Tests/SwitchboardTests/           Unit tests, one file per area
scripts/                          make-app.sh (build/package/install), release-notes.sh
Resources/                        Info.plist, app icon (AppIcon.svg is the source)
```

## How it works

| Feature | Implementation |
|---|---|
| Standby and wake | DDC/CI *Set VCP Feature* `0xD6` (power mode): `0x05` standby, `0x01` on |
| Brightness, contrast, volume | DDC/CI VCP `0x10`, `0x12` and `0x62`, read back with *Get VCP Feature* |
| DDC/CI transport | I²C through `IOAVService` (private IOKit symbols on Apple Silicon). Each framebuffer is matched to its DCP AV service through the IORegistry, scored on the EDID's vendor, product, serial and name. |
| Software disconnect | `CGSConfigureDisplayEnabled` (undocumented), completed `.forAppOnly`. Other screens don't blank, and macOS reconnects the screen when the app exits. |
| Software dimming | Display gamma tables (`CGSetDisplayTransferByTable`), which Quartz restores when the app exits |
| Resolution | Scaled modes from `CGDisplayCopyAllDisplayModes`, applied with `CGConfigureDisplayWithDisplayMode` |
| Monitor speakers | Core Audio finds HDMI/DisplayPort output without a volume control; volume is set over DDC/CI |
| Brightness keys | `IOHIDManager` reads consumer, Apple top-case and F1/F2 usages; a `CGEventTap` handles system media-key events |
| iPhone remote | `NWListener` HTTP/1.1 server, one request per connection, 64 KB request limit. See [remote-api.md](remote-api.md). |
| Siri shortcuts | Shortcut property lists built in code, signed with `/usr/bin/shortcuts sign`, opened in the Shortcuts app |
| Start at Login | `SMAppService` |

The DDC/CI approach on Apple Silicon follows the open-source
[m1ddc](https://github.com/waydabber/m1ddc) and
[MonitorControl](https://github.com/MonitorControl/MonitorControl) projects.

## Design principles

- **One source of state.** `DisplayController` is a `@MainActor`
  `ObservableObject` that owns every screen's state; views only render it and
  call its methods. The iPhone remote goes through the same methods, so it
  follows the same rules as the menu.
- **DDC/CI is serial and off the main thread.** All traffic runs on one serial
  queue. Slider changes are coalesced so only the latest value per control is
  in flight.
- **Nothing can get stuck.** Disconnects are app-scoped and gamma changes are
  per-process, so macOS undoes both if the app exits or crashes. The last
  screen that's on can't be switched off.
- **No `@State`.** On recent SDKs `@State` is a macro whose compiler plugin
  ships only with full Xcode, so views keep no local state.
- **Pure logic is testable.** Packet encoding, reply parsing, brightness
  curves, key decoding, HTTP parsing, routing, pairing and shortcut
  generation are free of hardware and covered by unit tests.

## Versioning and releases

- `VERSION` holds the version, following [Semantic Versioning](https://semver.org/).
- `scripts/make-app.sh` stamps it into the app's Info.plist. The build number
  (`CFBundleVersion`) is the number of commits, so it always increases. A
  pre-release label (`2.1.0-beta.1`) is kept in `SwitchboardVersion` and shown
  in the menu.
- The app is ad-hoc signed with a designated requirement naming only its
  bundle identifier, so macOS privacy permissions carry over between builds.
- The [Release workflow](../.github/workflows/release.yml) publishes `VERSION`
  as a GitHub release, using its `CHANGELOG.md` section as the notes (via
  `scripts/release-notes.sh`). See [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
