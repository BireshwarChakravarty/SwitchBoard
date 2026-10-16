# Security policy

## Supported versions

Security fixes are made for the latest release only.

## Reporting a vulnerability

Please don't open a public issue for security problems. Instead, use
[GitHub's private vulnerability reporting](https://github.com/BireshwarChakravarty/SwitchBoard/security/advisories/new)
for this repository. Include steps to reproduce and the affected version.
You can expect an acknowledgement within a week.

## Permissions and scope

Switchboard asks for two macOS permissions, both used only for keyboard keys:

- **Input Monitoring**, to read brightness keys from keyboards. Only
  brightness keys are acted on; all other input is ignored and never stored
  or logged.
- **Device Control and Data Access** (Accessibility), for an event tap that
  handles brightness, volume and mute keys. Every other event passes through
  unchanged.

Switchboard never contacts the internet. The optional iPhone Remote, off by
default, serves an HTTP API on the local network while it's on. Only paired
devices can use it: pairing takes a six-digit code shown on the Mac, five
wrong codes replace the code, and keys are random 256-bit values stored only
as SHA-256 hashes. The traffic isn't encrypted, so the remote is meant for
trusted networks. See [docs/remote-api.md](docs/remote-api.md).

Switchboard uses undocumented macOS functions for DDC/CI on Apple Silicon and
for disconnecting screens, and it changes display settings only for as long as
it runs.
