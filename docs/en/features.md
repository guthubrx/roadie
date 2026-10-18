# Features

## Tiling

Roadie tiles the visible windows in the active stage.

Available modes:

- `bsp`: binary tree layout for terminal/code/browser workflows.
- `spatialBsp`: persistent binary tree; stored splits and ratios define the layout. `mutableBsp` and `yabai` remain aliases.
- `masterStack`: one main window and a secondary stack.
- `float`: Roadie keeps stage state but does not retile windows.

Examples:

```bash
roadie mode bsp
roadie mode spatialBsp
roadie mode masterStack
roadie mode float
roadie balance
```

Use cases:

- development with an editor as master and terminals in the stack;
- persistent BSP layouts edited with `move`, `warp`, `resize`, and drag and drop;
- multi-display operations with different modes per display/stage;
- temporary tiling pause on a `float` stage.

### Resizing with dividers

In `spatialBsp`, drag a handle in the gap between two window groups to adjust their
proportions. Other dividers keep their relative positions. The result is saved in
the tree. Native resizing with window edges remains available.

**Tiling > Resize handles** shows or hides the handles without retiling windows
(`tiling.resize_handles`, enabled by default). A handle is a contrasting short line
at the centre of a divider. JankyBorders decorations do not hide it; real windows
covering the gap remain protected. Handles only appear in a free gap
on an active, compatible stage. With no gap, use window edges or `resize`.
Changing stages or displays interrupts the gesture and discards its pending target.

Recent placement notifications are recognized even when macOS delivers them out
of order. Size refusals and learned minimums stay tied to their generation and
window context, so they do not overwrite newer gestures.

## Modular Runtime

Roadie can run as a classic monolithic daemon or as a set of separate runtime
components:

- `tiler`: applies layouts and keeps tiled stages consistent;
- `rail`: renders the stage rail and thumbnails;
- `border`: draws the focus border overlay;
- `focus-mouse`: handles focus-follows-mouse;
- `titlebar-menu`: shows the title-bar right-click context menu (drag and drop onto the rail is handled by `rail`);
- `target-mode`: exposes keyboard targets, grids, and target activation.

Restore safety is not a separate component: it runs inside `roadied run` and `roadied tiler`. The old `roadied restore-safety` command still exists, but it only prints a message and exits with code 0.

`roadied run` and `roadied tiler` share one instance lock (`~/.roadies/roadied.lock`), so only one of them can run. A second instance exits with code 1. Use one launcher at a time: the LaunchAgent, `make dev-start`, or `./scripts/start-modular`. The tiler writes `~/.roadies/roadied.pid`; the other components write `<name>.pid`.

Start the full modular profile:

```bash
./scripts/start-modular
roadie query components
roadie daemon health
```

This is useful today for observability and targeted debugging: each component
has its own process, lock file, and stdout/stderr logs under `~/.roadies`.

It also creates the foundation for companion-mode usage. In that model, Roadie
can eventually provide stages, rail, borders, focus helpers, target mode, or
restore safety beside another window manager such as yabai or AeroSpace instead
of always owning the full tiling loop. The standard modular script still starts
the tiler, so explicit stage-only or overlay-only profiles remain experimental
future work rather than a stable public contract.

## Stages

A stage is a named group of windows inside a Roadie desktop. Only the active stage is visible; inactive stages are hidden but restorable.

```bash
roadie stage list
roadie stage create 4
roadie stage rename 4 Comms
roadie stage switch 2
roadie stage assign 2
roadie stage switch-position 2
roadie stage assign-position 2
roadie stage switch-visible next
roadie stage switch-visible prev
roadie stage assign-empty
roadie stage summon WINDOW_ID
roadie stage move-to-display 2
roadie stage move-to-display right --no-follow
```

The `*-position` variants follow the visible nav rail order. They are intended
for user shortcuts such as Alt-1, Alt-2, Alt-3.
`stage switch-visible prev|next` cycles through non-empty stages in nav rail
order. `stage assign-empty` sends the active window to the next unnamed empty
stage, creating one if needed.

A stage can also be sent to another display from the nav rail context menu. The
focus behavior is controlled by `[focus].stage_move_follows_focus` and can be
overridden per command with `--follow` or `--no-follow`.

Use cases:

- keep separate `Focus`, `Comms`, and `Docs` stages;
- hide a context without closing apps;
- bring a specific window back to the active stage with `stage summon`.

