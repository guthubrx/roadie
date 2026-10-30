# Features

## Window switcher

Find Roadie-managed windows in their own desktop, stage and display. Search,
thumbnail grid beside a larger preview, icons or list, independent profiles and
targeted actions. Shortcut tools call the CLI; settings live in **Sélecteur**.
[Guide and commands](window-switcher.md).

## Overview

Shows every display, desktop, stage and window on a single page, in Archipelago or
Bays layout. Drag a desktop chip, a stage chip or a window card to rearrange your
workspaces, on one display or across displays: a live preview shows the result
before you release. Drop a window or a stage into empty space to create a stage or a
desktop. [Overview guide](overview.md).

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

A stage name is unique across Roadie, all displays and desktops: `stage rename`
refuses a name already used by another stage, and `roadie state heal` fixes
inherited duplicates. The overview also moves a stage or a window by drag and drop.

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

Roadie fullscreen (`roadie toggle fullscreen`) hides the rail on the affected
display, including on hover. It does not create a native macOS fullscreen Space.
Repeat to restore the layout and normal rail behavior. `roadie toggle maximize`
keeps the rail accessible.

Auto-hide (`fx.rail.auto_hide`) works independently: outside fullscreen, the rail
retracts like the Dock and returns when you hover over the left edge. Edge width
and hide delay can be adjusted in Réglages Roadie > Rail. A pinned rail
stays open; `roadie rail unpin` restores auto-hide when it is enabled.

The nav rail keeps your chosen stage order, even when stages gain or lose windows.
Scroll the rail when the cards exceed the display height. Drop a window onto a
card to join that stage. Drop in free space to create a stage at the top, between
cards, or at the bottom; the preview marks the chosen location. Destination menus
and previews follow the same order. Named empty stages keep a subtle outline,
their name and an empty-state label, even when temporary stage labels are hidden.
Anonymous empty stages remain available through the next-empty-stage action.

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
- right-click a stage without dragging to open its menu: rename the stage, send it to another display, send a window to another stage, or delete the stage once it has no window (the active stage and a stage of a missing display stay).

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

When `visibility_seconds` is greater than `0`, occupied stage names are hidden by default.
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

