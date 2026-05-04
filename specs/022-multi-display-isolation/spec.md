# Feature Specification: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Feature Branch**: `022-multi-display-isolation`
**Created**: 2026-05-03
**Status**: Implemented (mergée sur main, US1+US2+US3 ✅, polish post-merge complet, daily-driver en cours)
**Dependencies**: SPEC-013 (desktop-per-display), SPEC-018 (stages-per-display), SPEC-019 (rail-renderers)
**Input**: User description: "Refactor stage state from global currentStageID to per-(display, desktop) tuple. Empty stages render nothing in the rail panel."

## Context

Roadie supports multi-display via SPEC-013 (per-display desktops) and SPEC-018 (per-display stages). However, the active stage tracking still uses a single global scalar `currentStageID` in `StageManager`. This causes two visible bugs:

- **Bug A (cross-display switch)** : clicking on a stage in display X's rail panel changes the view of display Y too, because `switchTo(stageID:)` mutates the single global scalar that drives the layout for every (display, desktop).
- **Bug B (phantom rendering)** : the SPEC-019 invariant "every (display, desktop) has at least stage 1" creates empty stages on displays without user activity. The current rail renderers (Parallax45, StackedPreviews, Mosaic, HeroPreview, IconsOnly) draw an "Empty stage" placeholder for these. The user perceives this as "fake stages with fake content" on displays they never touched.

The mental model the user expects is fully isolated triplets : each `(display, desktop, stage)` is independent. Switching a stage on display X must not affect display Y.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Click on stage of display X panel only switches display X (Priority: P1)

The user has two displays. They work primarily on the built-in. The LG rail panel shows stage 1 (empty). They click on stage 1 of the LG panel. **Expected** : the LG view does whatever it does (no-op since empty), the built-in view stays exactly as before. **Today** : the built-in's view also re-tiles based on stage 1 — wrong.

**Why this priority** : core multi-display correctness. Without this, the per-display rail panels are functionally broken — clicking them produces unexpected cross-display effects.

**Independent Test** : on a 2-display setup, switch each display's panel to a different stage and verify they stay independent. CGWindowList bounds of windows on display A unchanged after a click on display B's panel.

**Acceptance Scenarios** :

1. **Given** display A active stage = 2 and display B active stage = 1, **When** user clicks stage 3 in display B's rail panel, **Then** display B's active stage becomes 3 and display A's active stage stays at 2 (visible windows on A unchanged).
2. **Given** the same setup, **When** user uses a global keybind (Alt+1) without scope, **Then** the daemon resolves the scope from cursor position and switches only the display under the cursor.
3. **Given** the same setup, **When** user uses Alt+1 with explicit `--display 2`, **Then** display 2's active stage becomes 1, display 1 unchanged.

### User Story 2 — Empty stage renders nothing in the rail panel (Priority: P1)

The user has two displays. Built-in has stages 1 (3 windows) and 2 (1 window). LG has stage 1 (0 windows, auto-created by SPEC-019 invariant). **Expected** : LG rail panel shows the stage entry but with no thumbnail, no placeholder, no "Empty stage" text — visually nothing for that stage. The user can still tap the stage row to make it active and drag windows onto it. **Today** : a placeholder is drawn that looks like fake content.

**Why this priority** : eliminates the perceived "fake data" that confuses the user about what's actually on each display.

**Independent Test** : on a display where no stage has any window, the rail panel renders no thumbnail / no "Empty stage" placeholder. The stage row exists for interaction (click target) but its visual content area is blank or shows only the minimal click-target affordance.

**Acceptance Scenarios** :

1. **Given** stage 1 on display B has `memberWindows == []`, **When** the rail panel for display B renders, **Then** the stage cell for stage 1 contains no thumbnail, no icon, no "Empty stage" text.
2. **Given** the same empty stage, **When** the user drags a window onto its row, **Then** the window is assigned to that stage and the next render shows the thumbnail.
3. **Given** stage 1 has 1 window, **When** the user closes that window, **Then** the rail panel re-renders and the stage cell becomes blank (no placeholder).

### User Story 3 — Independent desktops per display (Priority: P2)

The user switches desktop 3 on the built-in. The LG's current desktop is unchanged (whatever it was). **Expected** : `desktop.focus 3` with no `--display` arg targets the display under the cursor, and only that display's current desktop changes. **Today** : SPEC-013 already implements this for desktops (`handleDesktopFocusPerDisplay`). Story 3 verifies it stays correct after the stage refactor.