## Display Parking

Roadie treats a disconnected display as a temporary topology change, not as a
reason to destroy or merge stage state.

When a display disappears:

- non-empty stages from that display are parked as distinct stages on a remaining display;
- their names, mode, members, groups, focus metadata, and relative order are kept;
- empty stages stay as hidden restoration metadata;
- the active stage on the host display is not replaced by the parked stages.

When the display comes back, Roadie restores the current parked stages to that
display if it can recognize the display safely. Recognition first uses the
previous display ID, then a conservative fingerprint based on name, size,
visible size, position, and main-display hint. If several displays match equally,
Roadie refuses the automatic restore and leaves the parked stages visible.

Use cases:

- unplug a laptop from a monitor without losing the monitor's stages;
- keep working on the parked stages while the monitor is absent;
- replug the monitor and have those stages return without collapsing into one stage.

## Nav Rail

The nav rail shows stages with windows first, followed by named empty stages.
Scroll the rail when the cards exceed the display height. Destination menus and
the reorder preview follow the same order. Dragging reorders stages within their
group: occupied or empty. Anonymous empty stages remain available
through the next-empty-stage action.

Window thumbnails can also expose their presentation state. A `maximized`
window stays in its normal stage and is marked with a four-corner border. A
`nativeFullscreen` window is marked with a continuous border to show that macOS
fullscreen semantics may apply.

Main interactions:

- click a stage to activate it;
- keep empty rail clicks inert by default, with an opt-in `empty_click_hide_active` setting for switching to an empty stage;
- drag a thumbnail to another stage to move that window there;
- drag a thumbnail into the active workspace to summon it;
- drag an application window by its title bar onto a stage to move it there;
- drag an application window by its title bar onto empty rail space to create or use an empty stage;
- drag a stage with the right mouse button to preview its destination and the new card order; release to apply, or release outside the rail to cancel;
- right-click a stage without dragging to open its menu: rename the stage, send it to another display, or send a window to another stage.

macOS-reserved areas such as the menu bar are ignored by empty rail click handling.

Stage labels in the nav rail are configurable. By default, they are drawn below
the thumbnails, in the stage accent color, positioned so roughly two thirds of
the label remains visible.

```toml
[fx.rail.stage_labels]
enabled = true
color = "stage"      # or a hex color, e.g. "#6BE675"
font_size = 11
font_family = "system"
weight = "semibold"
alignment = "center" # left | center | right
opacity = 0.72
offset_x = 0
offset_y = 0
placement = "below" # above | below
z_order = "below"   # below | above
visibility_seconds = 0 # 0 = always visible, otherwise duration after reveal
fade_seconds = 0.35
```

When `visibility_seconds` is greater than `0`, stage names are hidden by default.
The `roadie rail labels show` command shows them for that duration, then fades
them out over `fade_seconds`.

If `enabled = false`, the title bar context menu no longer lists anonymous empty
stages one by one. It keeps stages that contain windows and adds one `Next empty
stage` destination.

## Title Bar Context Menu

Roadie can show a context menu when you right-click the top band of a managed window. Right-clicks inside application content are left to the application.

TOML activation:

```toml
[experimental.titlebar_context_menu]
enabled = true
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
double_click_maximize = false
```

### Title Bar Double-Click

A double-click in the same top band shows the window on its own, with Roadie maximize
keeping the rail clear. A second double-click restores the layout, like
`roadie toggle maximize`. This setting (`double_click_maximize`, off by default) does not
depend on the right-click menu.

macOS already acts on this double-click and Roadie cannot stop it. Roadie therefore acts
only when the macOS setting "Double-click a window's title bar to" is "Do Nothing"
(System Settings > Desktop & Dock). Otherwise, `roadie daemon health` reports it in the
`macos-window-settings` check.

## New Window Placement

By default, a new window joins the current stage on the active display. Opening
a terminal with ⌘N keeps it in your workspace even when the pointer is on another
display. Roadie adds it to the layout as soon as it is available. Popups, dialogs,
and non-tileable windows are not affected.

Choose the destination in **Settings > Tiling > New window display**
(**Tuilage > Écran des nouvelles fenêtres** in the interface). Saved choices are
preserved; Reset selects the active display.

Choosing the active display can also improve perceived responsiveness by limiting
window transfers and layout changes across displays. The effect depends on the
application's initial placement and the displays in use.

