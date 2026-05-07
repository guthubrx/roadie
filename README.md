# roadie

Fresh rewrite of a macOS tiling window manager.

This repository intentionally starts with no production code from the previous implementation. The archived failed attempt is stored separately in `../39.roadie.old` and must be treated as documentation/reference only, never as a source of copied code.

## Direction

- Hyper-clean, maintainable Swift code.
- Stage manager is a first-class requirement, not an add-on.
- Prefer AeroSpace-style architecture when choosing between AeroSpace and yabai technical patterns.
- No SIP-off requirement.
- No SkyLight/CGS write APIs for controlling third-party windows.
- Build in small vertical slices with tests and observability from the start.

See `docs/00-product-and-architecture.md`.

## Current Test Commands

If your shell has conda enabled, use the repo scripts instead of raw `swift`
commands. They force Xcode's toolchain and avoid conda-provided linker tools.

```bash
make test
make permissions
make displays
make windows
make snapshot
make state
make plan
make doctor
```

Equivalent direct commands:

```bash
./scripts/test
./scripts/roadie permissions
./scripts/roadie display list
./scripts/roadie windows list
./scripts/roadied snapshot
./scripts/roadie state dump --json
./scripts/roadie layout plan
```

The first command that moves windows is explicit and guarded:

```bash
./scripts/roadie layout apply --yes
```

## Running The Maintainer

`roadied` can run either in the foreground or as a user `launchd` agent.

```bash
make maintain   # foreground loop
make start      # install/build bin/roadied and start LaunchAgent
make status     # inspect launchd state
make logs       # show recent daemon logs
make doctor     # build + permissions + launchd diagnostics
make stop       # stop LaunchAgent
make restart    # stop then start
```

For `launchd`, macOS may require Accessibility permission for the stable
runtime binary:

```text
/Users/moi/Nextcloud/10.Scripts/39.roadie/bin/roadied
```

If `make doctor` reports `accessibilityTrusted=false` for the daemon, add that
binary in System Settings > Privacy & Security > Accessibility, then run:

```bash
make restart
```
