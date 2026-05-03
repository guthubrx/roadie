# Implementation: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Spec**: SPEC-022 | **Branch**: `022-multi-display-isolation` | **Date**: 2026-05-03

## Statut

- ✅ **US1** — Cross-display isolation : `switchTo(stageID:scope:)` opérationnel, vérifié sur 2 displays réels
- ✅ **US2** — Empty stage rendering : 4 renderers patchés (Parallax45, Mosaic, HeroPreview, IconsOnly) ; StackedPreviews déjà OK car pas de placeholder explicite
- ⏸ **US3** — Régression desktop : non testé formellement, le path SPEC-013 reste inchangé donc OK par isolation

## Fichiers touchés

| Fichier | Changement | Lignes |
|---|---|---|
| `Sources/RoadieStagePlugin/StageManager.swift` | Ajout `switchTo(stageID:scope:)` overload | +37 |
| `Sources/roadied/CommandRouter.swift` | Bascule sur API scopée + per-display current dans `stage.list` | +13/-5 |
| `Sources/RoadieRail/Renderers/Parallax45Renderer.swift` | `EmptyView()` au lieu de `emptyPlaceholder` | +2/-1 |
| `Sources/RoadieRail/Renderers/MosaicRenderer.swift` | idem | +2/-1 |
| `Sources/RoadieRail/Renderers/HeroPreviewRenderer.swift` | idem | +2/-1 |
| `Sources/RoadieRail/Renderers/IconsOnlyRenderer.swift` | `EmptyView()` au lieu de `HStack` placeholder | +2/-7 |

**Total** : ~50 lignes nettes ajoutées, 0 fichier nouveau, 0 dépendance ajoutée.

## Tests

### CLI manuel (validé)

```bash
# Setup : 2 displays, 3 windows sur built-in (display 1, frames capturées)
$ roadie windows list
2752  Firefox  1085,43 950x1172 stage=1
12    iTerm    125,43 470x1172 stage=1
15    iTerm    605,34 470x1172 stage=1

# Switch LG (display 2) sur stage 2
$ roadie stage 2 --display 2
current: 2

# Vérification : aucune window de display 1 n'a bougé
$ roadie windows list
2752  Firefox  1085,43 950x1172 stage=1
12    iTerm    125,43 470x1172 stage=1
15    iTerm    605,34 470x1172 stage=1
# ✅ frames identiques

# Vérification : LG affiche bien stage 2 comme active
$ roadie stage list --display 2
Current stage: 2
  1 (1) — 3 window(s)
* 2 (stage 2) — 0 window(s)
```

### Visuel (à valider par utilisateur)

- Rail panel sur display sans windows → stages vides, pas de placeholder "Empty stage"
- Click sur stage du panel LG → marque ce stage actif dans le panel LG, pas d'effet sur built-in

## Décisions notables

- **Scope distant = data-only update** : quand un click switche une stage hors du scope visible courant, on met à jour `activeStageByDesktop` + persiste `_active.toml`, mais on NE déclenche PAS hide/show ni applyLayout. Conséquence : si l'utilisateur a 2 windows sur le LG (stage 1 active visible) et clique sur stage 3 du panel LG, les windows ne se cachent PAS et stage 3 reste vide à l'écran. Le panel LG marque visuellement stage 3 active. Quand l'utilisateur déplace son curseur sur le LG (ou explicite `--display 2` sur d'autres commandes), le scope visible bascule et alors le rendu actuel reflète stage 3.
- C'est la "lazy switch" — explicitement minimaliste pour ne pas casser l'état du display visible courant. Trade-off : si l'utilisateur veut un switch "agressif" qui rend immédiatement les windows du LG, il faut un raccourci séparé qui combine `desktop.focus + stage 3` ou un hot-plug de `currentDesktopKey`. Décision : hors scope SPEC-022, possible follow-up.

## Limitations connues

- **`LayoutEngine.workspace.activeStageID` reste global** — utilisé par `applyAll` pour décider de la stage à tiler par display (en pratique iter par display × activeSID global). Tant qu'on n'a pas un activeStageID per-display dans LayoutEngine, le re-tile d'un display non-currentDesktopKey utilise la mauvaise stage. Mitigé par : on ne déclenche jamais `applyLayout` après un switch distant. Suffisant pour résoudre les bugs A et B observés.
- **Rail panel UI** : la cellule vide a toujours un cadre/halo. Si l'utilisateur veut zéro empreinte visuelle, il faut une passe sur `StageStackView` pour conditionner le rendu du fond.

## Suivi possible (post-022)

- SPEC-022b : promouvoir `LayoutEngine.workspace.activeStageID` en dict per-display.
- SPEC-022c : option de switch agressif (raccourci séparé pour basculer + tiler le display cible).
- Tests acceptance bash : `Tests/22-*.sh` pour automatiser la vérification cross-display isolation.
