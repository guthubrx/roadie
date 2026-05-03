# ADR-005 — Dock scripting addition injection blocked on macOS Tahoe 26

🇬🇧 **English** · 🇫🇷 [Français](ADR-005-tahoe-26-osax-injection-blocked.fr.md)

**Date**: 2026-05-01
**Status**: Accepted
**Triggering spec**: SPEC-004 fx-framework (post-delivery)
**Affected family**: SPEC-004 → SPEC-010 (SIP-off visual effects)

## Context

ADR-004 (2026-05-01) authorized the SPEC-004+ family to use Dock scripting addition + private SkyLight writes **under 6 cumulative conditions**. The family was delivered and merged (SPEC-004 framework + SPEC-005 through SPEC-010, 6 modules).

During the first end-to-end deployment on the dev machine (macOS Tahoe 26.2 build 25C56, Apple Silicon arm64e, SIP fully disabled), **the daemon, the `.dylib` modules, and the osax bundle all compiled and installed correctly, but the osax is never loaded by Dock**. No error, no log, no trace: complete system-side silence.

### Verified technical state

All documented preconditions (yabai wiki, SpecterOps blog 2025-08, macOS 14+ scripting addition archive) are met:

| # | Precondition | Verified state | Command |
|---|---|---|---|
| 1 | SIP fully disabled | ✅ `disabled` | `csrutil status` |
| 2 | Boot-args arm64e preview ABI | ✅ `-arm64e_preview_abi` | `nvram boot-args` |
| 3 | Bundle compiled arm64e (Pointer Auth) | ✅ `Mach-O 64-bit bundle arm64e` | `file .../MacOS/roadied` |
| 4 | Ad-hoc non-hardened signature | ✅ `flags=0x2(adhoc)`, hardened runtime absent | `codesign -dvvv` |
| 5 | Bundle root:wheel in `/Library/ScriptingAdditions/` | ✅ Placed via admin popup | `ls -la` |
| 6 | Library validation globally disabled | ✅ `DisableLibraryValidation = 1` | `defaults read /Library/Preferences/com.apple.security.libraryvalidation` |
| 7 | Bundle Info.plist `OSAXHandlers` valid | ✅ Identified `local.roadies.osax` | `plutil -p Info.plist` |
| 8 | SkyLight private headers linked (target arm64e-macos14) | ✅ Linked, symbols present | `nm` on the bundle |

### Observed symptoms

1. `osascript -e 'tell app "Dock" to load scripting additions'` ⇒ **localized AppleScript parse error** (-2740/-2741: "scripting additions" interpreted as a plural class name by the fr_FR parser). All workarounds (`LANG=en_US.UTF-8`, `tell application "AppleScript"` blocks, `osascript -l AppleScript`) failed.
2. Alternative force-load attempts (relaunching Dock via `killall Dock`, login/logout, reboot): **`+[ROHooks load]` is never called**, no trace in `log show --predicate 'subsystem == "local.roadies"'` or `log stream --process Dock`.
3. No crash report (`~/Library/Logs/DiagnosticReports/Dock-*.ips` empty for the period).
4. AMFI logs nothing (`log show --predicate 'eventMessage CONTAINS "AMFI"'` empty for the bundle).

### Community triangulation

- **yabai PR #2644** (Tahoe scripting addition support): opened 2025-06, **still unmerged** as of 2026-05-01. Multiple contributors report the same symptom: properly signed arm64e bundle + SIP off + boot-args, Dock silently ignores it.
- **Hammerspoon issue #3698**: `hs.spaces` (which uses a similar CGS injection mechanism) broken since Sequoia 15.0, never fixed.
- **SpecterOps blog "Apple's Scripting Additions Death March"** (August 2025): forensic analysis showing that Apple added a silent check on the `loginwindow` / `launchd` side that rejects any third-party scripting addition not signed by Apple, regardless of SIP/AMFI/library validation settings.

The convergent empirical conclusion: **Apple has effectively (de facto) killed the scripting addition mechanism on Tahoe 26 for third-party bundles, with no official documentation or error message**.

## Decision