Choose the destination in **Réglages Roadie > Tuilage > Écran des nouvelles fenêtres**
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
roadie desktop move 2 1
```

`desktop move` moves a desktop to another place and renumbers desktops, as in
Mission Control; its stages, windows and name follow it. The overview does the same
by drag and drop, including to another display.

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
- **On-screen search only** (session 133): `screen_search_hotkey` (for example
  `command+control+alt+f`, Capslock + F; empty by default) or `roadie targets screen` opens the bar without
  the launcher list. Only the input and the labels of visible elements show: ↑/↓ change the target,
  Shift + label clicks, Return clicks. The launcher keeps its own shortcut (`search_hotkey`);
  `launcher_on_screen = false` (Settings > Search) then removes its "On screen" section and the reading of
  visible windows.
- **Recent zones** (sessions 135 and 136): every zone clicked by on-screen search, and every ordinary click in
  a window, becomes a zone with its photo (`~/.roadies/zone-history.json`, `~/.roadies/zone-thumbs/`). A switcher
  profile with `source = "zones"` (for example `hotkey = "alt+tab"`) shows them exactly as ⌘Tab shows windows:
  presentations, styles, arrows, mouse, Escape, search, grouping by desktop and stage. Confirming brings the
  zone's window back (stage and desktop included) and clicks the zone, through its element if it still exists,
  otherwise through its place if the window kept its size. `[switcher] zone_history_size` (20),
  `zone_history_hours` (24) and `zone_clicks_per_window` (3 click zones per window; 0: clicks create no zone),
  Settings > Switcher.
- **Typos** (session 134): with no exact match at all, on-screen search allows a missing, extra or wrong
  letter, or two swapped letters: one typo from 4 letters, two from 8 ("enregsitrer" finds "Enregistrer").
  The bar shows "≈ approximate". In the launcher, a "Did you mean" section comes last, only under three exact
  matches (apps, windows, on-screen elements; Spotlight does not forgive typos in files). An exact match
  always comes first. Setting `typo_max_errors` (0 to 2, default 2; 0 turns it off), Settings > Search.

**Launcher**: above the bar, a list groups results into sections: **Applications**
(every installed app), **Windows**, **Stages and desktops**, then **On screen** (the
labeled targets). Matching accepts initials (`vsc` for Visual Studio Code). Roadie
remembers your choices: the row picked after the same input comes first next time
(local ranking, `~/.roadies/launcher-ranking.json`, safe to delete). Return on an
app that is already open goes to its window, in its stage and desktop; on a closed
app, opens it in the active stage of the active display, unless an `assign_stage`
rule applies. Arrow keys move through the list; clicking a row activates it.
The ranking also remembers the stage active when you choose: in "Com", `o` first offers
what you usually pick there, in "Dev" something else. A named stage is known by its name,
even after moving; at most six stages per item. **Documents and tabs**: the bar also finds what is open, even in a hidden stage or on another
desktop: each window's document (TextEdit, Preview, Pages…) and the tabs of Chrome, Brave, Edge
and Safari (title and address). Return shows the stage, brings the window forward and selects
the tab. macOS asks once for automation permission per browser. Firefox does not expose its
tabs: not covered. Nothing is written or logged. Diagnostic: `roadie launch --open-items
[--tabs]` (item count per app).

**Files**: from 3 letters, Spotlight searches the home folder (outside `~/Library`,
hidden items and `node_modules`) for folders, documents, text, images, PDFs, spreadsheets
and presentations; a "Files" section shows icon and folder. A leading space or apostrophe
searches files only (from 2 letters). Return goes to the window already showing the file
(apps that expose their document: TextEdit, Preview, Pages…), otherwise opens it in the
stage where you usually open files from that folder, or in the active stage. Verbs: open
in…, bring here, reveal in Finder, preview, copy path. ⌘C with no text selected copies the
selected row (path, title); ⌘Y shows the Quick Look preview.
Windows show their real thumbnail
(already captured by the rail, switcher or overview) with their app icon as a badge;
without a thumbnail, the icon alone.

**Web**: a typed address (`github.com/x`, `www.lemonde.fr`, `localhost:3000`, `https://…`) shows
« Ouvrir … » on top; Return opens it in the default browser, Tab offers Open in… (a new browser
window joins the chosen stage; Firefox: an empty tab may remain), Bring here, Copy. A file name
(`fichier.txt`, `readme.md`) is not an address, unless followed by `/`, a port or with `www.`.
`yt chat` searches « chat » on YouTube; defaults: `g` Google, `yt` YouTube, `wp` Wikipedia, `ddg`
DuckDuckGo, `maps` Maps; a `[[experimental.target_mode.web_searches]]` table (`keyword`, `title`,
`url` with `{query}`) replaces them. Every input ends with a « Web » section (the
`web_search_url` search, then the `fallback_searches` keywords), selected only when nothing else
matches. **History**: the last 20 inputs that led to an action are kept
(`~/.roadies/launcher-history.json`, on this Mac only). Reopened within 5 minutes, the bar brings
back the last one, selected: typing replaces it. The empty bar offers the 3 recent searches.
`roadie launcher history [--clear]` shows or clears them.