```toml
[window_placement]
new_apps_target = "focused_display" # default; mouse | focused_display | macos
```

- **Active display (recommended)** (`focused_display`, default): the current stage on Roadie's active display.
- **Pointer display** (`mouse`): the current stage on the display under the pointer.
- **macOS placement** (`macos`): the display initially chosen by the application and macOS.

In the configuration file, use these exact lowercase values without extra spaces.
An invalid value falls back to `focused_display`.

Available actions:

- float the window in its stage, outside tiling;
- pin the window across all stages on the current desktop;
- pin the window across all Roadie desktops on the same display;
- remove a window pin;
- send the window to another stage;
- send the window to another Roadie desktop;
- send the window to another display.

Use cases:

- keep a video, reference document, or terminal visible while switching stages;
- keep a window visible across all desktops on one display without duplicating or retiling it;
- move a window without looking up its ID;
- keep current focus while filing a window elsewhere;
- avoid popups and dialogs by limiting the menu to managed tileable windows.

Window pins do not copy a window into multiple stages. The window keeps one
home context, but Roadie does not hide it while the pinned desktop or display is
active. A pinned window is excluded from automatic layout to avoid moving other
windows unexpectedly.

### Floating Window

`roadie toggle floating` floats the active window in its stage. It leaves tiling:
the other windows take its space, and you place it by hand. It stays attached to
its stage: hidden when you switch stage, back in the same place when you return.
Run the command again to put it back into tiling.

The title bar "Fenêtre" menu also offers "Flotter dans cette stage" (float in this
stage) and "Revenir au tuilage" (return to tiling). On a window already pinned to a
desktop, the command removes the pin and returns the window to tiling. No shortcut
is set by default: bind the command to a key in BetterTouchTool or Karabiner.

The state survives a Roadie restart. An earlier Roadie version still reads the
state file: it treats a floating window as a pin on this desktop, visible on all
of its stages.

## Roadie Desktops

Roadie desktops are virtual. They do not create or control native macOS Spaces.

```bash
roadie desktop list
roadie desktop focus 2
roadie desktop back-and-forth
roadie desktop summon 3
roadie desktop label 2 DeepWork
```

Use cases:

- keep `DeepWork`, `Ops`, and `Admin` desktops;
- switch between two contexts with `desktop back-and-forth`;
- bring a desktop to the current display with `desktop summon`.

## Keyboard Targets

Keyboard Targets provide a stable list of keyboard-addressable destinations for
humans and external agents. It does not replace the nav rail: it exposes the
same concepts as named, inspectable, actionable targets.

```bash
roadie targets list
roadie targets list --json
roadie targets list --filter gray
roadie targets inspect A
roadie targets pick gray
roadie targets activate A --action switch
roadie targets activate S --action focus
roadie targets activate D --action send-active
roadie targets show --json --labels-only
roadie query targets
```

Roadie targets cover windows, stages, displays, desktops, and bookmarks. Each
target has a short label (`A`, `S`, `D`, then `AA`, etc.), a stable ID, and a
list of supported actions. Labels are for humans; IDs are for scripts.

Application controls can be listed through Accessibility. Enable discovery when
you want to use them; it is off by default to keep app scanning optional.

Electron apps (T3 Code, Slack, Discord...) only publish their Accessibility
content on request. When the AX boost is active (`ax_boost_enabled` or
`additional_boost_bundle_ids`), Roadie sets `AXManualAccessibility` on the
frontmost Electron app on each session. The app builds its tree in the
background: right after launch, the first session may only show the window
(Roadie retries for at most 300 ms); later sessions are complete. Web trees are
deep: use `max_depth = 30` and `timeout_ms = 250`. Only
elements visible inside the window get a label. Turning the boost off also turns
this request off.

Each scan writes a `targets.app_scan` event (elements read, depth reached,
duration, stop reason) to `~/.roadies/events.jsonl`. Use it to tune `max_depth`
and `timeout_ms`:

```bash
grep '"targets.app_scan"' ~/.roadies/events.jsonl | tail -3
```

Some web interfaces (SolidJS, React) make elements clickable through JavaScript:
Chromium gives them no Accessibility action. Inside a web area, Roadie therefore
also labels each focusable element that contains no other focusable element
(menu entries, cards). These labels come after the classic targets.
`focusableAdded` and `rejectedRoles` in `targets.app_scan` measure this rule.

