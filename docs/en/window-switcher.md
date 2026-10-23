# Window switcher

The switcher finds a window in its Roadie desktop, stage and display. It opens
that context before focusing the window. It does not move the window into the
current stage.

## Use

The default shortcut is **Ctrl + Alt + Tab**. Hold Ctrl and Alt, then press Tab
to move forward or Shift+Tab to move backward. Release to open the selected
window. Escape closes the switcher without changing windows.

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