**Calculation**: a typed calculation (`12*4.5`, `2^10`, `-(3+4)*2`) shows its result on top,
under « Calcul »; Return copies it and closes the bar, ⌘C copies it. Operators `+ - * / ^ %`,
`×`, `÷`, parentheses, `,` or `.` decimal; after `=`: `pi`, `e`, `sqrt`, `abs`, `round`,
`floor`, `ceil`, `exp`, `ln`, `log`, `log2`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`
(`=sqrt(2)`). 12 significant digits, system decimal separator. A lone number or an unfinished
calculation (`12*`, `1/0`) gives no row. With `calc_opens_calculator = true` (Settings > Search,
« Calcul : ouvrir aussi Calculette »), Return copies the result and also opens Calculator, or goes to its
open window; ⌘V pastes the result there. ⌘C still copies without opening.

**Path**: an input starting with `~`, or with `/` followed by a root folder (`/Us`,
`/Applications/`), lists that folder filtered by the rest of the input; nothing else is
searched. Tab completes the selected name (`~/Doc` → `~/Documents/`), → opens its verbs, Return
opens it like a file (a folder in Finder). Hidden items show only when the rest starts with `.`.
Command mode keeps priority: `/s`, `/set`, `/d`… stay commands; from the second `/` (`/sbin/`)
it is a path.

**Workflows**: the bar runs Alfred-format workflows, those installed in Alfred (read without
changing them, synced folder followed) and those in `~/.config/roadies/workflows`. Typing their
keyword (`emoji heart`) shows only their rows, under their name; from 2 letters, matching
keywords appear in a « Workflows » section (Tab or Return completes). A filter script runs in the
background (100 ms after the last keystroke, stopped by the next one, 10 s at most); actions (Run
Script, Run NSAppleScript, automation tasks, shortcuts) run to completion, as in Alfred. Return
follows the workflow graph: scripts, conditions, splits, replacements, URL, file, Finder, copy
(auto-paste included), notification, sound, speech, written file. Holding ⌘, ⌥ or ⌃ shows what the
row will do; Tab completes, ⌘C copies, ⌘Y previews. A workflow runs with Roadie's rights, as it
does in Alfred: install only those you know. Settings: `workflows_enabled`, `alfred_workflows`
(Settings > Search). `roadie workflow list` reports each one (complete, partial, unusable) and
what is missing; `roadie workflow check FOLDER` does the same; `roadie workflow install
X.alfredworkflow` and `roadie workflow remove ID` manage Roadie's folder. List and file filters
(Spotlight, → opens the file's verbs), fallback searches and universal text actions (« Repli »
section at the bottom) work too; file actions become « Workflow : … » verbs (Tab on a file).
`roadie workflow run ID OBJECT [ARGUMENT]` runs any object, `roadie workflow trigger ID TRIGGER
[ARGUMENT] [--var name=value]` an external trigger; `roadie workflow list --hotkeys` lists hotkeys
with the command to bind in BetterTouchTool (Roadie does not capture these keys; the « selection »
argument is read through accessibility, else by ⌘C). Alfred's official automation tasks (public
repository `alfredapp/automation-tasks`, BSD-3 license) install with `roadie workflow tasks update`
into `~/.roadies/alfred-tasks`. Other bricks: simulated keys, large type, Terminal, Apple Shortcuts,
dialog, file type, bar reopened on a path. **Presentations**: the results of a workflow (for example `emoji`), of an explored folder (`~/Pictures/`) or
the files of a search show as a list, a grid or large tiles. ⌘G (configurable: Settings > Search > « Touche des
présentations ») or a click on the chip at the right of the input (☰ ▦ ▣) moves to the next presentation;
Roadie remembers it per workflow, per folder and for files. In a grid, images show their content and ← → ↑ ↓
move between tiles. **Grid**: a Grid brick opens the bar as tiles (large
image, title, subtitle on the tile or in the footer), with the workflow's column count; ← → ↑ ↓
move between tiles, typing filters, Tab keeps the verbs, Return sends the tile to the rest of the
workflow. An external trigger can target any brick that declares it (Alfred 5.5). **Orders to
Alfred**: when a workflow script addresses Alfred (`tell application id "com.runningwithcrayons.Alfred"
to …`, `Application("com.runningwithcrayons.Alfred")`), Roadie does what is asked itself, without
opening Alfred: `search` opens the bar, `run trigger` runs the trigger, `set configuration` /
`remove configuration` keep the setting in `~/.roadies/workflows-settings/` (never in Alfred's folder),
`reveal workflow` shows the folder, `version` returns the version. `roadie workflow list` lists these
« ordres à Alfred » and the « non traduits » ones. Text, Image and PDF views and Alfred
Remote buttons: see below. Never: snippets, Alfred's buffer, compiled AppleScript. A script run by a workflow gets Roadie's Accessibility permission
(measured). The log keeps neither input nor result.

**Verbs and destinations**: Tab on the selected row opens its verbs. App: open or go
to its window, open in…, new window here, gather its windows in…, bring here, hide,
quit. Window: go to, send to…, bring here, float this window or always the whole app
(and back: tile this window again, always tile, remove the rule), fullscreen,
minimize, close. Stage: show, move to a
desktop or display. Desktop: show, move to a display. On-screen target: click,
double-click, right-click, Cmd-click. A verb ending with "…" asks for a destination:
a stage, desktop, display, or "New stage" (named after the input if that name is
free). As soon as you type a name at the verb step, matching destinations appear:
`fire`, Tab, `perso`, Return opens a Firefox window in the Perso stage and goes
there. Escape, or deleting in an empty field, goes back one step.

**Multiple selection**: ⌥↑ adds or removes the selected row, ⌥↓ adds it and moves down, ⌥← removes
the last one added, ⌥→ opens the selection's verbs, ⌥⌫ clears it (apps, windows and files; « ✓ »
before the rows, « N choisis » in the chip). The selection stays when the input changes: `fire`
⌥↓, `term` ⌥↓, `code` ⌥↓. Return with a selection opens its verbs, with the number of objects
concerned: Send to… (windows sent; apps and files opened in the stage), Bring here, Close,
Minimize, Quit, Hide, Copy paths, Reveal in Finder. A new stage is created once and receives
everything; Roadie goes there at the end. « Annuler » in the empty bar puts the whole batch back.
Escape first clears the selection. In this field, ⌥ + arrows no longer move by word (⌃A, ⌃E remain).

**Empty bar**: before you type, the bar offers what is useful now: a proposed rule, Back
(previous window), Undo (put the window of the last move back, within 10 minutes; also
`roadie undo`), Recently closed (reopen in its stage a window closed less than 12 h ago),
Often here (apps chosen most often in this stage), Recent searches. Settings > Search turns
Often here and Recent searches on or off and sets their number of rows (3 by default):
`idle_frequent_enabled`, `idle_frequent_count`, `idle_recent_searches_enabled`,
`idle_recent_searches_count`. **Proposed rules**: three or more moves of
an app to the same stage in a week propose "Create the rule" (open affinity), "Later" or
"Never". While searching, the counter capsule shows "💡 1"; ⌘R shows the proposal. Recorded
moves: `~/.roadies/launcher-moves.json` (200 at most).

**Projects**: a named stage can be kept as a project (the stage verb "Save as project", or
`roadie project save NAME`): its windows in order, each one's document or address when the app
exposes it (TextEdit, Preview, Pages, Chrome…), and the shape of its layout. Reopening the
project (the bar's "Projects" section, or `roadie project open NAME`) shows the stage if it
still lives; otherwise recreates it on the shown desktop, reopens each window in turn and puts
the layout back, even after a restart. An app that does not expose its document (Firefox,
iTerm2) comes back as a new empty window. Projects: `~/.roadies/projects.json`.

**Phrase**: several words whose last ones name a destination and a position, in French or
English: `fire perso gauche` or `fire perso left` opens Firefox in the Perso stage, on the
left. Recognized words: a stage name (exact, or a unique 3-letter start), `ici`/`here`,
`nouvelle`/`new`, `bureau N`/`desktop N`, `écran N`/`screen N`, and `gauche`/`left`,
`droite`/`right`, `plein`/`full`, `flotte`/`float`. The "Phrase" row states the action
before Return.

**Keep an action**: ⌘S on an app, a file, a phrase or a composed verb opens the "Keep" step:
type an abbreviation (12 characters at most), Return saves it; ⌘C copies the equivalent
`roadie launch` command, to paste into BetterTouchTool. Typing the abbreviation later puts the
action first. Windows and stages are not kept (they disappear); a target stage must be named.
Abbreviations: `~/.roadies/launcher-aliases.json`.

**Live preview**: when the selected row rests on a destination stage (Open in…, Send to…,
Bring here), the real windows of that stage take their future place; the window being sent
goes there too, and a window about to open is marked by a translucent ghost with its app
icon. A hidden stage of the shown desktop is shown during the choice. Escape, another row or
closing put everything back; Return keeps the layout. No preview to another desktop or a new
stage.

**Return variants**: holding ⌘, ⌥ or ⌃ changes what Return does, and the selected row's
detail says so. ⌘ Return opens the app in a new stage of the shown desktop, or sends
the window there, then Roadie goes there. ⌥ Return brings the window (or the app's
window) into the active stage without changing the shown stage. ⌃ Return searches the
web for the typed text (`web_search_url`, Google by default). The first nine shown rows
carry ⌘1 to ⌘9: the key runs their action, at every step. The modifier is set in
`pick_modifier` (`command` by default, `shift`, `alt` or `control`); with `shift`, the
top-row digits are typed on AZERTY only in an empty input or a calculation. → with the cursor at the end
of the input opens the verbs, like Tab.

**Verbs of the active window**: Capslock + Shift + F (`actions_hotkey`, Hyper + Shift + F)
or `roadie targets actions` opens the bar on the verbs of the frontmost window.
"Always float <App>" and "Always tile <App>" are also in the title bar Window menu; the
choice is written to `roadies.generated.toml`, on the same rule as "Always open this app
here", and applies to every window of the app, present and future.

**Auxiliary windows**: a reminder, a dialog or a palette often looks like an ordinary window to macOS
(Thunderbird's reminder has the same buttons as its inbox); only its title tells it apart. The "Fenêtres
toujours flottantes" list (Settings > Règles, `[[exclusions.floating_windows]]`) keeps an app's windows out
of tiling by title: `app` (name or bundle ID) and `title`, where `#` stands for a number and `*` for any
text, case-insensitive ("# Reminder" covers "1 Reminder" and "3 Reminders"). Add, edit or remove your own
rows. The title bar Window menu offers "Toujours faire flotter les fenêtres « # Reminder »" for the chosen
window, or "Ne plus faire flotter…" when it is already listed. A row wins over the app rule (priority
9,100). Size criteria (short panel, small settings window) judge the window as it was born, not after
tiling. `roadie window explain [ID]` shows what Accessibility reports about a window (subrole, buttons,
first frame) and why it is tiled or floating.

