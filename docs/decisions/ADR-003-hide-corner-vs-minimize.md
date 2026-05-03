# ADR-003 — Hide strategy: offscreen corner (vs minimize, vs Spaces)

🇬🇧 **English** · 🇫🇷 [Français](ADR-003-hide-corner-vs-minimize.fr.md)

**Date**: 2026-05-01 | **Status**: Accepted

## Context

The stage manager (opt-in plugin) must be able to hide the windows of an inactive stage without losing them, and restore them faithfully on switch.

Options:

1. **yabai-style**: use macOS Spaces. Each stage = one Space. Switching = `yabai -m space --focus N` via scripting addition. Requires **SIP partially off**.

2. **AeroSpace-style**: move windows offscreen to `(-100000, -100000)`. Keep their original frame in memory for restoration. No Spaces, no SIP.

3. **stage SPEC-001**: native minimize via `kAXMinimizedAttribute = true`. No Spaces, no SIP, but a visible Dock animation occurs and yabai/JankyBorders re-tile on un-minimize (flicker observed in SPEC-001).

## Decision

**Option 2 (offscreen corner) as the primary strategy**, with **option 3 (minimize) available via config** for users who prefer it.

Rationale:
- Option 1 is excluded by FR-005 (no SIP disabled).
- Option 2 = AeroSpace, validated 2 years in production, no flicker because windows stay in the same Space with no significant AX state change.
- Option 3 provided as a configurable fallback because some users prefer the Dock animation as a visual indicator.

**Identified limitation** of option 2: windows moved to the corner remain in the Cmd+Tab list. The original AeroSpace ignores this issue; we add a `"hybrid"` mode (corner + native minimize) as an option to mitigate it.

## HideStrategy specification

```swift
enum HideStrategy: String, Codable {
    case corner    // move to (-100000, -100000), save the frame
    case minimize  // kAXMinimizedAttribute = true
    case hybrid    // corner + minimize (resolves Cmd+Tab)
}
```

## Consequences

### Positive

- **Fast switching** (~50 ms per window via AX setPosition vs ~250 ms minimize animation).
- **No SIP** required.
- **No interference** with other running tilers (yabai/AeroSpace don't run in parallel anyway).
- **Configurable**: the user chooses their Cmd+Tab trade-off.

### Negative

- `corner` mode = "ghost" windows in Cmd+Tab. Acceptable for many users (same as AeroSpace).
- `hybrid` mode adds the minimize latency (250 ms) and the Dock animation for hidden windows. To be evaluated empirically.

## Rejected alternatives

- **Destroying/reopening** windows: would break application state (unsaved documents, etc.). Unacceptable.
- **Hidden Space created on the fly**: would require `CGSGetSpaces` (private), close to SkyLight, out of V1 scope.

## References

- AeroSpace: `Sources/AppBundle/tree/MacWindow.swift` — `hideInCorner` / `unhideFromCorner`
- yabai: `src/space_manager.c` — `space_manager_set_active_space`
- SPEC-001: `stage.swift` cmdSwitch (native minimize)
- research.md §3 (hide strategies)
