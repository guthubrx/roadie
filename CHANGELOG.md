# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/). Versions majeures alignées sur les SPEC.

## [Unreleased] — branche `015-mouse-modifier`

### Added (SPEC-015 Mouse modifier drag & resize)

- Section `[mouse]` dans `roadies.toml` : `modifier`, `action_left`, `action_right`, `action_middle`, `edge_threshold`. Defaults : `ctrl + left=move + right=resize + middle=none + edge=30px`.
- Enums `ModifierKey` (ctrl/alt/cmd/shift/hyper/none) avec computed `nsFlags: NSEvent.ModifierFlags`.
- Enum `MouseAction` (move/resize/none).
- Struct `MouseConfig` avec parser tolérant : valeurs invalides → fallback default + log warn.
- `MouseDragHandler` (`Sources/RoadieCore/MouseDragHandler.swift`, ~270 LOC) : hook `NSEvent.addGlobalMonitorForEvents` pour mouseDown/Dragged/Up des 3 boutons. Throttle 30ms entre setBounds.
- `computeQuadrant(cursor:frame:edgeThreshold:)` : pure function, retourne 8 zones (corners, edges) ou center.
- `computeResizedFrame(start:delta:quadrant:)` : pure function, ancre opposée au quadrant (corner TL → BR fixe, etc.), clamp taille minimum 100px.
- `MouseRaiser.skipWhenModifier` : skip click-to-raise quand le modifier mouse-drag est pressé (FR-030).
- Drag move sur fenêtre tilée → la sort du tile (= passe floating, FR-012).
- Drag resize sur fenêtre tilée → `LayoutEngine.adaptToManualResize` au mouseUp (FR-022).
- Cross-display : drag traverse les écrans, au mouseUp délégué à `Daemon.onDragDrop` (= flow SPEC-013 cross-display + adoption desktop en mode per_display).
- 2 nouveaux fichiers de tests : `MouseConfigTests` (5 cas), `MouseQuadrantTests` (13 cas). 39 suites totales, 0 fail.

## [Unreleased] — branche `013-desktop-per-display`

### Added (SPEC-013 Desktop par Display)

- Mode au choix dans `[desktops] mode = "global" | "per_display"` (défaut `global`, compat V2 stricte).
- `DesktopRegistry.currentByDisplay: [CGDirectDisplayID: Int]` : current desktop par écran physique. En mode global toutes les entries sont synchronisées. En `per_display` chacune est indépendante.
- `DesktopRegistry.setCurrent(_:on:)` + `setMode(_:)` + `currentID(for:)` + `syncCurrentByDisplay(presentIDs:)`.
- En mode `per_display`, `roadie desktop focus N` cache/montre uniquement les fenêtres dont le centre tombe sur le display de la frontmost ; les autres écrans gardent leur desktop courant.
- En mode `per_display`, drag manuel cross-écran et `roadie window display N` font adopter à la fenêtre le current desktop du display cible (cohérent avec AeroSpace).
- Persistance per-display dans `~/.config/roadies/displays/<displayUUID>/{current.toml, desktops/<id>/state.toml}`.
- `DesktopPersistence` : helpers `saveCurrent / loadCurrent / saveDesktopWindows / loadDesktopWindows` avec parser TOML minimaliste (5 lignes par fenêtre).
- Recovery rebranchement écran : restoration du current desktop + des fenêtres précédemment assignées (matching N1 cgwid > N2 bundleID + title prefix). Process tué entre temps → ignoré silencieusement.
- Migration V2 → V3 idempotente au boot : déplace `~/.config/roadies/desktops/` vers `displays/<primaryUUID>/desktops/`. Préserve tous les fichiers state.toml.
- `roadie desktop list` retourne `mode` et `current_by_display: [{display_id, current}]` dans la réponse JSON.
- `roadie desktop current` retourne `mode` et `display_id` quand pertinent.
- Event `desktop_changed` enrichi : payload contient `display_id` et `mode` (FR-024). Compat ascendante : les events SPEC-011/012 existants sont préservés.
- 4 nouveaux fichiers de tests : `ConfigDesktopsModeTests`, `DesktopRegistryPerDisplayTests`, `DesktopMigrationTests`, `DesktopPersistenceTests` (37 suites au total, 0 fail).

### Fixed (bug pré-existant SPEC-011)

- `DesktopSwitcher.performSwitch` : si le desktop d'arrivée n'avait pas d'`activeStageID` sauvegardé (premier visit), aucun stage n'était activé → fenêtres restaient hidden, l'utilisateur devait créer une nouvelle fenêtre pour déclencher un layout. Fallback ajouté sur le premier stage du desktop.

## [Unreleased] — branche `012-multi-display`

### Added (SPEC-012 Multi-Display)

