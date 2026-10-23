# Window switcher

The switcher finds a window in its Roadie desktop, stage and display. It opens
that context before focusing the window, without moving it into the current stage.

## Use

Shortcuts can be handled by **BetterTouchTool or Karabiner**, like other Roadie
commands. Roadie reserves no global opening shortcut by default. For example,
configure **Cmd+Tab** in BetterTouchTool:

- Cmd+Tab runs `roadie switcher cycle --hold cmd`;
- Cmd+Shift+Tab runs `roadie switcher cycle --hold cmd --backwards`;
- releasing Command activates the selected window; Escape cancels.

Use the full installed CLI path in a shell action, for example
`/Users/moi/.local/bin/roadie`. Adapt it for another installation.
An internal shortcut is also available through the optional profile field.

A profile can keep the switcher open after release. Search by application, title,
stage or desktop, then confirm with Return or a click. Selection follows window
identity during search. The larger preview does not focus the actual window.
AltTab can remain installed for comparison; assign different shortcuts.

## Profiles and shortcuts

In **Réglages Roadie > Sélecteur > Profils de raccourcis**, select or create a profile.
Its name describes its purpose; its identifier stays internal. Choose **Roadie**,
**BetterTouchTool**, or **Outil externe / commande** (external tool/CLI).

The full-width tabs **Raccourci**, **Fenêtres**, **Navigation** and **Apparence**
separate shortcut setup, window filters, navigation and appearance. Larger fonts
use two rows to keep their names readable.

With Roadie or BTT, click Record and press the actual key combination. Keys appear
as symbols; Escape cancels and Clear removes the combination. Recording is active
only during capture and uses Roadie's existing Accessibility access.

BTT must be running to create or change its binding. Roadie prepares a forward
and reverse pair, verifies the entries, then activates them. A failed change
preserves or restores the previous configuration. Unrecognized shortcuts are not
removed. Test the physical combination after setup: reading an entry does not
prove it intercepts the keys. External mode keeps existing CLI/BTT and Karabiner
commands.

Release has three modes:

- **Activer la fenêtre choisie**: activate the selected window;
- **Rester ouvert**: keep browsing and using actions, then confirm;
- **Passer en recherche**: move to the search field after release.

Search and Actions follow the mode or an explicit visibility choice. Cmd+F opens
search when allowed. Escape first exits search entered during a session, then
closes the switcher. A session opened directly in search closes with Escape.

## Keyboard and mouse navigation

All four arrows follow the grid geometry, including while the opening shortcut's
modifiers remain held, such as Command after Cmd+Tab. On an incomplete final row,
Up/Down chooses the closest card in the intended column.

Hover selects a card; clicking activates its window. A stationary pointer does
not override a later keyboard selection. Both methods are configurable per
profile. While editing nonempty search text, Left/Right edit the text and Up/Down
move through results. IME composition and native editing shortcuts remain available.

## Appearance and filters

### Group windows by desktop and stage

In **Réglages Roadie > Sélecteur > Apparence commune > Organisation**, choose:

- **Grille classique** (classic grid): the existing flat window grid;
- **Colonnes par stage** (stage columns): stages side by side, with tabs to select a desktop;
- **Bureaux en onglets** (desktop tabs): one desktop per tab, with a section for each stage;
- **Navigation hiérarchique** (hierarchy): desktops and stages on the left, selected stage windows in the middle;
- **Grille par sections** (grouped sections): all desktops and stages in one scrolling view;
- **Vue d'ensemble des bureaux** (desktop overview): spatial stage maps grouped by desktop. Relative window positions are retained when readable; otherwise a grid is used.

Every presentation supports the larger preview. Columns and overview place it
below the windows; the others use a side preview or stack on smaller screens.
Thumbnail, icon and list card styles remain independent.

Under **Profils de raccourcis > Apparence > Organisation**, override the presentation
for one profile or select **Réglage commun** to inherit it. Changes apply immediately,
including while the switcher is open. Existing configurations keep the classic
grid and are not rewritten on read.

Search examines every window allowed by the profile. Tab and forward/reverse
shortcuts keep the global traversal: the visible desktop or stage follows selection.
Arrows follow the visible card geometry; at a left or right boundary, tabbed and
hierarchical views also move to the adjacent group. Identical names never merge
stages from different desktops or displays. These are Roadie desktops, not native
macOS Spaces.

Group order follows first appearance in the profile's results. The presentation
does not change window ownership or the saved stage order.

### Card appearance

In **Réglages Roadie > Sélecteur**, choose thumbnails, icons or a compact list. The grid
sits beside the larger preview, or below it on narrow screens. The search field
uses the panel width. Adjust automatic sizing, thumbnail width, font size and
family without restarting Roadie.

Up to nine profiles can define:

- a name and optional internal shortcut;
- a scope: all windows, current display, desktop, stage or application;
- an order: recent, title or stage;
- filters for minimized windows, hidden applications and fullscreen;
- one window per application;
- behavior on release, search visibility and Actions visibility.

Profiles can inherit the common appearance or override organization, style, preview, thumbnail
size and font. Clearing an override restores the common value. Application bundle
identifier exclusions apply to every profile.

Actions target the selected window: close, minimize or restore, hide or normally
quit the application, maximize, and Roadie fullscreen. Applications can still ask
to save documents before quitting.

## Commands and gestures

```sh
roadie switcher show
roadie switcher cycle --hold cmd
roadie switcher cycle --hold cmd --backwards
roadie switcher show --profile all
roadie switcher next
roadie switcher previous
roadie switcher accept
roadie switcher cancel
```

BetterTouchTool can run these commands from a gesture. `show` uses the profile
identifier, not its displayed name. The CLI confirms queuing; that response does
not prove a window was later activated. `cycle` tracks the modifiers given by
`--hold`, such as `cmd` or `ctrl+alt`. `show` keeps the panel open until explicit
confirmation.

The daemon and graphical component must be running. In standard mode the switcher
remains available with `--no-target-mode`. In modular mode it shares the
`target-mode` process with other keyboard interfaces.

## Previews and limits

The rail and switcher share an image cache within the same process. An icon and
title remain available when a capture is missing. Images can show the last
captured state; the switcher is not a continuous video feed.

If macOS cannot verify an offscreen window's state, its card reports an unknown
state. Profiles that exclude minimized, hidden or fullscreen windows also exclude
these unknown states.

Roadie desktops are distinct from native macOS Spaces. This integration does not
provide complete management of native Spaces or native tabs. The switcher is
Roadie's own implementation; it does not import AltTab code, assets or license.