**Floating window placement**: an untiled window that opens over the rail (Finder's Get Info opens at the
top left) is moved just to its right, without resizing; Settings > Règles > "Fenêtres flottantes hors du
rail" (`[exclusions] floating_avoid_rail`, on by default). To have a window come back where you left it,
position and size, tick "Remember its place" on its row in the list above or on its rule
(`remember_frame = true`). The place is kept per row or rule, not per title: every Finder Get Info window
shares one. Only a window's opening is handled: afterwards Roadie only records your moves, and windows
already open when Roadie starts are left alone. An app may impose its size (Finder fixes the width of its
Get Info windows).

| Key | Effect |
|-----|--------|
| letters, digits, space | filter |
| Tab | verbs of the selected row; on a verb ending with "…", its destinations |
| Down, Ctrl-N | next result |
| Shift-Tab, Up, Ctrl-P | previous result |
| Shift + chip letter | open that row (`⇧K` on the right of a window, stage or desktop) |
| Return | click; on an app: go to its window or open it |
| ⌘ Return | app, window: new stage; on-screen target: Cmd-click |
| ⌥ Return | app, window: bring into the active stage |
| ⌃ Return | search the web for the typed text |
| ⌘1 to ⌘9 | action of the row carrying that digit |
| → at the end of the input | verbs of the selected row |
| Return twice (under 0.35 s) | double-click |
| Shift-Return | right-click |
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

