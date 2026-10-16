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
make test       # unit tests
swift run       # run without installing
make install    # build, then cleanly install into /Applications
make help       # every task
```

The app's behaviour depends on real monitors, so test changes with the
installed app as well as with `make test`. [docs/architecture.md](docs/architecture.md)
explains how the code is organised.

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
- **Log, don't print.** Use the categories in `Support/Log.swift`. Never log
  ordinary keystrokes, pairing keys or other personal data.
- **The remote is just another client.** It must act only through
  `DisplayController`'s public methods, so it can never do something the menu
  can't.
- **Add tests for pure logic.** Packet encoding, parsing, curves and key
  decoding are covered in `Tests/SwitchboardTests`. Follow that pattern for new
  logic that doesn't need hardware.
- Match the existing style: Swift API Design Guidelines, four-space
  indentation, and doc comments that explain *why*.

## Pull requests

1. Create a branch from `main`.
2. Make your change, with tests where possible.
3. Run `make test`, and try the change with the installed app (`make install`).
4. Add an entry under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
5. Open a pull request describing what changed, why, and how you tested it,
   including which monitors you used.

CI builds, tests and packages every push and pull request on macOS 26.

## Releasing

Switchboard follows [Semantic Versioning](https://semver.org/): patch
releases (2.0.1) for fixes, minor releases (2.1.0) for new features, and major
releases (3.0.0) for changes that break existing behaviour or settings.

1. Set the new version in `VERSION`.
2. In `CHANGELOG.md`, rename **Unreleased** to `## [x.y.z] - YYYY-MM-DD`, start
   a new empty **Unreleased** section, and update the links at the bottom.
3. Commit to `main` and wait for CI to pass.
4. Run the **Release** workflow from the Actions tab.

The workflow builds, tests and packages the app, then publishes `vx.y.z` with
`Switchboard.zip` attached and the changelog section as its notes. It refuses
a version that's already released, isn't valid semver, or has no changelog
entry. A version with a pre-release label, such as `2.1.0-beta.1`, is
published as a pre-release and may come from any branch; stable releases come
from `main`.

`VERSION` is the only place the version is set; the build stamps it into the
app, so never edit the version in `Resources/Info.plist`.