Inside a web area, Roadie only reads `AXChildren`: the AX boost attributes are
expensive there and add nothing. A heavy web page (Bluejay: about 3,300
elements) needs `timeout_ms = 700`.

CEF apps (Grayjay, Bluejay) answer no external request: their tree only exists
when the app starts CEF with `--force-renderer-accessibility` (built into
Bluejay on macOS).

### Search mode

Search mode follows the Homerow idea: type text instead of reading labels. A
global shortcut opens an input bar at the bottom of the pointer's display. Each
letter filters the targets; Return clicks the green target.

- **Shortcut**: `search_hotkey` in `[experimental.target_mode]`, default
  `command+control+alt+f`. The shortcut is customizable.
  Accepted aliases: `hyper` (= `command+control+alt`) and `ctrl`. An empty
  string disables the shortcut. Changes apply without a restart, including after
  a keyboard layout change. `roadie targets search` opens the same session.
- **All visible windows**: the bar opens immediately with the Roadie targets.
  Windows of the current Space are read in parallel in the background (at least
  2 s per window) and each one is added as soon as it is read; the bar
  updates the count chip on the right. An element hidden by a window in front gets no label.
  Targets on the pointer's display come first.
- **Matching** ignores case, accents, and spaces (`watchlater` finds
  `Watch Later`). It covers the title, value, role and, for web targets, the
  text of their children (T3 Code thread row, video card).
- **Display**: no label while the bar is empty. Result labels are green; the
  selected target has a thick frame. With 9 results or fewer, labels become
  `A`, `S`, `D`... and every result is framed.
- **Validating in another window**: Roadie focuses the window, waits until its
  app is active (at most 0.5 s), then clicks.

| Key | Effect |
|-----|--------|
| letters, digits, space | filter |
| Tab | complete the selected result's title without clicking |
| Down, Ctrl-N | next result |
| Shift-Tab, Up, Ctrl-P | previous result |
| Shift + label | select that result (`Shift+S` with few results) |
| Return | click |
| Return twice (under 0.35 s) | double-click |
| Shift-Return | right-click |
| Cmd-Return | Cmd-click (new tab) |
| `*` or `;` | show every target |
| `?` | details of the green target (role, title, text, id) |
| Esc | close without action |

Clicking outside the bar and its panel closes it. The click reaches the application
normally, including on another display. Clicking inside the bar or its panel
keeps it open. Search also closes after 60 s without a key press.
Click actions on a target require
`app_mouse_actions_enabled = true` and the bar requires `overlay_enabled = true`.

The bar stays centered at the bottom of the opening display, with a width of 640 points reduced on
narrower screens. Long text is truncated without moving the bar or overlapping
the count chip. It uses a proportional system font and a thin outline.
Input and suggestion font sizes remain independently adjustable.

A web leaf without an action (focusable-element rule) is clicked at the center
of its first visible image or text, not at the center of the element: the center
of a Bluejay History row does not react; only the thumbnail, title, and author
have a click handler.

Classic label mode stays limited to the active window. To extend it to every
visible window, set `scope = "visible_windows"` in `[experimental.app_targets]`.

### Command mode (`/`) and settings window

The search bar can also run commands, in the spirit of the `/` commands of Codex
or Claude. A `/` as the **first character** switches the bar to command mode.
Without a leading `/`, the bar stays in search mode, unchanged. To search for
text that starts with `/`, type a space first. Deleting the `/` returns to search
mode.

In command mode:

- the bar lists the commands with a short description; the list filters as you
  type (case and accents ignored);
- **Tab** completes the command or argument (command, stage number or name,
  bookmark name, setting name, category, direction) by inserting the selected
  suggestion. Subsequent Tab presses cycle through alternatives. Shift-Tab moves the selection back;
- **Up** and **Down** browse the history of the last 50 commands. The history
  survives a restart, in `~/.local/state/roadies/command-history.json`;
- **Return** runs the command on the window, stage, display and desktop that are
  active at that moment. On success, the bar closes. On failure, it stays open
  and shows a short error with the expected form; an unknown command suggests the
  closest one;
- **Esc** closes the bar without action.

Each command has the same effect as the matching `roadie` command: no new action
is created. Directions are accepted in French (`gauche`, `droite`, `haut`, `bas`)
or English (`left`, `right`, `up`, `down`). `N` is an integer greater than or
equal to 1.

