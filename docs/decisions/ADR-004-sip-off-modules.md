# ADR-004 — Allow SIP-off via separate opt-in modules

🇬🇧 **English** · 🇫🇷 [Français](ADR-004-sip-off-modules.fr.md)

**Date**: 2026-05-01
**Status**: Accepted
**Triggering spec**: SPEC-004 fx-framework
**Affected family**: SPEC-004 → SPEC-010 (framework + 6 modules)

## Context

The user expressed an explicit request (branch review `/branch` on 2026-05-01) to enable Hyprland-style aesthetic and cross-desktop manipulation features:

- Suppression / customization of third-party window shadows
- Focus dimming (alpha on unfocused windows)
- Bézier animations at 60–120 FPS on open/close/switch
- Colored borders around the focused window
- Frosted glass blur behind windows
- Programmatic cross-desktop window movement (FR-024 SPEC-003 DEFER V3)

All of these features require writing to private SkyLight APIs (`CGSSetWindowAlpha`, `CGSSetWindowShadow*`, `CGSSetWindowBackgroundBlur`, `CGSSetWindowTransform`, `CGSAddWindowsToSpaces`, etc.) which are only accessible via the **process owner of the target window**.

To reach third-party windows, the industry-standard pattern (yabai, 10 years in production) is:
1. SIP partially disabled (`csrutil enable --without fs --without debug --without nvram` on macOS 14+)
2. Cocoa scripting addition placed in `/Library/ScriptingAdditions/`
3. Injection into Dock via `osascript -e 'tell app "Dock" to load scripting additions'`
4. The injected code runs inside Dock (a privileged process with master connection) and exposes CGS calls via a Unix socket

The constitution-002 article C' v1.2.0 stated:
> "**`SLS*`/SkyLight and Dock scripting addition are forbidden** (FR-005)."

This clause blocks the entire SPEC-004+ family. It must therefore be amended — but **narrowly** — to preserve the invariant that made SPEC-001/002/003 robust: **no fragile private dependency in the core**.

## Decision

Amend article C' to version 1.3.0 to allow SkyLight write + scripting addition **exclusively in opt-in modules** loaded at runtime via `dlopen`, subject to **6 strict cumulative conditions**:

1. **Core daemon fully functional without any module**: a "vanilla" user (SIP intact, no module installed) MUST have a complete and excellent experience. SPEC-002 + SPEC-003 regression tests at 100%.
2. **Module = separate `.dynamicLibrary` target**: never statically linked into the daemon. Automatic gate: `nm roadied | grep CGSSetWindow* | wc -l == 0`.
3. **No crash when SIP is fully on**: the daemon starts normally; modules gracefully no-op (osax not loaded by Dock = OSAXBridge logs a warning, never throws an exception).
4. **Manual osax installation**: via a user-run script (`scripts/install-fx.sh`), never done automatically by roadie. The user gives explicit consent.
5. **Dedicated spec per module**: each module has its own spec, security audit, and LOC budget. No "quiet addition" that bypasses review.
6. **Disableable via config**: the flag `[fx.<module_name>] enabled = false` disables the module without removing it.

The amendment is scoped by this ADR and the new SPEC-004.

## Alternatives considered

### A. Flat refusal

Keep C' v1.2.0 strict, reject the user request.

**Rejected**: the request is legitimate and the technical path is proven (yabai, 10 years). Refusal would be dogmatic with no benefit.

### B. Full authorization in the daemon core

Directly link SkyLight writes into `roadied`.

**Rejected**: violates the project's suckless philosophy, exposes all users to macOS .X+1 fragility — including those who don't want visual effects. SIP-off attack surface imposed on everyone.

### C. Static modules with a build flag

Compile 2 daemon variants: one "vanilla" without CGS, one "fx" with it.

**Rejected**: fragments distribution (2 binaries), complicates CI testing, forces a build-time choice when the user may want to try or disable features at runtime.

### D. Opt-in modules via `.dynamicLibrary` (SELECTED)

Separate modules loaded at runtime. Core daemon unchanged. User installs what they want.

**Adopted**: combines pragmatism (the path is proven yabai-style) with invariant preservation (suckless core intact).

## Consequences

### Positive

- **Vanilla daemon strictly preserved**: no possible regression for users who don't touch SIP
- **Full compartmentalization**: removing a `.dylib` or the osax = 100% vanilla restore
- **Modular auditing**: each module has a dedicated SPEC + audit, no risk accumulation
- **Separate LOC budgets**: core ≤ 4,000 (G' unchanged), opt-in cumulative ≤ 2,720 (new SPEC-004+ family budget)
- **Explicit security consent**: the user consents via manual osax installation + SIP disabling

### Negative

- **Partial SIP off** opens a real attack surface for users who activate the modules. Explicit user documentation: "as-is, no warranty".
- **macOS .X+1 fragility**: each major update may break the pattern (cf. yabai's typical 1–4 week lag). Mitigation plan: monitor yabai upstream, clear user documentation.
- **Slightly increased build complexity**: 1 additional dynamicLibrary target (`RoadieFXCore`) + separate Cocoa bundle (`roadied.osax`). Managed by `scripts/install-fx.sh`.
- **No App Store distribution**: impossible with third-party scripting additions. Acceptable as the project never targeted the App Store (already incompatible with Accessibility daemon-style).

### Neutral

- **No backward incompatibility**: current SPEC-001/002/003 users see no difference until they manually install the modules.
- **Natural constitution evolution**: C' was strict at 1.0.0 out of caution; it adapts to 1.3.0 now that the invariants are proven.

## Guard conditions (recalled)

| # | Condition | Automatic verification |
|---|---|---|
| 1 | Core daemon 100% functional without module | SPEC-002 + SPEC-003 tests (regression) + SC-007 SPEC-004 |
| 2 | Modules as separate `.dynamicLibrary` | `nm roadied | grep CGSSetWindow* | wc -l == 0` |
| 3 | No crash with SIP fully on | Integration test `11-fx-vanilla.sh` |
| 4 | Manual osax installation | Code review: no `osascript ... load scripting additions` call in the daemon |
| 5 | Dedicated spec per module | Verified by review before merge |
| 6 | Config flag disables | Test: config `[fx.X] enabled=false` → module no-op verified |

## References

- [Disabling SIP — yabai Wiki](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
- [yabai sa.dylib injection pattern](https://github.com/koekeishiya/yabai/tree/master/sa)
- Project constitution 002-tiler-stage v1.3.0 (amended article C')
- SPEC-004 fx-framework (SIP-off family)

## Authors

Project roadies, branch `004-fx-framework`, 2026-05-01
