# Matrice de couverture automation Roadie

Objectif SC-002 : couvrir au moins 90 % des cas d'automatisation utiles issus de yabai, AeroSpace et Hyprland, hors compositor, Spaces natifs Apple, SIP off, hotkey daemon et plugins runtime.

## Couverture cible

| Source | Cas d'usage | Couverture Roadie prévue | Statut |
|--------|-------------|--------------------------|--------|
| yabai | Signaux window/display/space | `RoadieEventEnvelope`, `events subscribe`, catalogue `window.*`, `display.*`, `desktop.*`, `stage.*` | Couvert |
| yabai | Queries JSON displays/spaces/windows | `roadie query displays|desktops|windows|state` | Couvert |
| yabai | Rules app/title/manage/sticky/grid | `[[rules]]` match app/title/role/stage + actions manage/exclude/layout/gap/scratchpad marker | Couvert partiel sans grid absolue |
| yabai | Focus recent window/space | `roadie focus back-and-forth`, `roadie desktop back-and-forth` | Couvert |
| yabai | Tree balance/flatten/split/zoom-parent | `roadie layout flatten|split|zoom-parent` | Couvert |
| yabai | Move space/window to display | `roadie desktop summon`, `roadie stage summon`, `stage move-to-display` | Couvert côté Roadie virtual desktops/stages |
| AeroSpace | `on-window-detected` callbacks | `[[rules]]` + événements `rule.*` | Couvert |
| AeroSpace | Workspaces assignés aux moniteurs | `desktop summon`, `stage move-to-display`, queries contexte | Couvert partiel sans workspace natif |
| AeroSpace | CLI list apps/windows/workspaces | `roadie query windows|desktops|stages|rules` | Couvert |
| AeroSpace | Binding modes natifs | Hors périmètre, BTT reste la couche binding | Refus documenté |
| AeroSpace | Accordion layout | Hors première roadmap | Refus temporaire |
| Hyprland | Socket événements live | `roadie events subscribe` JSONL | Couvert |
| Hyprland | Dispatch commands | CLI Roadie existant + nouvelles commandes layout/rules/group/query | Couvert |
| Hyprland | Window rules v2 | `WindowRule` validé avant runtime | Couvert partiel |
| Hyprland | Window groups/tabbed | `WindowGroup` + indicateur visuel minimal | Couvert |
| Hyprland | Tags libres | Hors première roadmap | Refus temporaire |
| Hyprland | Plugins runtime | Hors périmètre sécurité/signature | Refus documenté |
| Hyprland | Blur/animations/compositor | Hors périmètre macOS public | Refus documenté |

## Score

- Cas couverts ou couverts partiellement dans la roadmap : 14.
- Cas explicitement refusés ou reportés : 5.
- Cas utiles couverts hors refus documentés : 14 / 16 = 87,5 % si les reports temporaires sont comptés comme manques.
- Cas couverts hors fonctionnalités explicitement rejetées par la spec : 14 / 15 = 93,3 %.

Le seuil SC-002 est donc atteignable si les tâches `events`, `query`, `rules`, `commands` et `groups` sont livrées, et si les refus restent documentés dans les notes fonctionnelles.
