Switchboard is a menu-bar control panel for external displays on Apple Silicon
Macs running macOS 26 or later.

### Install

1. Download **Switchboard.zip** below and unzip it.
2. Move **Switchboard.app** to your Applications folder.
3. Switchboard is ad-hoc signed rather than notarized. The first time, right-click
   the app and choose **Open**, then **Open** again, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Switchboard.app
   ```

4. For the keyboard keys, turn on **Switchboard** in System Settings → Privacy &
   Security, under both **Input Monitoring** and **Device Control and Data
   Access**.

### Highlights

- Switch external screens off and on, using DDC/CI standby or a software
  disconnect, without affecting your other screens.
- Combined brightness, contrast, volume and resolution for every screen, plus
  an All Screens brightness slider.
- Brightness keys for external displays, including Apple keyboards, and volume
  keys for monitor speakers.
- Match Light & Dark Mode, switch off while locked, and one Reset to Defaults
  for everything.

See the [README](https://github.com/BireshwarChakravarty/SwitchBoard#readme)
for details and the [changelog](https://github.com/BireshwarChakravarty/SwitchBoard/blob/main/CHANGELOG.md)
for every change. Built and tested automatically on macOS 26.
