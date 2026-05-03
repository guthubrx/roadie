# ADR-008 — Code signing, Accessibility permissions, and distribution strategy

🇬🇧 **English** · 🇫🇷 [Français](ADR-008-signing-distribution-strategy.fr.md)

**Date**: 2026-05-03 | **Status**: Accepted for the dev phase. Open for beta/release phases.

## Context

Developing roadie surfaced a recurring problem: after every daemon rebuild, the **Accessibility** permission (TCC) is silently revoked by macOS, preventing the daemon from starting (`AXIsProcessTrusted` returns false → exit 2). The launchd `KeepAlive` re-spawns in a loop, logging `Accessibility permission missing`, with no obvious UI-side fix since on macOS Sonoma+ the Privacy & Security pane rejects adding a bare binary (drag-and-drop or `+` are rejected).

Three distinct sub-problems to clarify in a single decision:

1. **The binary must be inside a `.app` bundle.** On Sonoma/Sequoia, the Accessibility pane rejects bare binaries. Apple DTS (Quinn the Eskimo) has publicly confirmed that running a daemon "like a user" is unsupported; the official pattern is to wrap the binary in a bundle.
2. **TCC anchors the permission to the code signature, not the path.** Every `swift build` produces a different ad-hoc signature → TCC treats the binary as a new program and drops the existing grant. The canonical solution (yabai, AeroSpace, and others): sign with a stable self-signed certificate, identical across rebuilds, which preserves the TCC identity.
3. **At least two roadie installs coexisted on the dev machine** (`/Applications/Roadie.app` + `~/Applications/roadied.app`), with different binaries: one pointed to by a launchd plist, the other by a `~/.local/bin/roadied` symlink. When a crash occurred, launchd auto-restarted the old build while `cp` commands from the dev workflow were updating the other. Source of persistent disk-state ↔ in-memory binary desync.

## Decision

### 1. **Dev** installation architecture (maintainer's machine)

A single canonical install:

| Element | Path | Role |
|---|---|---|
| Daemon binary (real file) | `~/Applications/roadied.app/Contents/MacOS/roadied` | The only executed binary. TCC anchored here. |
| Dev symlink | `~/.local/bin/roadied` → bundle above | So `cp .build/debug/roadied ~/.local/bin/` dereferences and updates the bundle. Preserves the existing dev workflow. |
| CLI client binary | `~/.local/bin/roadie` (real file) | IPC client. Also signed for consistency. |
| Rail binary | `~/.local/bin/roadie-rail` (real file) | Launched manually by `install-dev.sh`, not by launchd. |
| LaunchAgent | `~/Library/LaunchAgents/com.roadie.roadie.plist` | `RunAtLoad=true`, `KeepAlive.Crashed=true`, points to `~/Applications/roadied.app/Contents/MacOS/roadied`. |
| Dev certificate | `roadied-cert` (login keychain, Code Signing type, Self Signed Root) | Stable identity. Created once via Keychain Access > Certificate Assistant. |

Any other roadie `.app` is forbidden (orphan `/Applications/Roadie.app` bundles must be deleted on first detection).

### 2. Single dev workflow: `scripts/install-dev.sh`

This script is **the only** entry point for propagating a new build to the system:

1. `swift build` (anaconda PATH override — project MEMORY.md rule).
2. `launchctl bootout` of the current daemon + `pkill` of rail and `events --follow` zombies.
3. `cp .build/debug/{roadied,roadie-rail,roadie}` to the 3 targets.
4. Creates the bundle `Info.plist` if absent (CFBundleExecutable=roadied, LSUIElement=true).
5. **`codesign -fs roadied-cert`** on each of the 3 binaries (preserves the Accessibility grant).
6. `launchctl bootstrap` of the LaunchAgent + manual relaunch of roadie-rail.

Any other binary update method (manual editing, direct `cp`, `brew install`, etc.) is forbidden during the dev phase — it would invalidate either the stable path, the TCC signature, or both.

### 3. Persistent TCC identity

The `roadied-cert` certificate is a self-signed root, Code Signing type, in the login keychain. It is shared across the 3 binaries (daemon, rail, CLI). It contains **no personal information** (just a certificate name), is never committed to the repo. Each project developer creates it manually — its content does not need to be identical across developers; it is a naming convention only.

Consequences:
- Accessibility permission granted **once** to the binary `~/Applications/roadied.app/Contents/MacOS/roadied`. It survives all rebuilds.
- If the cert is deleted from the keychain or expires, a new one must be generated (same name) and the grant re-ticked. This is a rare event (cert with no explicit expiration by default).
- If a developer changes the cert name (`ROADIE_CERT=foo ./scripts/install-dev.sh`), they must re-tick the grant for that new TCC identifier.

### 4. **End-user** distribution strategy (future phase, not immediate)

Three possible paths, to be locked in later:

