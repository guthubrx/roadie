# ADR-009 — Monobinary merge: fuse roadied + roadie-rail into a single process

**Status**: Accepted
**Date**: 2026-05-04
**Spec**: SPEC-024

## Context

Until V1, roadie shipped as **two separate executables**:

- `roadied` — daemon launched by launchd, owns tiling, stages, virtual desktops, IPC server on Unix socket `~/.roadies/daemon.sock`.
- `roadie-rail` — separate `.accessory` SwiftUI app that draws the rail panel, connects to the daemon via Unix socket for state queries (`stage.list`, `windows.list`, `window.thumbnail`) and event subscription (spawns `roadie events --follow` as a subprocess and parses JSON-lines from stdout).

Over the V1 lifetime (SPEC-014, 018, 021, 022), this two-process boundary accumulated friction:

| Problem | Frequency |
|---------|-----------|
| State drift between rail's `state.stagesByDisplay` and daemon's `stagesV2` (silent desync, observable only when user clicks an outdated stage) | Recurrent — at least 6 commits across 4 SPECs |
| Two TCC grants per category (Accessibility on roadied, Screen Recording on roadied, plus rail listed by mistake in README) | Permanent friction during dev (every codesign breaks grants) |
| Two `.app` bundles to deploy, sign, maintain Info.plist, version | Operational tax |
| Two PID lockfiles, two LaunchAgents to maintain | Operational tax |
| Thumbnail PNG round-trip via base64 over Unix socket (~250 kB / 2 s × N windows) | Continuous bandwidth + latency |
| Helpers `decodeBool/Int/String` to absorb JSON serialization quirks (NSNumber vs Bool vs Int) | Tech debt |
| When daemon crashes, rail freezes on IPC timeout, requires manual restart | Recurrent during dev |

No mature macOS tiling WM splits the panel and tiling logic across processes:

- **yabai**: single binary daemon. Panels (sketchybar) are third-party, not part of yabai itself.
- **AeroSpace**: single mono-process binary, `NSApplication` with activation policy `.accessory` and a tiling thread.

The two-process design in roadie was a holdover from when the rail was prototyped as a separate experiment; over time it failed to justify its continued cost.

## Decision

Fuse `roadie-rail` into `roadied` as a single mono-binary, single-process app. Keep:

- The CLI `roadie` separate (it remains a thin Unix socket client used by BTT, SketchyBar, shell scripts).
- The Unix socket server inside the daemon process (used by the CLI and any external consumer).
- Logical module separation in Swift (`RoadieCore`, `RoadieTiler`, `RoadieStagePlugin`, `RoadieDesktops`, `RoadieRail`) — only the runtime fusion changes.

Internal architecture:

- `RoadieRail` becomes a `target` (library) instead of `executableTarget`, linked statically to `roadied`.
- A new `Sources/roadied/RailIntegration.swift` (~25 LOC) creates a `RailController` after the daemon's `bootstrap()` completes, stored in a strong property `daemon.railController`.
- `RailController.init(handler:)` accepts a `CommandHandler` (the protocol that `Daemon` already implements for the Unix socket server). The rail no longer creates a `RailIPCClient`; it creates a `RailDaemonProxy` that calls `handler.handle(request)` directly in-process. The `send(command:args:)` API is byte-compatible with the V1 client, so call sites in `RailController` are unchanged.
- A new `EventStreamInProcess` subscribes to `EventBus.shared.subscribe()` (the same actor-based bus that already feeds the public `events --follow` socket subscription path) and dispatches `DesktopEvent` to the existing `handleEvent(name:payload:)` method.

## Trade-offs

### What we gain

- **Single TCC grant per category** (Accessibility + Screen Recording on `roadied.app` only). README fixed: rail does not need any grant.
- **Single codesign per build** (~50% faster install-dev cycle).
- **Single LaunchAgent** (`com.roadie.roadie`).
- **Zero IPC drift**: the rail reads state via direct method calls, no JSON serialization, no silent mismatch.
- **Crash co-recovery**: launchd respawns one process, rail and tiling come back together.
- **−171 LOC effective Swift** measured (target was −150).

### What we lose

- **OS-level crash isolation**: a SwiftUI exception in the rail kills the whole process (tiling included). Mitigated by the fact that no rail-side crash has been observed historically (`~/Library/Logs/DiagnosticReports/roadied-*.ips` contains zero rail-attributed traces in the project's lifetime). And launchd's `ThrottleInterval=30` ensures recovery within ~30 s.
- **No independent rail upgrade**: rail and tiling now ship as one binary. Acceptable: this project is for personal daily-driving, not multi-tenant deployment.

## Why not other alternatives

| Alternative | Why rejected |
|-------------|--------------|
| Keep V1 two-process, optimize IPC (XPC mach-named instead of Unix socket) | Solves only one symptom (IPC perf). Leaves all other costs (TCC, codesign, LaunchAgent, drift). Same dev complexity. |
| One process but UI in a separate `XCApp` extension | macOS app extensions are sandboxed; cannot host the rail SwiftUI panel with `NSPanel` overlays and global mouse polling. Wrong tool. |
| Move tiling logic into the rail process, kill the daemon | Would force the user to launch the rail manually, defeating the launchd auto-start. And the rail is GUI-bound; the tiling should be running even when the user has no rail visible. |

## Consequences

- The CLI public contract (`roadie stage *`, `roadie desktop *`, `roadie display *`, `roadie window *`, `roadie events --follow`, `roadie daemon *`, `roadie fx *`) is **unchanged**. SPEC-024's `contracts/ipc-public-frozen.md` formalizes this.
- `daemon.status` exposes `arch_version: 2` and `rail_inprocess: true` to allow third-party consumers to detect V2 vs V1.
- Migration V1 → V2 is automatic: `install-dev.sh` detects and removes `~/Applications/roadie-rail.app`, kills any running rail process, removes `~/.local/bin/roadie-rail`, runs `tccutil reset` on the orphan TCC entries (`com.roadie.roadie-rail`).
- The user must re-toggle the TCC grants for `roadied.app` (Accessibility + Screen Recording) on V1→V2 upgrade because the codesign hash changes. Documented in `quickstart.md`.

## Sources

- yabai source code (github.com/koekeishiya/yabai): single-binary pattern.
- AeroSpace source code (github.com/nikitabobko/AeroSpace): NSApplication `.accessory` mono-process.
- Apple TN3127 "Apple silicon and TCC": designated requirement preserved across rebuilds when codesigned with the same identity.

---

## French summary

Fusion mono-binaire roadied + roadie-rail en un seul process NSApplication.accessory. Le rail UI vit dans le même process que le daemon, accède aux sous-systèmes via accès direct (CommandHandler, EventBus.shared) plutôt que via socket Unix. Élimine les frictions accumulées sur les SPECs 014/018/021/022 (drift state, double TCC, double codesign, double LaunchAgent, sérialisation thumbnails). Compat ascendante CLI/socket/events stricte. -171 LOC nets.
