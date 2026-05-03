# Research: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Spec**: SPEC-022
**Date**: 2026-05-03

## R-001 — Promotion de `activeStageByDesktop` au rang de source de vérité

**Decision** : `StageManager.activeStageByDesktop[DesktopKey]` (déjà présent depuis SPEC-018) devient l'unique source de vérité de "stage active de tel (display, desktop)". `currentStageID` (scalaire global) devient une propriété **calculée** dérivant de `currentDesktopKey`.

**Rationale** :
- Le dict existe déjà, est persisté via `_active.toml` per-(display, desktop), et est mis à jour par `setCurrentDesktopKey`. Toute la machinerie est en place.
- Le scalaire global `currentStageID` est la racine du bug B (cross-display switch). Le retirer comme état stocké force tous les call sites à passer par le tuple, ce qui rend l'erreur impossible.
- La compat backward est triviale : le getter calculé renvoie `activeStageByDesktop[currentDesktopKey]`.

**Alternatives considérées** :
- Garder `currentStageID` ET `activeStageByDesktop` synchronisés à la main : trop fragile, déjà la source du bug.
- Renommer `currentStageID` en `currentStageScope` partout : refactoring brutal, casse le wire-format JSON exposé via `stage list`.

## R-002 — `switchTo(stageID:scope:)` overload + wrapper compat

**Decision** : ajouter `switchTo(stageID:scope:)` qui prend un `StageScope` explicite. L'ancien `switchTo(stageID:)` devient un wrapper qui résout le scope depuis `currentDesktopKey`.

**Rationale** :
- Préserve toutes les call-sites V1 existantes.
- Force les nouvelles call-sites (CommandRouter `stage.switch`) à expliciter le scope.

**Alternatives** : modifier la signature en place et casser tous les callers — trop de blast radius.

## R-003 — `EmptyView` SwiftUI pour stage vide

**Decision** : dans chaque renderer (Parallax45, StackedPreviews, Mosaic, HeroPreview, IconsOnly), remplacer le `emptyPlaceholder` par `EmptyView()` du framework SwiftUI. La cellule reste dans la VStack pour conserver le tap-target et la zone de drop, mais son contenu visuel est invisible.

**Rationale** :
- `EmptyView` est le pattern standard SwiftUI pour "rien à afficher".
- Coût render = 0 (pas de view tree créé).
- Conserve la position du stage dans le layout vertical, donc l'utilisateur peut toujours cliquer sur cette zone (le `StageStackView` wrap chaque cellule dans un container interactif).

**Alternatives** :
- Skipper la cellule entièrement dans le `ForEach` : casse l'invariant "stage existe en data → ligne dans la rail". L'utilisateur perdrait le drop-target.
- Hauteur cellule à 0 : casse le rendu de fond / espacement.

**Note dev** : le `private var emptyPlaceholder` peut être conservé dans le code source (dead code temporaire) avec un commentaire pour permettre un mode debug ultérieur. Mais pas branché par défaut.

## R-004 — Pas de migration disque

**Decision** : aucun changement de format TOML. Le fichier `_active.toml` per (display, desktop) (introduit SPEC-018) est déjà la persistance correcte de `activeStageByDesktop`.

**Rationale** :
- Le format est :
  ```toml
  current_stage = "3"
  ```
  dans `~/.config/roadies/stages/<UUID>/<desktopID>/_active.toml`.
- `loadActiveStagesByDesktop()` peuple déjà `activeStageByDesktop` depuis ces fichiers au boot.
- Le seul changement est : `currentStageID` (qui était dans `~/.config/roadies/stages/active.toml`, scalaire global) devient calculé. Le fichier `active.toml` global devient obsolète mais n'est pas supprimé (sera ignoré silencieusement).

**Migration** : aucune. Premier boot post-refactor : `currentStageID` getter renvoie l'active du `currentDesktopKey` courant (ou nil si aucun, fallback à stage 1).

## R-005 — Hide/show scope-aware

**Decision** : `switchTo(stageID:scope:)` ne hide/show que les windows dont `WindowState.displayUUID == scope.displayUUID` ET `WindowState.desktopID == scope.desktopID`. Les windows des autres scopes restent intouchées.

**Rationale** :
- Aujourd'hui `switchTo(stageID:)` itère sur **toutes** les windows du registry (cf. `widsToHide = registry.allWindows.filter { $0.stageID != stageID }`). C'est correct pour single-display, faux pour multi-display.
- Le filter `state.displayUUID == scope.displayUUID && state.desktopID == scope.desktopID` est précis et utilise les champs déjà tracés sur `WindowState`.

**Risque** : si `WindowState.displayUUID` est stale (désync avec la position réelle de la window après drag cross-display), une window peut être hidée/shown sur le mauvais scope. **Mitigation** : SPEC-013 garantit que `displayUUID` est mis à jour par `axDidMoveWindow` lors d'un drag cross-display. Les tests acceptance vérifient ce cas.

## R-006 — Comportement après hot-plug d'un display

**Decision** : pas de changement. Si l'utilisateur déconnecte un display avec stages actives, les entrées `stagesV2[(uuid, *, *)]` restent en mémoire et sur disque (pas de cleanup). Les windows orphelines sont gérées par les mécanismes SPEC-012 existants.

**Rationale** : conforme à SPEC-012, hors scope.

## R-007 — Compat avec le rail panel V2 (per-display panels)

**Decision** : le rail envoie déjà `display: <UUID>` dans `stage.switch` depuis SPEC-019. Le CommandRouter résout ça en scope explicite. Aucun changement côté rail.

**Validation** : grep `stage.switch` dans `Sources/RoadieRail/` confirme que les call-sites passent l'UUID du panel d'origine. Pas de path qui appelle `stage.switch` sans display arg.
