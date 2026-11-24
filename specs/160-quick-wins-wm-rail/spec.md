# Spec 160 — Quick Wins WM & NavRail

## Contexte

Suite à la livraison des Lots 1 et 2 (Spec 158 et Spec 159), ce Lot 3 regroupe cinq gains rapides d'ergonomie très demandés sur le gestionnaire de fenêtres et le NavRail, 100 % locaux et compatibles avec l'ensemble des modes et paramètres existants :

1. **`roadie window close [WINDOW_ID]`** : implémenter la fermeture gracieuse d'une fenêtre via son bouton de fermeture Accessibility (`kAXCloseButtonAttribute`), activer la commande jusque-là marquée `implemented: false` dans `CLICommandRouter`, et l'exposer dans le Lanceur et le menu contextuel du NavRail.
2. **`roadie layout rotate 90|180|270` et `roadie layout mirror x|y`** : opérations algébriques pures sur `BSPTree` (`rotated(degrees:)` et `mirrored(axis:)`), exposées via `LayoutCommandService`, la CLI, la complétion zsh, le Lanceur et le menu contextuel du NavRail.
3. **`roadie window gather-app`** : rassemble en une commande atomique toutes les autres fenêtres gérées (hors plein écran natif) de la même application (`bundleID`) dispersées sur d'autres stages/écrans vers la stage active de la fenêtre focalisée (ou de la fenêtre cliquée dans le NavRail), en mettant à jour les arbres BSP et les placements en un seul `CommandPlacement`.
4. **Suivi du curseur complet (`focus.mouse_follows_focus`)** : étendre l'usage du réglage existant `focus.mouse_follows_focus` (déjà toggleable dans **Paramètres > Focus**) aux bascules de stage (`StageCommandService.switchDisplay`) et aux changements d'écran (`DisplayCommandService.focus`), afin que le curseur suive la fenêtre focalisée sur toutes les navigations clavier.
5. **Retour visuel et infobulle dynamique au survol des icônes d'application du NavRail** : lorsque le curseur survole une icône de la rangée sous une vignette (`fx.rail.show_app_icons_row = true`), mettre en valeur l'icône (halo discret + léger agrandissement) et mettre à jour l'infobulle de la carte avec le nom et le titre exact de la fenêtre ciblée (en restaurant l'infobulle de la stage dès que la souris quitte l'icône).

## Exigences fonctionnelles

- **FR-001 (`window close`)** : `WindowFrameWriting.close(_ window: WindowSnapshot) -> Bool` appuie sur `kAXCloseButtonAttribute` dans `AXWindowFrameWriter`. `WindowCommandService.close(windowID: WindowID? = nil)` ferme la fenêtre ciblée ou active, journalise `window_close`, et `CLICommandRouter` expose `window close` (`implemented: true`).
- **FR-002 (`layout rotate` & `layout mirror`)** :
  - `BSPTree.rotated(degrees:)` pour `90`, `180`, `270` (rotation horaire : 90° enchaîné 4 fois = identité ; 90° puis 270° = identité).
  - `BSPTree.mirrored(axis:)` pour `.x` (miroir gauche/droite) et `.y` (miroir haut/bas), involutifs (`mirrored(axis).mirrored(axis) == self`).
  - `LayoutCommandService.rotate(_ degrees: Int)` et `LayoutCommandService.mirror(_ axis: String)` appliquent la mutation sur l'arbre BSP de la stage active (`spatialBsp`) et replacent les fenêtres immédiatement.
- **FR-003 (`window gather-app`)** : `WindowCommandService.gatherApp(windowID: WindowID? = nil)` déplace atomiquement dans la stage active toutes les autres fenêtres vivantes gérées du même `bundleID` (hors plein écran natif) provenant d'autres stages, met à jour les arbres BSP source/cible et applique un seul `CommandPlacement`.
- **FR-004 (`mouse_follows_focus` étendu)** : `StageCommandService` et `DisplayCommandService` invoquent `MouseFollower.follow(_:)` après un focus réussi (sans effet quand `focus.mouse_follows_focus` est désactivé).
- **FR-005 (Survol des icônes NavRail)** : `StageCardView.updateHoveredAppIcon(at:)` détecte l'icône survolée (en inversant la perspective 3D si mode `parallax`), applique un halo/agrandissement subtil au dessin, met à jour `toolTip` avec le nom d'application et le titre de fenêtre, et restaure l'infobulle de la stage hors survol. Aucun nouveau timer : branché sur `RailController.updateRailHover()`.
- **FR-006 (Exposition Lanceur, NavRail, CLI & Documentation)** : nouvelles entrées dans `LauncherSystemCommands`, menu contextuel `RailController`, `CLICommandRouter`, `docs/fr/features.md`, `docs/en/features.md` et `CHANGELOG.md`.

## Critères d'acceptation

- Invariants algébriques `BSPTree` vérifiés (`rotate 90×4 == id`, `rotate 90+270 == id`, `rotate 180 == mirror x + mirror y`, `mirror x×2 == id`, `mirror y×2 == id`).
- `window close`, `window gather-app`, `layout rotate 90|180|270`, `layout mirror x|y` testés bout en bout via services et `CLICommandRouter`.
- `MouseFollower` vérifié sur bascule de stage et focus d'écran (actif seulement si activé).
- Survol d'icône `StageCardView` vérifié (mise à jour `hoveredAppIconWindowID`, infobulle dynamique et restauration hors survol).
- 0 régression sur l'ensemble des suites Swift (`./scripts/test --no-parallel`) et Python (`unittest`).
