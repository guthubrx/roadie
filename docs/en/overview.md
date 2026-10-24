# Desktop and stage overview

The overview shows your Roadie organization: displays, desktops, stages and windows. It complements the Cmd+Tab switcher. It covers the full screen, including the menu bar and Dock, as a global overview. It does not create a macOS Space.

Open it with `roadie overview show`. BetterTouchTool can bind a three-finger upward swipe to `roadie overview toggle`; a second swipe closes it. `roadie overview hide` also closes it. `roadie overview status` reports configuration and daemon availability, not confirmed window visibility.

In **Réglages Roadie > Vue d’ensemble**, choose:

- **Archipel** (default): display columns with stacked desktops. Each display gets the width it needs. Slanted dividers separate displays.
- **Baies**: horizontal display bands with desktops side by side.
- **Loupe au survol** (enabled by default): cards of the desktop under the pointer grow after a short settling delay. Hovering only previews; it never activates a desktop.
- **Magnification**, from 100 to 250%, default 150%: card size of the hovered desktop relative to the others. Other desktops tighten when space runs out. Real windows keep their sizes.
- **Wallpaper blur**, from 0 to 100%, default 20%: a slider and a live preview of your wallpaper show the result.
- **Optional internal shortcut**: record a key combination directly. A blank shortcut reserves no keys. BetterTouchTool, Karabiner and other tools can call the CLI instead.

The overview shows no controls: change these settings in the settings window; they apply to the open view. The background is the display's wallpaper, blurred, which hides desktop icons. Without a readable image, Roadie blurs what lies under the view. Desktop order stays stable. A layout change alone does not move the magnifier while the pointer is still.

Each desktop is a grid of equally sized 16:10 cards in stage order. The desktop name is a chip; a green dot marks the active desktop, a blue chip the magnified one. Under each card, the window icon and title are followed by a chip with its stage name. Chips of the selected window's stage turn blue. Blue outlines the selected window. Arrow keys and Tab move the selection; Enter or a click opens the window in its original desktop and stage. Escape closes the overview immediately from any control. Clicking another display also closes it.

Occupied, named and active desktops are represented. Empty stages are not shown. Unused desktops are not added merely because their number is allowed in configuration. Dense layouts scroll to keep targets usable. A capture fills its card, cropped from the top; it is taken at the card's resolution and stays unchanged while the view is open. An application icon stands in when a capture is unavailable.

```toml
[overview]
enabled = true
presentation = "archipelago" # or "bays"
loupe = true
magnification = 150
background_blur = 20 # 0 = sharp, 100 = very blurred
hotkey = "" # optional; use the keyboard recorder
```

Images use the rail and switcher's shared cache. Pointer movement triggers no window acquisition, disk read or capture. Bounded capture batches run while the view is open. This describes the mechanism; no measured performance improvement is claimed.

Cards remain compact. Stages use rows and columns according to their contents. A single window does not stretch to fill the entire height. Magnification stays inside the stage composition, without an overlay. The whole window image is preserved. Clicking it opens that window.

If Mission Control also appears after the three-finger swipe, turn that gesture off in System Settings > Trackpad > More Gestures > Mission Control. Keep the Roadie gesture in BetterTouchTool.