**Why this priority** : regression safety net for SPEC-013 invariants once the stage scoping is changed.

**Independent Test** : two displays, each on different current desktops. Trigger `desktop.focus 5` from cursor on display A. Display A switches to desktop 5, display B's current desktop unchanged.

**Acceptance Scenarios** :

1. **Given** display A current desktop = 1, display B current desktop = 4, **When** `roadie desktop focus 5` with cursor on A, **Then** A.current = 5, B.current = 4.
2. **Given** the same setup, **When** `roadie desktop focus 5 --display 2`, **Then** B.current = 5, A.current = 1.

## Functional Requirements

- **FR-001** : `StageManager.switchTo(stageID:)` MUST be replaced by a scoped overload `switchTo(stageID:scope:)` that mutates only the active stage for the given (displayUUID, desktopID) tuple. Current `switchTo(stageID:)` is kept as a wrapper that resolves the scope from `currentDesktopKey` for compat.
- **FR-002** : The internal store `activeStageByDesktop[DesktopKey]` becomes the single source of truth for "active stage of (display, desktop)". The legacy scalar `currentStageID` becomes a derived property : it returns the active stage of `currentDesktopKey`.
- **FR-003** : `CommandRouter.stage.switch` handler MUST resolve the scope from request args (`display`, `desktop`) before calling `switchTo(stageID:scope:)`. No global side-effect.
- **FR-004** : The rail panel renderers (Parallax45, StackedPreviews, Mosaic, HeroPreview, IconsOnly) MUST detect `stage.windowIDs.isEmpty` and render an empty content area (no placeholder, no "Empty stage" text). The cell remains interactive for tap-to-activate and drag-drop.
- **FR-005** : The SPEC-019 invariant "every (display, desktop) has at least stage 1" MUST be preserved : the data model still creates stage 1 in `stagesV2[(uuid, 1, "1")]` for every screen at boot. Only the rendering changes.
- **FR-006** : Hide/show on stage switch MUST be scoped : when switching stage on display A, only windows whose `state.displayUUID == A` are hidden/shown. Windows on display B are untouched.
- **FR-007** : Persistence MUST survive : `_active.toml` per (display, desktop) directory continues to record the active stage of that scope. On boot, `loadActiveStagesByDesktop()` populates `activeStageByDesktop` correctly.
- **FR-008** : Existing CLI commands (`roadie stage 3`, `roadie stage 3 --display 2`) MUST continue to work with the same observable semantics. `--display` selects the target scope; absence falls back to cursor-position resolution.
- **FR-009** : The rail panel still shows the stage row even if empty, so the user can interact (tap to make it the active stage of this scope, drag a window in). Only the visual content INSIDE the cell is blank.

## Success Criteria

- **SC-001** : on a 2-display setup, no click on display B's rail panel changes the on-screen layout of display A. Verifiable by capturing window frames before and after the click.
- **SC-002** : on a display with all empty stages, the rail panel contains zero thumbnails and zero "Empty stage" placeholders. Verified by `gui` skill screenshot or inspection of SwiftUI hierarchy.
- **SC-003** : zero regression on `roadie stage 3` (CLI, single-display) — same observable behavior as before.
- **SC-004** : zero regression on SPEC-018 acceptance tests : `Tests/18-*.sh` all pass.
- **SC-005** : zero regression on SPEC-013 desktop tests.
- **SC-006** : after a daemon restart, the active stage per (display, desktop) is restored from disk to the same value as before restart.

## Out of Scope

- The `mouse_follows_focus` SPEC-016 A6 implementation is independent.
- SPEC-019 renderer effects (parallax, stacked) — only the empty-stage branch is touched.
- Performance optimisation of the per-display stage switch — implementation-time tuning, not a spec requirement.
- New keybindings for cross-display navigation — out of scope.

## Assumptions

- The DisplayRegistry returns deterministic UUIDs for each connected screen (`CGDisplayCreateUUIDFromDisplayID`), already verified by SPEC-012.
- The user has at most 2 to 4 active displays at once. The data model is general but performance is only validated for this typical case.
- The `currentDesktopKey` is well-defined at all times once the daemon is bootstrapped (set by `setCurrentDesktopKey` after every desktop change).

## Open Questions

- None for the data model. Implementation may surface edge cases on display hot-plug (handled by SPEC-013 already).