#### Themes, bar placement, terminal, bookmarks and system commands (sessions 100 to 105)

- **Dead keys**: `~` (⌥N on a French keyboard), `^` then `e` and other compositions are no longer erased
  by the bar while typing.
- **Themes** (`theme`, `theme_dark`): Roadie, or one of Alfred's themes (Alfred, Alfred Dark, Alfred Modern,
  Alfred Modern Dark, Alfred macOS, Alfred macOS Dark, Frosty Teal, High Contrast Light, Large Avenir), with
  colours, fonts, sizes, corner radius, width and blur. A theme exported from Alfred (`.alfredappearance`) in
  `~/.config/roadies/themes`, or a custom theme made in Alfred, joins the list. `theme_dark` applies in macOS
  dark mode. `visible_results` limits the number of visible rows (0: as many as fit).
- **Bar placement**: drag the bar by its edge or the list background; it keeps that place
  (`bar_save_position`). Double-click the edge to return to the default place (`bar_position`: bottom,
  centre, or top like Alfred, the list opening on the free side). `bar_screen`: mouse, active window or main screen.
- **Terminal**: `> command` then Return runs the command in a new window of the chosen terminal
  (`terminal_app`: Terminal, iTerm, Ghostty, Warp, kitty, WezTerm, Alacritty).
- **Bookmarks** (`bookmarks_enabled`, `bookmark_browsers`): Firefox bookmarks (all profiles, folders, tags,
  site icons), Safari (Full Disk Access required) and Chrome, Brave or Edge, from two letters. Firefox
  keywords work: `w cat` with a `w` keyword bookmark containing `%s`. Open Firefox tabs are found too;
  Return selects the tab.
- **System**: lock, sleep displays, quit all, empty trash, volume, restart, shut down… (second Return for
  heavy commands); "Force quit" verb for an application.
- **Typed folders**: ⌫ at the end of `…/` goes up one folder; `path_sort` sorts by name or date.
- **Shortcuts**: Settings > Raccourcis gathers every key, recorded by pressing it: global shortcuts, bar keys
  (`large_type_key`, `copy_key`… in `[experimental.target_mode]`), grid, switcher, and BetterTouchTool's
  `roadie …` commands, each handled by BTT, by Roadie (`[[shortcuts]]`: `keys`, `command`, `btt_uuid`) or by
  nobody. A bar key taken by BTT is flagged; `btt_pause_keys` pauses that BTT shortcut while the bar is open.
