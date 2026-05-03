# ADR-007 — Navrail × tiling coherence test matrix for agent-driven validation

🇬🇧 **English** · 🇫🇷 [Français](ADR-007-test-matrix-coherence-navrail-tiling.fr.md)

**Date**: 2026-05-03 | **Status**: Accepted

## Context

A series of coherence bugs between navrail and tiling (SPEC-018 then SPEC-019) revealed that the system's axes of variation (display × desktop × stage × tiler × renderer) interact without any exhaustive test matrix to verify that no regression has been introduced. Recent bugs include: navrail showing the same content on 2 screens, hover erasing windows, clicking a stage with no effect, empty ghost stages, 66×20 helpers polluting thumbnails, double wid assignment on disk, active stage memory lost on desktop_changed, etc.

Each bug was fixed empirically, but without a systematic test suite any fix can break another case that nobody has re-validated. Furthermore, some tests cannot be automated on the Swift side (visual validation) and require real GUI interaction (hover, drag-drop, resize).

Three requirements:

1. **Exhaustiveness**: cover ALL combinatorics of the system's axes, not just the happy paths.
2. **Consumable by an intelligent agent**: the suite must be driven by an agent (Claude Code + `gui` skill for mouse interaction) that executes each test case unambiguously, with no omission or free interpretation.
3. **Consolidated reporting**: avoid 600 result files — a single grid with one row per test, recording the verdict, the observed deviation, the applied fix, and the post-fix status.

## Decision

### Scope — combinatoric axes covered

| Axis | Values |
|---|---|
| **Displays** | 1 screen (built-in only) / 2 screens (built-in + external LG) / hot plug/unplug |
| **Desktops** | 1, 2, …, N per display (`per_display` mode) + `global` mode |
| **Stages** | 1 (immortal) / 2+ per scope (display, desktop) / empty stage / stage with > maxVisible wids |
| **Tilers** | BSP / Master-Stack |
| **Navrail renderers** | `stacked-previews` (shipped) / `icons-only` (shipped) / `hero-preview`, `mosaic`, `parallax-45` (TODO SPEC-019 US3–US5) |
| **Window types** | tiled / floating / native fullscreen / minimized / helpers (66×20) / Electron |

### Scope — interactions covered

**Passive observation**: at a given instant, does the navrail show what is tiled on screen?

**Active interactions**:
- Click on navrail thumbnail → stage switch
- Drag-drop window between 2 thumbnails → cross-stage reassignment
- Resize tiled window (split, ratio)
- Move (focus neighbor / swap)
- Cmd+Tab to window in another stage / desktop
- Click-to-raise on hidden window
- Window creation / destruction
- Desktop switch (Ctrl+→ / `roadie desktop focus`)
- Display switch (cursor / frontmost)
- Stage creation / deletion / rename (CLI + wallpaper-click + rail context menu)
- Hot-swap tiler (`roadie tiler bsp` ↔ `master-stack`)
- Hot-swap renderer (`roadie rail renderer …`)
- Daemon reload
- Screen hot plug / unplug

### Invariants to verify (referenced as `INV-N` in test cases)

