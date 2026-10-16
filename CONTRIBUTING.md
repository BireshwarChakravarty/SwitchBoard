# Contributing to Switchboard

Thanks for helping improve Switchboard. This guide covers reporting problems,
setting up a development build, and what a pull request needs.

## Reporting a problem

[Open an issue](https://github.com/BireshwarChakravarty/SwitchBoard/issues/new/choose)
using the bug report form. The most useful details are:

- your Mac model and macOS version;
- each monitor's make and model, and how it's connected (USB-C,
  Thunderbolt, HDMI, a dock or adapter);
- the log while you reproduce the problem:

  ```bash
  log stream --level debug --predicate 'subsystem == "app.switchboard.Switchboard"'
  ```

DDC/CI behaviour varies a lot between monitors, so the model and connection
often explain a problem on their own.

## Development setup

You need an Apple Silicon Mac with macOS 26 and the Swift toolchain. The
Command Line Tools are enough (`xcode-select --install`).

```bash
git clone https://github.com/BireshwarChakravarty/SwitchBoard.git
cd SwitchBoard
swift build          # debug build
swift test           # unit tests
swift run            # run without installing
./make-app.sh        # build and install into /Applications
```

The app's behaviour depends on real monitors, so test changes with the
installed app as well as with `swift test`.

## Guidelines

- **No `@State` in SwiftUI views.** On recent SDKs `@State` is a compiler macro
  whose plugin ships only with full Xcode, so using it breaks builds that use
  the Command Line Tools. Keep view state in `DisplayController` instead.
- **Keep DDC/CI off the main thread.** All DDC traffic goes through
  `DisplayController`'s serial queue. DDC messages are slow, and monitors
  expect one at a time.
- **Never leave a screen stuck.** Anything that switches off, disconnects or
  dims a screen must be undone by Quit, by Reset to Defaults, and when the app
  exits unexpectedly.
- **Log, don't print.** Use the categories in `Log.swift`. Never log ordinary
  keystrokes or other personal data.
- **Add tests for pure logic.** Packet encoding, parsing, curves and key
  decoding are covered in `Tests/SwitchboardTests`. Follow that pattern for new
  logic that doesn't need hardware.
- Match the existing style: Swift API Design Guidelines, four-space
  indentation, and doc comments that explain *why*.

## Pull requests

1. Create a branch from `main`.
2. Make your change, with tests where possible.
3. Run `swift build` and `swift test`, and try the change with the installed app.
4. Add an entry under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
5. Open a pull request describing what changed, why, and how you tested it,
   including which monitors you used.

Continuous integration builds and tests every pull request on macOS 26.

## Releases

Maintainers publish a release by running the **Build and test** workflow
manually with a version number, for example `2.0.0`. The workflow builds,
tests and packages the app, creates the tag, and publishes the release with
`Switchboard.zip` attached. Update `CFBundleShortVersionString` in
`Resources/Info.plist` and the changelog first.