| Command | Alias | Form | Effect |
|---------|-------|------|--------|
| `/move` | | `/move DIR` | moves the active window |
| `/swap` | | `/swap DIR` | swaps the active window with its neighbor |
| `/resize` | | `/resize DIR` | resizes the active window |
| `/full` | | `/full` | native fullscreen |
| `/max` | | `/max` | maximizes the window |
| `/stage` | `/s` | `/stage N` or `/stage NAME` | shows that stage |
| | | `/stage new [NAME]` | creates a stage |
| | | `/stage rename NAME` | renames the current stage |
| | | `/stage send N` | sends the active window to stage N |
| `/screen` | | `/screen DIR` or `/screen N` | focuses another display |
| `/send` | | `/send N` | sends the active window to display N |
| `/desktop` | `/d` | `/desktop N` | activates desktop N |
| `/layout` | | `/layout bsp\|spatial\|master\|float` | changes the stage layout |
| `/balance` | | `/balance` | balances the layout |
| `/split` | | `/split h\|v` | sets the split direction |
| `/bm` | `/b` | `/bm NAME` | jumps to bookmark NAME |
| | | `/bm set NAME` | sets bookmark NAME on the active window |
| `/grid` | | `/grid` or `/grid fenêtre` | opens the display grid or the active window grid |
| `/letters` | | `/letters` | opens letter mode |
| `/doctor` | | `/doctor` | diagnostics; result shown in the bar |
| `/heal` | | `/heal` | repairs the daemon state |
| `/reload` | | `/reload` | reloads the configuration |
| `/restart` | | `/restart` | restarts the daemon (no result shown) |
| `/settings` | | `/settings [category]` | opens the settings window |
| `/set` | | `/set name [value\|défaut]` | reads or changes a setting |

`/grid`, `/letters` and `/restart` run after the bar closes. With a single
display or desktop, `/screen` and `/desktop` say there is no other target.
Commands that need an active window are refused when there is none. A refusal is
written to the event log (`command.rejected`) with the command name and a reason
code, never the raw input.

The command names, the category names and the `défaut` and `fenêtre` keywords are
French. The settings window itself is in French only.

#### Settings window (`/settings`)

`/settings` opens the "Réglages Roadie" window. `/settings category` opens it on
that category (identifier without accent, or label, case ignored). With no
argument, it opens on the last category viewed (Général the first time). A second
request brings the same window to the front.

- **Left column**: a search field, then the categories: Général (General),
  Tuilage (Tiling), Stages et bureaux (Stages and desktops), Mode lettres (Letter
  mode), Grille (Grid), Recherche (Search), Rail, Bordures (Borders), Focus et
  souris (Focus and mouse), Règles (Rules), Avancé (Advanced).
- **Right area**: the settings of the category. Each setting shows a readable
  name, a description, a matching control (switch, number with limits, choice
  list, text, color), and a **Rétablir** (Reset) button when the value differs
  from the default.
- **Search**: filters the settings of every category by name and description,
  ignoring case and accents.
- **No Save button**: a change is written to the configuration file and applies
  as soon as typed input is valid, without Return or leaving the field.
  Incomplete or rejected input remains a draft; the last valid value stays active.
  Margins trigger a new layout even for a one-point change. During a mouse drag,
  tiling waits for release.
- **File tracking**: a change made elsewhere (by hand, by `/set`) appears in the
  window without reopening it.
- **Closing**: Esc, Cmd+W or the close button. The app that was in front gets the
  focus back.
- **Général** shows settings text, help and title sizes, along with the file path
  and status. Advanced tools offer Reload, Diagnostics and optional file opening.
- **Lists and tables**: built-in controls edit gap sides, window roles, apps,
  width presets, per-display overrides, named stages, stage colors and rules.
  Each complete valid row applies immediately. Changed stage names appear in the
  rail. Removing a definition does not delete its stored stage or its windows.
- **Built-in advanced editor**: rare complex fragments, including `signals.hooks`,
  use validation and explicit saving inside the window. Roadie stores hooks but
  does not currently execute them. If the file is invalid, ordinary controls are
  disabled; the full editor can repair it without an external application.

#### Inline setting (`/set`)

A setting is named `table.key`: the path of the file table, without the
`experimental.` or `fx.` prefix, then the key. Examples: `target_grid.rows`,
`app_targets.max_targets`, `rail.header.display.font_size`. The window, `/set` and
the bar completion use the same names.