1. **INV-1** The navrail of a panel shows the stages of **its own** screen (not another's)
2. **INV-2** The visible content on screen matches the wids of the active stage for the scope
3. **INV-3** Stage 1 is always present on each (display, desktop) — never "No stages yet"
4. **INV-4** 1 wid = 1 stage max (no double assignment on disk or in memory)
5. **INV-5** No 66×20 helper window in any stage
6. **INV-6** Correct hide/show on switch (offscreen `frame.x < -1000` vs on-screen `frame.x ≥ 0`)
7. **INV-7** Active stage memory per (display, desktop) is preserved through a round-trip
8. **INV-8** Panel actions propagate to the **panel's** scope, not the cursor-inferred scope

### Edge cases to include systematically

- Empty stage (renderer's neutral placeholder)
- Stage with > maxVisible wids (legible truncation "+N")
- Hot reload during drag-drop
- App crash while it is tiled
- Native macOS fullscreen
- Wallpaper-click (stage creation by clicking the desktop)
- Cursor crossing between 2 screens during a switch
- Offscreen window receiving focus (Cmd+Tab)
- Unknown renderer in TOML (typo) → fallback to `stacked-previews` + warn
- Daemon not running → rail shows a coherent offline state

### Out-of-scope combinatorics (declared impossible or untested)

- **`global` mode × 2 displays**: by construction, the rail exposes only one panel on the primary → no cross-display test.
- **`mosaic` renderer × stage with 0 wids**: deferred past US4 if ever shipped; mark as SKIP today.
- **Tiler ≠ BSP/Master-Stack**: no other tiler shipped, no test.
- **Screen hot-plug without Accessibility permissions**: daemon precondition, out of functional test scope.
- **Multiple simultaneous users on the same daemon**: not supported (PID lock SPEC-001).

These cases MUST appear in a separate table in the test matrix with the label `IMPOSSIBLE` or `OUT_OF_SCOPE` for traceability.

### What the suite does NOT do

- No automated Swift test code (XCTest) — the suite is driven manually or by agent + `gui` skill.
- No source code modification during a run (except via the "Fix applied" column in the grid, where the corrected commit/file is referenced after the fact).
- No implicit chaining — the agent running the suite does not chain tests automatically; it iterates one test at a time and fills in the grid.

Produce **a single markdown file**: `specs/019-rail-renderers/test-matrix-coherence.md`, structured in 3 sections:

### Section 1 — Context header (read by the agent)

- Suite objective, scope, hardware prerequisites (1 or 2 screens), software prerequisites (`cliclick`, daemon alive, rail alive, screens detected).
- List of invariants verified by each test (referenced by number `INV-N` in the test cases).
- Minimal glossary (scope, panel, thumbnail, on-screen frame, etc.).
- Operating procedure: test order, dependencies between tests, recovery mode if daemon crashes mid-suite.

### Section 2 — Test cases

Each test case follows a strict structured format:

```
### TC-XXX — <short title>

- **Category**: <passive observation | active interaction | edge case | hot-swap>
- **Axes**: display=<…> desktop=<…> stage=<…> tiler=<…> renderer=<…>
- **Invariants verified**: INV-1, INV-3, INV-7
- **Preconditions**:
  - <verifiable shell command>
  - <expected daemon state>
- **Action**:
  - <ordered sequence of shell commands + gui skill>
- **Expected result**:
  - **Daemon state**: <what `roadie X` must return>
  - **Visual tiling**: <what must be on screen after>
  - **Navrail visual**: <what must appear in the panel>
- **Notes**: <known pitfalls, timing, etc.>
```

Continuous `TC-NNN` numbering. Thematic grouping by prefix (TC-100 = display, TC-200 = desktop, TC-300 = stage, TC-400 = drag-drop, TC-500 = resize, TC-600 = hot-swap, TC-700 = edge case).

### Section 3 — Single evaluation grid

A **single markdown table** at the bottom of the file, with **one row per test case**. The agent fills each row after execution:

| Column | Content |
|---|---|
| `TC` | TC-XXX (primary key) |
| `Status` | `PASS` / `FAIL` / `BLOCKED` (precondition not met) / `SKIP` (hardware missing, e.g. 2nd screen) |
| `Observed` | What the agent saw (max 2 lines) |
| `Expected` | Short reminder of the expected outcome |
| `Gap` | If FAIL: nature of the deviation (1 sentence) |
| `Fix applied` | Reference to the corrected commit/file (empty if PASS) |
| `Post-fix status` | `PASS` after correction / `STILL_FAIL` / `N/A` |
| `Evidence` | Path to screenshot `/tmp/hui-tc-XXX-*.png` or extracted log |

This table is **the single source of truth** for the run. Human reading in 30 seconds: count `FAIL` entries not yet at `Post-fix=PASS`.

### Format for the agent

The agent that runs the tests receives the file as a prompt. Enforced conventions:

- All actions are shell commands **literally executable** (no pseudo-code, no "click here").
- GUI coordinates are absolute (origin 0,0 = top-left of primary screen). For the secondary screen, explicit coordinates with offset.
- Each visual action is followed by a screenshot stored as PNG under `/tmp/hui-tc-XXX-<step>.png` for traceability.
- Daemon verifications are `roadie ...` commands whose expected output is quoted word-for-word or via `grep`.
- No free interpretation: if a test expects "stage 1 visible full screen and stage 2 hidden offscreen", the expected result is verified by `roadie windows list` returning `frame.x ≥ 0` for stage 1 wids and `frame.x < -1000` for stage 2 wids.

## Consequences

### Positive

- **Executable by an agent** unambiguously → 100% reproducibility.
- **Single reporting** → one look at the grid shows the full suite state.
- **Easy regression detection**: re-running the suite after any fix produces the same grid to compare.
- **Explicit coverage**: the matrix makes untested combinatorics visible (= empty cell or SKIP).
- **Self-documenting scope**: centralized invariants prevent divergent definitions across files.

### Negative

- **Run cost**: the full suite may take 30–60 minutes manually (estimate to refine after writing).
- **Maintenance**: adding a renderer (US3–US5) or a new tiler requires extending the matrix — not automatic.
- **Subjective visual tests**: some results rely on screenshot capture + agent reading, susceptible to errors if rendering varies (e.g. DPI). Mitigation: 1% pixel-to-pixel tolerance (cf. SPEC-019 SC-002).
- **No CI**: the suite is not wired to a GitHub Actions pipeline (impossible: requires macOS + 2 screens + Accessibility permissions). Remains manual or semi-manual via local agent.

### Test ↔ fix articulation (operating mode imposed on the agent)

**Choice**: class-by-class hybrid loop (Option C), with explicit guard-rails.

**Rationale**:
- Test classes (display, desktop, stage, drag-drop, resize, hot-swap, edge-case) typically map to **a dedicated Swift module** → a fix touches one file, the risk of breaking another class is low **within the current class**.
- A full pass without fixing (Option A) accumulates cascading FAILs when class N+1 depends on a fix from class N.
- Immediate test↔fix per TC (Option B) loads the reasoning context with both testing and coding concerns simultaneously, increasing error risk.
- The class loop preserves cognitive separation (one mode at a time) while keeping cycles short.

**Imposed phases**:

```
PHASE 1 — Setup (once)
  ├─ Verify prerequisites: daemon alive, rail alive, screens detected,
  │  Accessibility permissions, cliclick installed
  └─ STOP and escalate if not OK (no infrastructure fixes by the agent)

PHASE 2 — Class loop, in order TC-100 → TC-700
  For each class:
    Step A — Read-only pass
      Run all TCs in the class, fill Status column
    Step B — If FAIL > 0 in the class
      1. Mandatory empirical diagnosis: daemon logs, screenshots,
         runtime state (`roadie windows list`, `roadie stage list …`).
         NEVER fix without observed runtime data.
      2. Identify root cause (1 fix may resolve N related FAILs)
      3. Apply fix to source code
      4. Record in grid: commit hash + modified file +
         1-sentence rationale (Fix applied column)
      5. Re-run ONLY the FAIL TCs → record Post-fix status
      6. If still FAIL → 2nd fix cycle (ONE more only)
      7. If still FAIL after 2 cycles → STOP, human escalation
    Step C — If entire class = PASS or Post-fix=PASS
      Tag commit `git tag tc-class-<name>-pass` + next class

PHASE 3 — Full regression (once, after all classes are green)
  ├─ Re-run suite TC-100 → TC-799 in READ-ONLY mode
  ├─ Any difference vs initial pass (PASS → FAIL or Post-fix=PASS → FAIL)
  │  = cross-class regression
  └─ If regression: "targeted fix" mode ONLY on the TC that changed,
     then re-run phase 3 entirely (max 2 iterations)
```

**Critical guard-rails (agent deviation forbidden)**:

| Guard-rail | Justification |
|---|---|
| **Mandatory empirical diagnosis before any fix** | Project memory `feedback_no_workarounds.md` + CLAUDE.md anti-tunnel rule "2 attempts, then observe runtime data" |
| **Maximum 2 fix cycles per class** | Beyond that, the root cause hypothesis is statistically wrong — escalate rather than tunnel-fix |
| **Every fix traced in the grid** (commit + file + 1-sentence rationale) | The human must be able to audit all changes from the run in 1 minute |
| **Commit tag per green class** | Reversibility: if phase 3 reveals a regression, roll back to the last stable tag |
| **Phase 3 is mandatory** | Cross-class regression detection — without it, a late fix can silently break an early class |
| **The agent never modifies TCs themselves** | Otherwise it could subtly adapt a test to a bug it just introduced. Matrix = read-only, grid = write-only |
| **The agent never skips a TC unless SKIP is justified** | A `BLOCKED` TC must have a documented cause (missing hardware, daemon down) — not a comfort cause ("seems hard to automate") |

### Update convention

- Adding a new test case → prefix TC in the right section, add row to grid with `Status=PENDING`.
- Modifying an existing test case → keep the same TC-XXX, append a note `Modified: YYYY-MM-DD <reason>` in the test case.
- Removing an obsolete test case → `Status=DEPRECATED` in the grid, do not delete (traceability).
- The agent running the suite **must not modify** the test cases (read-only), only the grid.

## Links

- [SPEC-018 audit-coherence.md](../../specs/018-stages-per-display/audit-coherence.md) — 19 coherence findings of which 15 are fixed, motivating this suite
- [SPEC-019 spec.md](../../specs/019-rail-renderers/spec.md) — renderer modularity, direct dependency for renderer TCs
- [Test matrix](../../specs/019-rail-renderers/test-matrix-coherence.md) — deliverable of this ADR
