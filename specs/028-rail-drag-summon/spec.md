# SPEC-028 — Drag-summon : ramener une fenêtre cachée dans la stage active via drag depuis le navrail

**Statut** : Implémenté (V1 minimaliste)
**Date** : 2026-05-05
**Branche** : `026-wm-parity` (suite directe SPEC-026/027)

## Contexte

Aujourd'hui pour basculer une fenêtre d'une stage cachée vers la stage active (= la rendre visible et tilée), il faut soit :
- Switcher vers la stage source, drag-drop la wid sur la cellule de la stage cible (= active), re-switcher.
- `roadie stage assign <active_id>` qui assigne la fenêtre frontmost.

Aucune des deux n'est confortable quand on a un visuel direct dans le rail (vignette de la fenêtre cachée) et qu'on veut juste « la ramener ici, maintenant ». Sur Stage Manager natif macOS, on peut drag une fenêtre depuis le « rideau » de droite vers la zone principale ; on veut le même geste dans roadie.

## User story

En tant qu'utilisateur, je vois une vignette de fenêtre dans une cellule de stage non-active du navrail. Je veux drag cette vignette et la lâcher n'importe où sur le bureau (zone des fenêtres) du display courant pour que la fenêtre rejoigne instantanément la stage active de ce display.

**Critère d'acceptation** : avec stage 1 active sur LG externe (Firefox visible), et stage 2 cachée contenant Slack ; le user voit la vignette Slack dans la cellule stage 2 du rail. Drag de la vignette vers le centre de l'écran → relâchement → Slack apparaît tilée dans la stage 1 (à côté de Firefox), stage 2 ne contient plus Slack.

## Sémantique précise

- Source du drag : un `WindowVM` rendu par n'importe quel renderer du rail (parallax-45, stacked-previews, hero-preview, mosaic, icons-only).
- Payload du `NSItemProvider` : la `cgWindowID` de la fenêtre (sérialisée en string décimal).
- Cible du drop : tout point de l'écran qui n'est pas dans la frame du panel rail du display courant.
- Action : `roadie stage assign <active_stage_id_du_display> --wid <wid>` côté daemon.

## Design

V1 (cette spec) :

1. **Renderers du rail** : chaque vignette `WindowVM` reçoit `.onDrag { NSItemProvider(object: wid as NSString) }`.
2. **Overlay panel** : un nouveau `StageDropPanel` (`NSPanel` borderless transparent) est créé par display, couvrant **toute la frame du display sauf la frame du rail**. Il est en niveau `.floating - 1` pour rester sous le rail mais au-dessus du desktop. Il accepte les drops de type `kUTTypePlainText` et déclenche un callback `onSummon(wid)` qui appelle `assignWindow(wid:to: <active_stage_du_display>:displayUUID:)` via IPC.
3. **CLI** : `roadie stage assign --active-current` (alias) pour les power-users qui veulent scripter sans UI. Default : `roadie stage assign <stage_id>` reste la voie nominale.

V2 (out of scope SPEC-028) :
- Hint visuel pendant le drag (highlight de la zone valide, ghost de la fenêtre cible).
- Snap zones (drop sur la moitié gauche → split horizontal, etc.) — type Magnet/Rectangle.

## Critical files

- **NEW** `specs/028-rail-drag-summon/spec.md` (ce fichier)
- **MODIFIED** Renderers : `Parallax45Renderer.swift`, `StackedPreviewsRenderer.swift`, `HeroPreviewRenderer.swift`, `MosaicRenderer.swift`, `IconsOnlyRenderer.swift` — ajout `.onDrag` sur la vue par-vignette.
- **NEW** `Sources/RoadieRail/Views/StageDropPanel.swift` — overlay panel transparent.
- **MODIFIED** `Sources/RoadieRail/RailController.swift` — création/destruction du `StageDropPanel` par display, callback de drop.

## Verification

1. Build OK + install OK + daemon UP.
2. Drag visuel : prendre une vignette dans une cellule non-active du rail, la lâcher au milieu de l'écran → la fenêtre arrive dans la stage active.
3. Drop sur le rail lui-même = comportement existant inchangé (pas capté par l'overlay).
4. `roadie daemon audit` reste à 0 violations après plusieurs summons consécutifs.