**Accept the limitation**: the SPEC-004+ family remains merged and delivered, the framework works correctly (the 6 `.dylib` modules load via `dlopen` and receive their events), **but no CGS visual effect reaches Dock until Apple or the yabai/Hammerspoon community finds a replacement mechanism**.

**No speculative investment** in workarounds (Mach thread injection via `task_for_pid` → estimated 6h+ for a fragile proof-of-concept, out of scope for the constitution G' minimalism).

**Active monitoring**: watch yabai PR #2644 and the ecosystem (Hammerspoon, AeroSpace, Übersicht) to detect when a new injection pattern emerges.

## Current runtime state (post-delivery)

### What works (without injected osax)

| Capability | Source | Works? |
|---|---|---|
| BSP/master-stack tiling | SPEC-002 | ✅ |
| Stage Manager (⌥1/⌥2 shortcuts) | SPEC-002 | ✅ |
| Multi-desktop awareness (per-desktop state) | SPEC-003 | ✅ |
| Drag-to-adapt | SPEC-002 | ✅ |
| Click-to-raise | SPEC-002 | ✅ |
| 13 BTT shortcuts | SPEC-002 | ✅ |
| `roadie fx status` (CLI) | SPEC-004 | ✅ shows 6 loaded modules |
| `dlopen` of 6 `.dylib` modules + event dispatch | SPEC-004 | ✅ |
| NSWindow border overlays (roadie's own window) | SPEC-008 | ✅ visual outline |
| CAKeyframeAnimation pulse on focus change | SPEC-008 | ✅ |
| `roadie events --follow` (stable JSON-lines stream, no broken pipe) | SPEC-003+ | ✅ |

### What is inert (requires osax)

| Capability | Source | State |
|---|---|---|
| Shadowless (suppress third-party window shadows) | SPEC-005 | 🟡 module loaded, silent no-op |
| Inactive window dimming | SPEC-006 | 🟡 same |
| Per-app baseline alpha | SPEC-006 | 🟡 same |
| Stage hide via alpha=0 | SPEC-006 | 🟡 `HideStrategy.corner` fallback active |
| Window fade-in / fade-out | SPEC-007 | 🟡 same |
| Horizontal slide on workspace switch | SPEC-007 | 🟡 same |
| Crossfade stage switch | SPEC-007 | 🟡 same |
| Resize animation (interpolated frame) | SPEC-007 | 🟡 same |
| Frosted glass blur | SPEC-009 | 🟡 same |
| `roadie window space N` (cross-desktop move) | SPEC-010 | 🟡 same |
| `roadie window stick` | SPEC-010 | 🟡 same |
| `roadie window pin` (always-on-top at CGS level) | SPEC-010 | 🟡 same (NSWindow level managed on roadie's borders side, OK for roadie's own windows) |

### Partial case

| Capability | State |
|---|---|
| CGS-level borders on third-party windows (floating palettes) | roadie's NSWindow overlay remains correct on standard windows; on native `.floating` palettes (Photoshop, Sketch), the overlay may appear below without `SLSSetWindowLevel` on the third-party side |

## Consequences

### Positive

- **Zero regression on the core** (SPEC-001/002/003): modules load as no-ops; the vanilla daemon keeps running exactly as before.
- **Architecture dry-run validated**: the entire framework (FXLoader, OSAXBridge, AnimationLoop, BezierEngine) is empirically tested on the no-op path. The day injection becomes possible again, **no code migration** — the osax just loads.
- **Negligible sunk cost**: the framework represents ~2,000 LOC aligned with the yabai industrial pattern. If Apple reverses course (unlikely) or the community finds a workaround, switching takes a few hours.
- **ADR-004 compartmentalization conditions preserved**: none of the 6 conditions is violated by this runtime unavailability — condition #3 ("no crash with SIP fully on / osax absent") is in fact validated 100% since every machine is in that configuration by default.

### Negative

- **User promise partially unmet**: the "HypRoadie" experience (Bézier curves, focus dimming, crossfade) announced in SPEC-004+ is **inert** on Tahoe 26. Documents to update: README + SPEC-004 spec.md must be amended to explicitly flag the Tahoe limitation (status `Delivered (runtime-blocked Tahoe 26)`).
- **Attack surface unnecessarily open**: the dev machine has SIP partial off + library validation off for nothing (the effects don't run). User recommendation: **re-enable SIP** (`csrutil enable`) until injection works, and re-disable it when a workaround emerges. The vanilla daemon is unaffected.
- **Confidence in the scripting addition pattern eroded**: ADR-004 relied on "10 years of yabai production". That stability is over. Any future SPEC must treat this pattern as **provisional and not guaranteed**.

### Neutral

- **No LOC impact**: no lines to remove. The framework stays ready.
- **Only user documentation needs updating** (README + SPEC-004 status).

## Alternatives considered

### A. Revert the SPEC-004+ family

Undo all merges, keep only SPEC-001/002/003.

**Rejected**: pure economic sunk cost. The code works, the tests pass, the graceful no-op is exemplary. Reverting = discarding ~2,000 clean LOC for nothing. If injection returns, everything would have to be rewritten.

### B. Invest in Mach thread injection (`task_for_pid`)

Alternative pattern: from a root process, attach to Dock via `task_for_pid` + inject a thread that loads the `.dylib`.

**Rejected**:
- Estimated 6–12h for a fragile POC (each macOS update can break it).
- Requires `com.apple.security.cs.debugger` entitlement, Apple-signed (impossible without a paid Developer ID + provisioning profile for the user).
- Even larger attack surface (permanent root process).
- Out of scope for constitution G' (LOC minimalism).

### C. Request `com.apple.private.security.scripting-addition-loading` entitlement (yabai PR #2644 style)

Bypass attempt via custom entitlement embedded in the bundle.

**Rejected**: the yabai #2644 thread shows that Apple also ignores this entitlement on Tahoe 26 if the signature is not from Apple. Pure mimicry.

### D. Wait + monitor (SELECTED)

Accept the limitation, keep the framework ready, wait for a positive community signal (yabai PR merged OR new pattern published).

**Adopted**: the only economically sound option. Marginal cost = passive monitoring.

## Immediate action plan

1. **Project README**: add a "Tahoe 26 limitation" section pointing to this ADR.
2. **SPEC-004 spec.md**: amend the status from "Delivered" to "Delivered (runtime-blocked on macOS 26+, framework ready)".
3. **SPEC-005 → SPEC-010 spec.md**: add a note "Effects inert until osax is injected — see ADR-005".
4. **Dev user recommendation**: `csrutil enable` + remove `-arm64e_preview_abi` from boot-args until a positive signal. The core daemon runs identically.
5. **Watch list**: `gh issue subscribe koekeishiya/yabai 2644` (manual monthly reminder).

## Reopening conditions

This ADR becomes `Superseded` (and the SPEC-004+ family becomes fully operational) if **any one** of the following conditions is met:

- yabai PR #2644 merged + yabai-sa.dylib bundle observed functional on Tahoe 26.
- Apple publishes an official third-party scripting addition mechanism (very unlikely).
- A new emerging injection pattern (e.g., DriverKit user-space, abused Endpoint Security extensions) is documented by 2+ independent projects, stable on Tahoe 26.
- The user explicitly agrees to invest in alternative B (Mach thread injection) with its constraints (paid Developer ID + extra LOC beyond the G' budget).

In all cases: a **new ADR** will be produced to record the reopening — no silent modification of this ADR.

## References

- [yabai PR #2644 — Tahoe scripting addition support](https://github.com/koekeishiya/yabai/pull/2644)
- [Hammerspoon issue #3698 — hs.spaces broken Sequoia+](https://github.com/Hammerspoon/hammerspoon/issues/3698)
- SpecterOps blog "Apple's Scripting Additions Death March" (August 2025)
- ADR-004 — Allow SIP-off via separate opt-in modules
- Project constitution 002-tiler-stage v1.3.0 (article C')
- SPEC-004 fx-framework + spec.md `Delivered (runtime-blocked Tahoe 26)`
- Verified system state: macOS 26.2 (25C56), arm64e, SIP disabled, `-arm64e_preview_abi`, library validation off

## Authors

Project roadies, post-merge SPEC-004+ → main, 2026-05-01
