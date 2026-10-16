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

Switchboard makes no network connections. It uses undocumented macOS functions
for DDC/CI on Apple Silicon and for disconnecting screens, and it changes
display settings only for as long as it runs.