| Input | Effect |
|-------|--------|
| `/set` | lists the categories |
| `/set name` | shows the current value, the default, and the allowed range or choices (`target_grid.overlay_fill_opacity = 0.4 (défaut 0.1, de 0 à 1)`) |
| `/set name value` | validates, writes to the file and applies |
| `/set name défaut` | restores the default value |

Value conversions:

- **Boolean**: `true`, `false`, `oui`, `non`, `on`, `off`, `1`, `0`.
- **Number**: decimal point or comma. A value out of range is refused, as is a
  non-integer for an integer setting.
- **Choice**: a value from the list, otherwise refused with the list.
- **Color**: `#RRGGBB` or `#RRGGBBAA`.
- **Text**: the rest of the input, without edge spaces.
- **List or array of tables**: use the built-in editor in `/settings`.
  `/set name défaut` can reset a collection.

A refusal leaves the file intact and the bar gives the reason. Roadie logs every
changed setting (`settings.changed`, setting name and result), never its value.

#### Configuration file

The file is edited **line by line**: only the key's line changes, with its
indentation and trailing comment. Comments, order and unknown settings are kept.
A missing key is added at the end of its table; a missing table, at the end of
the file. The resulting text is validated before writing, and the write is
atomic. On the first write of a Roadie session, a `roadies.toml.bak-<timestamp>`
copy is created in the same folder.

#### Label size

Sizes are independent: `target_mode.label_font_size` for letters,
`target_mode.search_label_font_size` for search and `target_grid.label_font_size`
for the grid. Values are in points, default 13, range 8 to 48. Search input uses
`target_mode.search_text_font_size`; suggestions use `target_mode.command_text_font_size`.
Frames follow the text size.

Search also offers `target_mode.search_font_family` and `target_mode.command_font_family`.
The menu lists installed families. `system`, an
empty value or a missing family falls back to the macOS font. Family and size
changes appear in the open bar without losing input. The TOML keys belong to
`[experimental.target_mode]`.

#### Limits

- Advanced fragments require validation and explicit saving. `signals.hooks`
  are not executed.
- Rule actions `layout` and `gap_override` are stored but do not yet change tiling.
  The settings window displays this limitation.
- `/float` and `/close` do not exist: Roadie has no such actions. `/layout float`
  sets the stage layout.
- Command mode and the settings window are drawn by the daemon: they require
  `roadied` to be running.
- Settings with no effect (for example `desktops.*`, `stage_manager.enabled`) are
  not shown.

Keyboard Target building blocks are independently configurable. The CLI foundation
and picker stay enabled by default. Visual overlays are implemented and remain
optional. Application mouse actions and scroll mode are disabled by default.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = false
overlay_labels_only = true
overlay_duration_seconds = 3
app_mouse_actions_enabled = false
scroll_mode_enabled = false
search_hotkey = "command+control+alt+f"
label_font_size = 13   # label size in points (8 to 48)
```

```toml
[experimental.app_targets]
enabled = false
scope = "frontmost_window"   # or "visible_windows"
max_targets = 150
timeout_ms = 120
hint_characters = "asdfghjkl"
include_roles = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow"]
```

```toml
[experimental.target_grid]
enabled = true
overlay_enabled = true
overlay_draw_grid = true
overlay_fill_color = "#4DABF7"
overlay_fill_opacity = 0.10
overlay_border_color = "#4DABF7"
overlay_border_opacity = 0.55
overlay_label_color = "#FFFFFF"
rows = 3
columns = 3
max_depth = 3
hint_characters = "azeqsdwxc"
label_font_size = 13   # label size in points (8 to 48)
```

Use cases:

- jump to a bookmarked window or stage without remembering its ID;
- search for a target with `targets pick` and fail cleanly on ambiguity;
- open the bar with your chosen shortcut, then type a few letters to activate a visible element;
- send the active window to a target selected by label;
- give an agent a JSON API that is more robust than screenshots;
- inspect why a target is stale, pinned, floating, or excluded from tiling.

Even when `experimental.app_targets.enabled = true`, `click`, `double-click`,
`right-click`, and `command-click` on application targets are refused until
`experimental.target_mode.app_mouse_actions_enabled = true`.

Control discovery depends on the information each application exposes.
Reading is time-limited and the feature is enabled separately.

## Power-User Commands

Roadie exposes layout primitives inspired by power-user window managers.

```bash
roadie focus back-and-forth
roadie layout split horizontal
roadie layout split vertical
roadie layout flatten
roadie warp right
roadie resize right
roadie layout zoom-parent
roadie layout toggle-split
roadie toggle floating
```

Use cases:

- return to the previous focus;
- force a local layout restructuring;
- insert the active window on a chosen side with `warp`;
- locally flip two neighboring windows in `spatialBsp` with `toggle-split`;
- temporarily enlarge a window without losing context;
- take a window out of tiling in its stage, then put it back.

In `spatialBsp`, `layout insert` and `layout join-with` are rejected; use `warp`. `layout width` is rejected; use `resize`. `layout flatten` balances the existing tree. In other modes, legacy commands remain available where supported.

## Rules

Rules automate window handling by app, title, role, stage, or regex. They can
also place a new real application window on a target stage, Roadie desktop, and
display without following focus by default.

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules list --json
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev
```

