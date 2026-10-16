Switchboard is a menu-bar control panel for the monitors on a Mac mini
(Apple Silicon, macOS 26 or later).

**Download:** `Switchboard.zip` below. Unzip it and move **Switchboard.app**
to Applications. The app isn't notarized, so the first time, right-click it
and choose **Open**, then **Open** again, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Switchboard.app
```

**What it does**

- Switch each screen off and on: DDC/CI standby for monitors that support
  it, a software disconnect for those that don't. Other screens stay on.
- Brightness (hardware plus software dimming below the monitor's minimum),
  contrast, volume and resolution sliders, plus one brightness slider for
  all screens.
- Your keyboard's brightness keys control the monitors (needs Device
  Control and Input Monitoring permission). Volume keys control monitor
  speakers that macOS can't adjust.
- Match Light & Dark Mode, switch off while locked or asleep, restore the
  monitor's factory settings, Start at Login.

Built and tested automatically on macOS 26.
