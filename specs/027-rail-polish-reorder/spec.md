# SPEC-027 — Rail polish & stage reorder

**Statut** : Implémenté
**Date** : 2026-05-05
**Branche** : `026-wm-parity` (suite directe SPEC-026, pas de branche dédiée — features de polish UI)

## Contexte

Trois irritants UX du navrail signalés par l'utilisateur après usage quotidien post-SPEC-026 :

1. **Badge stage en arrière-plan** (`fx.rail.stage_numbers_*`) qui déborde verticalement (`offset_y` négatif) reste visible **par-dessus** la cellule de la stage du dessus dans le navrail. Voulu : le badge passe **derrière** toutes les vignettes (z-order global), pas seulement derrière la vignette de sa propre cellule.
2. **`smart_gaps_solo`** (SPEC-026 US2) supprime *tous* les gaps quand un display contient une seule fenêtre tilée. Trop binaire : l'utilisateur veut conserver `gaps_outer_left = 150` (réserve navrail) mais que les autres côtés tombent à 0 — ou n'importe quelle combinaison.
3. **Ordre des stages** dans le navrail figé par ordre de création. Voulu : drag-and-drop d'une cellule de stage par-dessus une autre pour réordonner, ordre persistant par scope `(display, desktop)`.

## User stories

### US1 — Badge stage z-index global

En tant qu'utilisateur du navrail, je veux que le mot/numéro affiché en arrière-plan d'une stage passe physiquement **derrière** les vignettes des stages voisines quand il déborde, pour que le rendu reste lisible quel que soit l'`offset_y` configuré.

**Critère d'acceptation** : avec `[fx.rail].stage_numbers_offset_y = -40` et 3 stages empilées, le badge de la 2e stage qui déborde de 40px vers le haut est partiellement masqué par la vignette de la 1ère stage (et non l'inverse).

### US2 — Smart gaps solo sélectif

En tant qu'utilisateur, je veux pouvoir préciser quels côtés de gaps tomber à 0 quand `smart_gaps_solo` est actif, plutôt que tous-ou-rien.

**Config TOML** :

```toml
[tiling]
smart_gaps_solo = true
smart_gaps_solo_sides = ["top", "bottom", "right"]   # default = ["top","bottom","left","right"] (= comportement SPEC-026)
```

Sémantique :
- `smart_gaps_solo = false` ou non défini → no-op, on garde les gaps configurés (override absolu).
- `smart_gaps_solo = true` + `smart_gaps_solo_sides` non défini → tous les côtés à 0 (rétrocompat SPEC-026).
- `smart_gaps_solo = true` + `smart_gaps_solo_sides = []` → équivalent `smart_gaps_solo = false`.
- `smart_gaps_solo = true` + `smart_gaps_solo_sides = [...]` → seuls les côtés listés tombent à 0, les autres gardent leur valeur configurée.

`gaps_inner` n'est pas concerné par `_sides` (zéro fenêtre voisine = inner sans objet) — il tombe à 0 dès que `smart_gaps_solo = true` et que sides est non-vide.

**Critère d'acceptation** : avec `gaps_outer = 8`, `gaps_outer_left = 150`, `smart_gaps_solo = true`, `smart_gaps_solo_sides = ["top","bottom","right"]` et 1 fenêtre, la fenêtre est cadrée à `(left=150, top=0, right=0, bottom=0)`.

### US3 — Drag-reorder des stages

En tant qu'utilisateur, je veux pouvoir attraper une cellule de stage dans le navrail et la lâcher au-dessus d'une autre cellule pour qu'elles soient permutées dans la liste affichée.

**Comportement** :
- Drag stage A sur stage B (A ≠ B, même display+desktop) → A prend la position de B, B et toutes les stages qui étaient après B descendent d'un cran.
- L'ordre est persisté dans le state file et survit aux restarts du daemon.
- Une commande CLI `roadie stage move-before <stage_id> <target_id>` et `roadie stage move-after` reflète la même API au niveau daemon.

**Critère d'acceptation** : 3 stages dans l'ordre `[1, 3, switch]`, drag `switch` sur `1` → ordre `[switch, 1, 3]`. Restart daemon, ordre conservé.

## Contraintes constitution

- Article 0 (minimalisme) : pas de refactor surrounding. Touches chirurgicales.
- Article G (LOC) : SPEC-027 reste sous 200 LOC effectives ajoutées au cumul SPEC-026. Vérification via `find ... | grep -vE '^\s*$|^\s*//'`.
- Tests : tests unitaires sur logique pure (smart_gaps_solo_sides resolver, stage order math).
- Pas de dépendance scripting addition (SIP-on strict).

## Critical files

- **NEW** `specs/027-rail-polish-reorder/spec.md` (ce fichier)
- **MODIFIED** `Sources/RoadieRail/Views/StageStackView.swift` (US1 layout 2-couches)
- **MODIFIED** `Sources/RoadieCore/Config.swift` (US2 champ `smartGapsSoloSides`)
- **MODIFIED** `Sources/RoadieTiler/LayoutEngine.swift` (US2 application sélective)
- **MODIFIED** `Sources/RoadieStagePlugin/StageManager.swift` (US3 ordre persistant + reorder)
- **MODIFIED** `Sources/roadied/CommandRouter.swift` (US3 case `stage.reorder`)
- **MODIFIED** `Sources/roadie/main.swift` (US3 sous-verbe `stage move-before/move-after`)
- **MODIFIED** `Sources/RoadieRail/Views/StageStackView.swift` (US3 onDrag/onDrop sur cellules)

## Verification

1. Build : `swift build -c release` doit passer sans warning nouveau.
2. Install : `./scripts/install-dev.sh` réussit, daemon UP.
3. US1 visuel : badge stage déborde et passe sous la cellule du dessus avec `offset_y = -40`.
4. US2 visuel : avec `smart_gaps_solo_sides = ["top","bottom","right"]` et 1 fenêtre, la marge gauche reste 150px, les autres à 0.
5. US3 visuel : drag stage 3 par-dessus stage 1 → ordre devient `[3, 1, ...]` et persiste après `launchctl kickstart -k`.
6. CLI : `roadie stage move-before 3 1` et `roadie stage move-after 1 3` ont le même résultat final.
7. `roadie daemon audit` reste à 0 violations post-modifications.