Use cases:

- send project terminals to a `shell` stage;
- always open Firefox on the `web` stage of the external display;
- create that affinity directly from the title bar right-click menu;
- tag documentation windows as `research` scratchpad candidates;
- catch invalid regexes before restarting the daemon.

## Window Groups

Window groups associate multiple windows with the same user intent.

```bash
roadie group create terminals 12345 67890
roadie group add terminals 11111
roadie group focus terminals 67890
roadie group remove terminals 12345
roadie group dissolve terminals
roadie group list
```

Use cases:

- group several terminals for the same project;
- group multiple browser documentation windows;
- expose grouped state to scripts via `roadie query groups`.

## Events And Query API

Roadie publishes JSONL events and exposes stable JSON queries.

```bash
roadie events subscribe --from-now --initial-state
roadie query state
roadie query windows
roadie query groups
roadie query events
```

Use cases:

- feed a status bar;
- watch focus changes;
- debug a rule or a group;
- build a local dashboard.

## Restore Safety And Administration

The daemon (`roadied run` or `roadied tiler`) writes a restore snapshot at startup, at each stage change, and every 30 seconds. On SIGTERM, SIGINT, or SIGHUP, it brings hidden windows back before it exits. A small watcher process (`restore-watch`) follows the daemon and does the same if the daemon disappears without a clean exit. None of this runs in the focus/border path. To disable it, start the daemon with `roadied run --yes --no-restore-safety`. To bring every hidden window back by hand, run `roadie restore unhide-all`.

```bash
roadie config reload --json
roadie restore snapshot --json
roadie restore status --json
roadie restore apply --yes --json
roadie cleanup --dry-run --json
roadie cleanup --apply
```

Use cases:

- reload config only when validation succeeds;
- take a manual frame snapshot before a risky operation;
- explicitly restore frames by window ID when requested, or after an unclean crash;
- keep logs, backups, and legacy archives under control.

## Width Presets And Performance Diagnostics

Width presets apply to `bsp` and `masterStack`. In `spatialBsp`, use `resize` instead of `layout width`. Performance diagnostics read the event log; they do not time the focus/border path in real time.

```bash
roadie layout width next
roadie layout width prev
roadie layout width nudge 0.05
roadie layout width ratio 0.67

roadie performance summary
roadie performance recent --limit 20
roadie performance thresholds --json
```

Use cases:

- quickly widen the active window without changing the whole layout mode;
- inspect recent interaction event types in `events.jsonl`;
- keep target thresholds documented without touching the daemon.

## Keyboard Targets, Display Grid, Window Grid, And Macros

Keyboard Targets expose actionable stages, windows, displays, desktops,
bookmarks, and Accessibility application zones.

The **Display Grid** adds a recursive spatial language over a full display when
Accessibility cannot see everything. The **Window Grid** uses the same recursive
language but scopes it to the focused window, which is useful for video players,
webviews, canvases, and dense application panes.

Record/replay captures short manipulations with target context and grid
fallback. A `record` indicator can appear in the navrail while capture is
running.

```bash
roadie targets interactive --source all --include-app-targets
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
roadie record start demo --duration 10
roadie record replay demo
```

Use cases:

- switch to a stage or window by label instead of ID;
- click an application button exposed by Accessibility;
- target a non-accessible zone through Display Grid;
- target a control inside the focused window through Window Grid;
- show a manipulation to an agent, then replay or analyze it.
