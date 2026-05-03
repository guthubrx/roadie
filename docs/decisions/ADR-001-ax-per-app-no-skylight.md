# ADR-001 — Per-app AX Observer, no SkyLight, no SIP

🇬🇧 **English** · 🇫🇷 [Français](ADR-001-ax-per-app-no-skylight.fr.md)

**Date**: 2026-05-01 | **Status**: Accepted

## Context

The daemon must observe macOS window events in real time: creation, destruction, move, resize, focus. Two options:

1. **yabai-style**: combine `AXObserver` (per app) + SkyLight notifications `SLSRequestNotificationsForWindows` (private, require scripting addition injection into Dock.app, hence SIP partially disabled).
2. **AeroSpace-style**: `AXObserver` per app only, with `Task { @MainActor }` for synchronization. No SkyLight, no SIP off.

## Decision

**Option 2 (AeroSpace-style) with one addition**: subscribe to `kAXApplicationActivatedNotification` on top of the standard window events. This addition (absent from the original AeroSpace) fixes the click-to-focus bug on Electron/JetBrains apps.

Concretely:
- For each `NSRunningApplication`, create a dedicated thread with a `CFRunLoop`.
- `AXObserverCreate` + 6 notifications: `kAXWindowCreatedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`, `kAXFocusedWindowChangedNotification`, `kAXUIElementDestroyedNotification`, **`kAXApplicationActivatedNotification`**.
- In the callback, `Task { @MainActor in ... }` to dispatch to the state machine.

## Consequences

### Positive

- **No SIP dependency** → trivial installation, no complex setup procedure.
- **No scripting addition** → robust against macOS updates.
- **Reliable click-to-focus** on Electron/JetBrains apps (differentiator vs AeroSpace).
- **Modern Swift code** with Concurrency, readable and testable.

### Negative

- No access to SkyLight events (ordering changes, etc.) → certain known yabai regressions will be hard to reproduce if they depend on these events. Acceptable for the V1 scope.
- One thread per app may seem costly in theory — in practice, these threads block passively on their RunLoop, memory cost ~64 KB/thread.

## Rejected alternatives

- **Periodic polling** (100 ms): unacceptable battery consumption, visible latency.
- **NSWorkspace distributed notifications alone**: too coarse-grained, does not cover window-level events.
- **yabai+AeroSpace hybrid**: disproportionate complexity.

## References

- yabai: `src/application.c` — `application_observe()`
- AeroSpace: `Sources/AppBundle/tree/MacApp.swift`, `Sources/AppBundle/util/AxSubscription.swift`
- research.md §1 (event loop) and §4 (click-to-focus)
