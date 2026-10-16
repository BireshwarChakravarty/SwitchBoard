Switchboard is a menu-bar control panel for external displays on Apple Silicon
Macs running macOS 26 or later.

### New in 2.0: iPhone Remote and Siri

- **Control your screens from your iPhone:** power, brightness, contrast,
  volume and resolution, from a page you add to the Home Screen like an app.
- **Siri shortcuts:** Settings → iPhone Remote → **Add Shortcuts…** builds
  "ARZOPA On", "ARZOPA Off", "Toggle ARZOPA" and "Screen Brightness" (for your
  own screens' names) and opens them in the Shortcuts app. iCloud syncs them to
  your iPhone, so "Hey Siri, ARZOPA Off" just works. They also fit in Control
  Center and on the Action button.
- **Private by design:** off unless you turn it on, local network only, and a
  phone must pair with a code shown on the Mac.

See [iPhone Remote](https://github.com/BireshwarChakravarty/SwitchBoard#iphone-remote)
in the README for setup.

### Install

1. Download **Switchboard.zip** below and unzip it.
2. Move **Switchboard.app** to your Applications folder.
3. Switchboard is ad-hoc signed rather than notarized. The first time, run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Switchboard.app
   ```

4. For the keyboard keys, turn on **Switchboard** in System Settings → Privacy &
   Security, under both **Input Monitoring** and **Device Control and Data
   Access**. Permissions carry over from 1.0.3 and later.

### Highlights

- Switch external screens off and on, using DDC/CI standby or a software
  disconnect, without affecting your other screens.
- Combined brightness, contrast, volume and resolution for every screen, plus
  an All Screens brightness slider.
- Brightness keys for external displays, including Apple keyboards, and volume
  keys for monitor speakers.
- Match Light & Dark Mode, switch off while locked, and one Reset to Defaults.

See the [changelog](https://github.com/BireshwarChakravarty/SwitchBoard/blob/main/CHANGELOG.md)
for every change. Built and tested automatically on macOS 26.