- **Verbs**: after Tab, the verbs you choose most for a kind of object (application, file, window, stage…)
  come first; `learn_verb_order = false` keeps the fixed order.
- **Tile shape**: a workflow grid follows its Alfred image setting (`imageaspect`: square, portrait or
  landscape); tile width does not change.
- **Content and tags**: `in invoice march` finds files whose text contains these words (word start),
  `tags red` those carrying a Finder tag (colours in French or English). Keywords are configurable
  (`content_search_keyword`, `tag_search_keyword`, empty: off). OneDrive, Dropbox, Google Drive and iCloud
  Drive (`~/Library/CloudStorage`, `~/Library/Mobile Documents`) are searched too.
- **Web history** (`web_history_days`, 90 by default, 0: off): pages already seen in the bookmark browsers
  (Firefox, all profiles; Safari with Full Disk Access; Chrome, Brave, Edge), under « Historique » from two
  letters, excluding pages already bookmarked; most visited first.
- **Settings** (`settings_in_search`): Roadie settings pages and settings (`rail`, `theme`) and System Settings
  panes in your language (`keyboard`, `wi-fi`) under « Réglages »; Return opens the page, the setting (Settings
  search already filled) or the pane. ⌘, (`settings_key`) opens Roadie Settings.
- **Recent documents**: on an application, Tab then « Documents récents… » lists its last 20 documents that still
  exist (macOS File > Open Recent; for Word, Excel and PowerPoint, Office's own list). Typing filters, Return opens
  the document with that application. The first read of an Office list may make macOS ask for access to that
  application's data.
- **Workflow Text View**: Alfred 5.5's Text object opens a window (text to read, edit, or rendered Markdown with its
  images), filled by the argument, a file, or a script rerun from an input field (JSON responses `append`,
  `replacelast`, `rerun`… as in Alfred). Return sends the text on through the workflow, with held keys; Escape
  closes.
- **Workflow Image and PDF views**: the received file opens in a preview window (image reduced, fitted, or at its
  real pixels; PDF in one or two pages, continuous or not, per the object). Return sends its path on through the
  workflow; Escape closes.
- **Small Alfred features**: `open name` shows files only, `find name` too and Return reveals them in Finder
  (`open_keyword`, `find_keyword`); `file_types` adds file types (archives, AppleScripts…), `file_excluded_folders`
  leaves folders out; `calc_decimal` (macOS, point, comma) and `calc_grouping` shape a calculation result;
  `show_scrollbar` shows a scroll bar; 17 built-in web searches (`gi`, `tr`, `amazon`, `gh`, `wa`…); « Recharger
  les applications » and « Reconstruire l'index Spotlight » commands.
- **Workflows: Remote buttons and cache**: an Alfred Remote button becomes a trigger called by
  `roadie workflow trigger ID TRIGGERID` (with its fixed text), listed by `roadie workflow list --hotkeys` for
  BetterTouchTool; a Script Filter asking for a cache (`cache.seconds`) is not rerun for the same input during that
  time.
- **Misc**: ⌘L (configurable) shows the selected row in large type; ⌘⎋ closes the bar; `app_search_paths` adds application
  folders; `learning_enabled` turns learning off and `roadie launcher reset` clears it; the calculator also
  knows sinh, cosh, tanh, trunc, dtor, rtod…

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

The `default`/`défaut` and `window`/`fenêtre` keywords work in both languages; category names are the
identifiers shown by `/settings`. The settings window follows the macOS language.

#### Settings window (`/settings`)

`/settings` opens the "Réglages Roadie" window. `/settings category` opens it on
that category (identifier without accent, or label, case ignored). With no
argument, it opens on the last category viewed (Général the first time). A second
request brings the same window to the front.

- **Left column**: a search field, then the categories: Général (General),
  Tuilage (Tiling), Stages et bureaux (Stages and desktops), Mode lettres (Letter
  mode), Grille (Grid), Recherche (Search), Rail, Bordures (Borders), Focus et
  souris (Focus and mouse), Sélecteur (Window switcher), Règles (Rules), Avancé (Advanced).
- **Right area**: settings grouped by purpose, with aligned labels and controls.
  Narrow windows place the control below its label. The information button opens
  scrollable help; the reset arrow restores the default. Expand individual rules
  and their criteria or actions as needed. Menus follow the chosen text size.
  Switcher tabs span the available width and show the active tab clearly.
  Larger fonts use two rows instead of breaking tab names.
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