- Tiling indépendant par écran physique : chaque display obtient son propre arbre `TilingContainer` dans `LayoutEngine.rootsByDisplay`.
- `roadie window display <1..N|prev|next|main>` : déplace la fenêtre frontmost vers un autre écran, recalcule et applique les frames sur les deux écrans.
- `roadie display list [--json]` : liste tous les écrans connectés (index, id, uuid, nom, frame, fenêtres).
- `roadie display current [--json]` : écran contenant la fenêtre frontmost.
- `roadie display focus <selector>` : focus la première fenêtre tilée de l'écran cible.
- Recovery automatique branch/débranch : à la déconnexion d'un écran, ses fenêtres migrent vers le primary en < 500 ms. À la reconnexion, root vide créé.
- Event `display_configuration_changed` émis à chaque changement de topologie d'écrans.
- Event `display_changed` émis à chaque changement de focus d'écran actif (observable via `roadie events --follow`).
- Per-display config : section `[[displays]]` dans `roadies.toml` avec `match_index/uuid/name`, `default_strategy`, `gaps_outer`, `gaps_inner`.
- `DisplayRegistry` (actor Swift, 201 LOC effectives) : source de vérité des écrans, refresh automatique sur `NSApplication.didChangeScreenParametersNotification`.
- `DisplayProvider` protocol + `MockDisplayProvider` pour tests sans dépendance à `NSScreen.screens`.
- 0 import SkyLight/CGS/SLS dans les fichiers Display* (vérifié par `Tests/StaticChecks/no-cgs.sh`).

## [Unreleased] — branche `011-virtual-desktops`

### Added (SPEC-011 Roadie Virtual Desktops)

- Module `RoadieDesktops` (719 LOC effectives) implémentant le pattern AeroSpace.
- N desktops virtuels (1..16, défaut 10) gérés intégralement par roadie dans un seul Mac Space natif.
- Bascule offscreen/onscreen via AX (`kAXPositionAttribute`) — aucun appel SkyLight/CGS pour la bascule.
- Persistance per-desktop dans `~/.config/roadies/desktops/<id>/state.toml` (write-then-rename atomique POSIX).
- Stages V1 désormais scopés au desktop courant (`StageManager.reload(forDesktop:)`).
- Commandes CLI : `roadie desktop list / focus / current / label / back`.
- Stream d'events : `roadie events --follow [--types desktop_changed,stage_changed]` via `DesktopEventBus` (actor + AsyncStream), latence < 50 ms.
- Migration automatique V1 → V2 au premier boot : stages V1 mappés sur desktop 1.
- Archivage automatique du state SPEC-003 (UUID-keyed) en `.archived-spec003-<UUID>/`.
- Validation labels (regex `^[a-zA-Z0-9_-]{0,32}$` + liste de mots réservés `prev`/`next`/`recent`/`first`/`last`/`current`).
- Back-and-forth (`focus N` quand current=N → bascule vers recent si `back_and_forth=true`).
- Opt-out via `[desktops] enabled = false` (comportement V1 strict mono-desktop).

### Removed (SPEC-003 deprecated)

- Suppression intégrale de `Sources/RoadieCore/desktop/` (8 fichiers : DesktopInfo, DesktopManager, DesktopProvider, DesktopState, EventBus, Migration, MockDesktopProvider, SkyLightDesktopProvider).
- Suppression des CGS Spaces APIs : `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`, `CGSManagedDisplaySetCurrentSpace`.
- Suppression du case `OSAXCommand.spaceFocus` (osax handler `space_focus`).
- Suppression des structs `MultiDesktop`, `DesktopRule`, `validateDesktopRules` de `Config.swift`.
- Suppression handlers legacy `desktop.*` du `CommandRouter` (réimplémentés par SPEC-011).

### Changed

- `WindowState` étendu avec `desktopID: Int` et `expectedFrame: CGRect`.
- `Package.swift` : nouveau target `RoadieDesktops` (lib statique), test target `RoadieDesktopsTests`, dépendance ajoutée à `RoadieStagePlugin` et `roadied`.
- README mis à jour : section V2 réécrite autour du pattern AeroSpace + recommandation « désactiver Displays have separate Spaces ».
- `specs/003-multi-desktop/spec.md` marquée DEPRECATED 2026-05-02 avec lien vers SPEC-011.

### Why this pivot

Le mécanisme historique de SPEC-003 (1 Roadie Desktop = 1 Mac Space natif, bascule via `CGSManagedDisplaySetCurrentSpace`) est cassé par une régression macOS Tahoe 26 documentée ([yabai #2656](https://github.com/asmvik/yabai/issues/2656)) : le state interne change (visible sur SketchyBar et app active) mais WindowServer ne rerender plus les fenêtres. Pas de fix possible sans Apple. Pivot vers le pattern AeroSpace (validé en production sur ~17k stars GitHub) qui s'affranchit complètement des Mac Spaces natifs.

### Tests

- 168 tests verts au total (`swift test`).
- `RoadieDesktopsTests` : 33+ tests (Smoke, Parser, EventBus, DesktopRegistry, DesktopSwitcher, Perf, Ghost, Label, Migration, EventStream, Disabled, Persistence, CorruptionRecovery).
- `RoadieStagePluginTests` : 7 tests dont 5 nouveaux pour le scope per-desktop.
- `ConfigDesktopsTests` : 6 tests parsing config `[desktops]`.
- Validation statique CI : `Tests/StaticChecks/no-cgs.sh` garantit 0 import SkyLight/CGS/SLS dans `Sources/RoadieDesktops/`.

### Constitution

- Principe G LOC : 719 effectives (cible 700, plafond 900) — respecté.
- Binaire `roadied` release : 2.3 MB (plafond 5 MB) — respecté.
- 0 dépendance ajoutée vs SPEC-003 ; suppression nette de la dette legacy.
- Principe F (CLI minimaliste) : extension à 5 sous-commandes desktop justifiée dans Complexity Tracking de [plan.md](specs/011-virtual-desktops/plan.md).