| Path | Maintainer cost | User friction | Compatible with HypRoadie SIP-off (SPEC-004+)? |
|---|---|---|---|
| **A. Apple Notarization** | $99/year Apple Developer Program + notarization submission per release | Zero warning, only the Accessibility perm remains manual | **No** — Apple refuses to notarize code that touches Dock |
| **B. Developer ID signed, non-notarized** (AeroSpace model) | $99/year Apple Developer Program (cert renewed at expiration) | Low: Homebrew cask auto-strips the `com.apple.quarantine` xattr; user ticks Accessibility once | **Yes** for the core, keeping SIP-off modules in a separate distribution |
| **C. User-side self-sign** (yabai model) | $0 | **High**: each user generates their local cert, runs `codesign -fs` after every brew upgrade | **Yes** with no constraint |

Decision for roadie:

- **Core roadie** (SPEC-001/002/003 and family) → targets path B (Developer ID + Homebrew cask). Target audience: all macOS users, near-zero friction. Activates at the project's first public release.
- **HypRoadie opt-in modules** (SPEC-004+) → path C (user-side self-sign) with a separate `install-fx.sh` script. Target audience: power users who have deliberately disabled SIP. Consistent with the user's non-negotiable position ("full compartmentalization", SIP-off plan § P1).

Path A is **explicitly rejected** from the outset: it would foreclose any future HypRoadie evolution, which is non-negotiable.

## Consequences

### Positive

- **No more Accessibility grant losses between rebuilds**: the stable signature guarantees TCC identity. The maintainer never re-ticks.
- **Deterministic dev workflow**: `./scripts/install-dev.sh` is the single entry point; the result is reproducible.
- **Elimination of the "2 roadie installs" desync**: one `.app`, one launchd, one cert.
- **Distribution future prepared without technical debt**: the bundle structure is already conformant to Developer ID / Homebrew cask. When the time comes to switch to the Apple program, just replace `roadied-cert` with the Developer ID in the script.
- **HypRoadie SIP-off remains possible**: the decision doesn't lock the project into notarization.

### Negative

- **Manual cert creation**: each developer (and each yabai-style user if path C is activated for the core) must perform a GUI step in Keychain Access to create the cert. Not automatable. Documented in the dev README.
- **Manual Accessibility grant remains required**: the TCC API does NOT allow programmatically adding a binary to the Accessibility list (Apple DTS confirmed). This is an OS constraint, not a project one.
- **The dev cert will eventually expire** (Self Signed Root with no explicit validity = ~365 days per Keychain Access by default). At that point: re-create + re-grant. Acceptable for a solo dev; to be documented for the team phase.
- **`scripts/install-dev.sh` must stay in sync with the bundle convention**: if the bundle path moves, the cert is renamed, or the `Info.plist` structure changes, the script must follow — it is the single source of truth for the dev install.

### Neutral

- No impact on in-progress SPECs (SPEC-014/018/019). This is an orthogonal infrastructure layer.
- No impact on the HypRoadie roadmap (SPEC-004+). On the contrary, the decision prepares it cleanly.

## Alternatives considered

1. **Sign with `codesign --force --sign -`** (explicit ad-hoc signature, no cert). Rejected: produces a different signature on every rebuild → identical to unsigned behavior, drops TCC.
2. **Partially disable TCC via `tccutil`**. Rejected: requires full SIP off, out of core scope, pushes the machine's security posture far beyond what is necessary.
3. **Run the daemon as a system `LaunchDaemon` (root)** instead of a user `LaunchAgent`. Rejected: Apple DTS explicitly advises against the "root daemon + UserName=user to fake a session" pattern, and `roadied` needs the AX API which requires a GUI session.
4. **Embed the daemon in a `.xpc` service signed by a GUI `.app`**. Rejected: roadie does not (yet) have a proprietary GUI app, and this would be over-engineering for a CLI tool.
5. **Distribute via path A directly (Apple notarization)**. Rejected: blocks HypRoadie evolution — a dealbreaker per the user's position.

## Sources

- [Apple Developer Forums — daemons are unable to access files (Quinn the Eskimo, DTS)](https://developer.apple.com/forums/thread/118508)
- [Chris Paynter — *What to do when your macOS daemon gets blocked by TCC dialogues*](https://chrispaynter.medium.com/what-to-do-when-your-macos-daemon-gets-blocked-by-tcc-dialogues-d3a1b991151f)
- [yabai wiki — *Installing yabai (from HEAD)*](https://github.com/koekeishiya/yabai/wiki/Installing-yabai-(from-HEAD)) (`codesign -fs yabai-cert` workflow that inspired `roadied-cert`)
- [AeroSpace README](https://github.com/nikitabobko/AeroSpace) (Developer ID non-notarized + Homebrew cask that strips quarantine model)
- [Apple Developer — Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Apple Developer — Developer ID](https://developer.apple.com/support/developer-id/) ($99/year program)
- [rsms — *macOS distribution gist*](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) (panoramic view of signing/notarization/quarantine)
- [Apple Developer Forums — *Add application to accessibility list*](https://developer.apple.com/forums/thread/119373) (impossibility of automating the Accessibility grant)
