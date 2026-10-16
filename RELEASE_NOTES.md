**Beta.** This pre-release adds the iPhone Remote. Everything else works as in
1.0.3, and the remote stays off unless you turn it on. If anything misbehaves,
reinstall [1.0.3](https://github.com/BireshwarChakravarty/SwitchBoard/releases/tag/v1.0.3).

### New: iPhone Remote

- Control your screens from your iPhone: power, brightness, contrast, volume
  and resolution, from a page you add to the Home Screen like an app.
- Siri and Shortcuts: **Settings → iPhone Remote → Add Shortcuts…** builds
  ready-made shortcuts ("ARZOPA On", "ARZOPA Off", "Toggle ARZOPA", "Screen
  Brightness") and opens them in the Shortcuts app. iCloud syncs them to your
  iPhone, so "Hey Siri, ARZOPA Off" just works.
- Local network only. A phone pairs once with a code shown on the Mac.

To try it, turn on **Settings → iPhone Remote** in Switchboard, then open the
address it shows in Safari on your iPhone and enter the pairing code. See
[iPhone Remote](https://github.com/BireshwarChakravarty/SwitchBoard#iphone-remote)
in the README.

### Install

1. Download **Switchboard.zip** below and unzip it.
2. Move **Switchboard.app** to your Applications folder.
3. Switchboard is ad-hoc signed rather than notarized. The first time, run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Switchboard.app
   ```

Permissions granted to 1.0.3 carry over. If macOS asks whether Switchboard may
accept incoming network connections, allow it so your iPhone can connect.
