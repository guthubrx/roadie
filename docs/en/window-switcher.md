# Window switcher

The switcher finds a window in its Roadie desktop, stage and display. It opens
that context before focusing the window. It does not move the window into the
current stage.

## Use

Configure **Cmd+Tab in BetterTouchTool or Karabiner** to call the CLI commands
below. Hold Command and press Tab to move forward, or Shift+Tab to move backward.
Release Command to open the selected window. Escape cancels.
Roadie does not register a global opening shortcut by default.

A profile can also keep the switcher open after release. In this mode, search
by application, title, stage or desktop, then confirm with Return or a click.
Selection follows window identity during search. Enlarging a preview does not
focus the actual window.

You can keep AltTab installed to compare both tools. Assign different shortcuts
in their settings.

## Settings

In **Settings > Sélecteur**, choose thumbnails, icons or a compact list. Adjust
automatic sizing, thumbnail width, font size and font family. Changes take
effect without restarting Roadie.

You can define up to nine shortcut profiles. Each profile has:

- a name and key combination;
- a scope: all windows, current display, desktop, stage or application;
- an order: recent, title or stage;
- filters for minimized windows, hidden applications and fullscreen;
- an option to show one window per application;
- a choice between focusing on release and staying open.

Bundle identifier exclusions apply to every profile. Actions target the selected
window: close, minimize or restore, hide or normally quit the application,
maximize, and Roadie fullscreen. Applications may still ask to save documents
before quitting.

## Commands and gestures

```sh
roadie switcher show
roadie switcher show --profile all
roadie switcher next
roadie switcher previous
roadie switcher accept
roadie switcher cancel
```

BetterTouchTool can run these commands from a gesture. `show` uses the profile
identifier, not its displayed name. The CLI confirms that the command was queued;
this response does not prove that a window was later activated. The daemon and
its graphical component must be running.

## Previews and limits

The rail and switcher share their image cache within the same process. An icon
and title remain available when a capture is missing. Images can show the last
captured state; the switcher is not a continuous video feed.

Roadie desktops are distinct from native macOS Spaces. This integration is not
complete management of native Spaces or native tabs. The switcher is Roadie's
own implementation; it does not import AltTab code, assets or commercial license.

The switcher remains available in standard mode with `--no-target-mode`. In
modular mode, it shares the `target-mode` process with the keyboard interfaces.
If macOS cannot verify an offscreen window's state, the card reports an unknown
state. Profiles that exclude minimized, hidden or fullscreen windows also
exclude these unknown states.

Global opening shortcuts are now external by default. In BetterTouchTool or
Karabiner, bind Cmd+Tab to `roadie switcher cycle --hold cmd`, and Cmd+Shift+Tab
to `roadie switcher cycle --hold cmd --backwards`. Releasing Command confirms
the selection. `show` keeps the panel open until explicit confirmation. Use the
full path of the installed CLI in a shell action. An internal shortcut remains
optional in each profile; its default is empty.

Thumbnails form a grid beside the larger preview. On narrow screens they move
below it. The search field uses the panel width, independent of the grid width.


## Profiles and direct shortcut recording

Settings groups related controls across all categories. In **Settings > Sélecteur**,
profiles have a name, a shortcut owner and separate controls for windows and navigation.
Choose Roadie, BetterTouchTool, or an external tool/CLI. Click Record and press the
actual key combination; Escape cancels. The temporary recorder uses Roadie's existing
Accessibility access. BTT must be running to prepare and verify its forward/reverse
bindings. Failed changes preserve or restore the previous binding. Unrecognized
third-party bindings are not removed. Test the real combination after setup.

Release can focus the selected window, keep the panel open, or enter search.
Search and Actions can follow that mode or an explicit visibility choice. Cmd+F
enters search when allowed; Escape exits search entered mid-session before closing.

Four arrows follow the grid geometry. Hover selects a card and clicking activates
its window. A stationary pointer does not override a later keyboard selection.
Both navigation methods are configurable per profile. While editing nonempty search
text, Left/Right edit text and Up/Down move through results. IME and native editing
shortcuts remain available. External CLI and Karabiner workflows remain supported.

Profiles can inherit common appearance settings or override style, preview, sizing
and font. Clearing an override restores the common value.
