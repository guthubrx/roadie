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
make status
make plan
make config-validate
make self-test
make events
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
./scripts/roadie state audit
./scripts/roadie state heal
./scripts/roadie tree dump
./scripts/roadie metrics
./scripts/roadie layout plan
./scripts/roadie config validate
./scripts/roadie self-test
./scripts/roadie daemon health
./scripts/roadie daemon heal
./scripts/roadie events tail 30
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
make self-test  # read-only runtime consistency checks
make events     # recent JSONL Roadie events
make doctor     # build + permissions + runtime diagnostics
./bin/roadie daemon health  # pid + self-test + state audit
./bin/roadie daemon heal    # repair state + reconcile layout
make stop       # stop LaunchAgent
make restart    # stop then start
```

Useful runtime inspection commands:

```bash
./bin/roadie state audit       # durable state consistency checks
./bin/roadie state heal        # conservative persistent-state repair
./bin/roadie tree dump         # display > desktop > stage > window hierarchy
./bin/roadie metrics --json    # compact counters for automation
./bin/roadie stage summon WID  # bring an inactive-stage window to the active stage
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
