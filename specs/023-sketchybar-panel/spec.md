# Feature Specification: SketchyBar plugin desktops × stages

**Feature Branch**: `023-sketchybar-panel`
**Status**: Draft
**Created**: 2026-05-03
**Dependencies**: SPEC-013 (desktops per-display), SPEC-018 (stages per-display), SPEC-021 (single source of truth)

## Vision

Étendre la barre du haut (SketchyBar) pour afficher en un coup d'œil l'organisation **desktops × stages** courante de roadie. L'existant est minimaliste (10 numéros highlight) et ne montre rien des stages. L'objectif est une visualisation à la fidélité « pile horizontale » du mockup utilisateur :

- Chaque **desktop** est un groupe étiqueté `🏠 Bureau N` (ou son label custom si défini via `roadie desktop label`).
- Pour chaque desktop, ses **stages** sont affichés comme cartes côte à côte. La carte du stage actif a son fond coloré (vert pour stage 1, rouge pour stage 2 — héritage de `[fx.rail.preview.stage_overrides]`).
- Chaque carte stage indique **un compteur** des fenêtres tilées qu'il contient (ex: « Stage 1 (actif) · 3 »). Les icônes d'apps ne sont pas affichées (limitation SketchyBar : pas de layout vertical, et 5 icônes par stage × 3 stages × 3 desktops = saturation barre).
- Pour économiser la place, **seuls les 3 desktops les plus récemment actifs** sont affichés. Si plus de 3 desktops existent, un item `…` (trois points cliquable) résume le reste avec un compteur `+N`.
- L'état est rafraîchi en temps réel via le bridge `roadie events --follow` qui écoute déjà `desktop_changed`, étendu à `stage_changed`, `stage_assigned`, `window_assigned`, `window_destroyed`, `window_created`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Visualisation desktops + stages dans la barre (Priority: P1, MVP)

En tant qu'utilisateur de roadie, je veux voir dans SketchyBar un panneau qui synthétise mon organisation courante : quels desktops existent, quel est le desktop actif, quels stages chaque desktop contient, lequel est actif, et combien de fenêtres dans chaque stage.

**Why this priority** : c'est la valeur principale. Sans ce panneau, SketchyBar ne reflète pas l'état roadie au-delà du numéro de desktop.

**Independent Test** : créer 2 desktops avec 2 stages chacun (« Work »/« Comm » sur desktop 1, « Code »/« Doc » sur desktop 2), ouvrir 3 fenêtres réparties. Vérifier dans la barre :
- Item `🏠 Bureau 1` puis cartes `Work · 2` (vert si actif) et `Comm · 1`
- Séparateur visuel
- Item `🏠 Bureau 2` puis cartes `Code · 0` et `Doc · 0`

**Acceptance Scenarios** :
1. **Given** un état roadie avec 2 desktops et 2 stages chacun, **When** SketchyBar boote, **Then** le panneau affiche les 2 desktops + leurs stages avec couleur active correctement.
2. **Given** le panneau affiché, **When** l'utilisateur switche stage via raccourci ⌥1/⌥2, **Then** la couleur active migre dans la barre en moins de 500 ms.
3. **Given** le panneau affiché, **When** l'utilisateur déplace une fenêtre entre stages via drag-drop dans le navrail roadie, **Then** le compteur se met à jour automatiquement en moins de 1 s.
4. **Given** le panneau affiché, **When** l'utilisateur clique sur une carte stage, **Then** roadie switche vers ce stage (équivalent CLI `roadie stage <id>`).

---

### User Story 2 — Bouton "+" pour créer un nouveau stage (Priority: P2)

En tant qu'utilisateur, je veux pouvoir créer un nouveau stage directement depuis la barre via un bouton `+` à la fin de chaque desktop.

**Why this priority** : qualité de vie, permet de scaler son organisation sans aller dans la CLI. Pas critique pour le MVP.

**Acceptance Scenarios** :
1. **Given** un desktop avec 3 stages, **When** l'utilisateur clique sur le `+` à la fin du groupe de ce desktop, **Then** un nouveau stage 4 est créé (CLI équivalent `roadie stage create <id> "<auto-name>"`) et apparaît dans la barre en moins de 1 s.
2. **Given** un desktop avec 0 stage (juste après création), **When** l'utilisateur clique sur le `+`, **Then** stage 1 est créé.

---

### User Story 3 — Cap d'affichage avec overflow `…` (Priority: P2)

En tant qu'utilisateur power qui crée jusqu'à 10 desktops, je veux que la barre reste lisible même avec beaucoup de desktops, en n'affichant que les 3 plus récemment actifs et un indicateur `… +N` pour le reste.

**Why this priority** : sans cap, 10 desktops × 4 stages = 40 cartes saturent la barre. Avec cap, l'utilisateur garde le focus sur ce qui est utilisé activement.

**Acceptance Scenarios** :
1. **Given** 5 desktops avec utilisation récente : 1, 3, 4 récents et 2, 5 anciens, **When** SketchyBar refresh, **Then** la barre montre `Bureau 1`, `Bureau 3`, `Bureau 4` + un item `… +2` cliquable.
2. **Given** ≤ 3 desktops, **When** SketchyBar refresh, **Then** aucun overflow item, tous les desktops affichés.
3. **Given** l'item `… +N` cliqué, **When** l'utilisateur clique, **Then** un menu (ou simplement focus sur le desktop suivant non-affiché) — comportement défini en Phase 5 implem (le plus simple suffira).

---

### User Story 4 — Installation reproductible via script (Priority: P1)

En tant que mainteneur du repo roadie, je veux que les scripts SketchyBar vivent dans le repo (versionnés) et soient installés via `scripts/sketchybar/install.sh` qui copie/symlink vers `~/.config/sketchybar/sketchybar/`.

**Why this priority** : sans ça, les scripts ne sont pas versionnés, donc perdus à chaque réinstall ou inutiles pour d'autres utilisateurs roadie.

**Acceptance Scenarios** :
1. **Given** un fresh checkout du repo, **When** l'utilisateur exécute `./scripts/sketchybar/install.sh`, **Then** les fichiers sont symlinkés dans `~/.config/sketchybar/sketchybar/{items,plugins}/`, l'utilisateur peut `sketchybar --reload` et voir le panneau.
2. **Given** des fichiers existants dans `~/.config/sketchybar/sketchybar/{items,plugins}/`, **When** install.sh tourne, **Then** ils sont backupés avec suffix `.bak` avant le symlink.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** : un nouveau script `scripts/sketchybar/items/roadie_panel.sh` DOIT générer dynamiquement les items SketchyBar pour les desktops × stages au boot et à chaque event roadie pertinent. Idempotent (re-run = même résultat).
- **FR-002** : le script DOIT consommer `roadie desktop list --json` + `roadie stage list --display X --desktop N --json` + `roadie windows list --json` pour reconstruire l'état complet.
- **FR-003** : pour chaque desktop affiché, un item `roadie.desktop.N` (label header) + un item `roadie.stage.N.M` par stage (cliquable, switch). Pour chaque desktop, un item `roadie.add.N` (bouton "+", cliquable, crée nouveau stage).
- **FR-004** : le stage actif d'un desktop a son `background.color` mis à la couleur définie dans `[fx.rail.preview.stage_overrides]` du TOML utilisateur (parsing du TOML côté script). Fallback sur une couleur "active" globale si pas d'override pour ce stage.
- **FR-005** : les stages inactifs ont un `background.color` neutre gris (héritage de `[fx.rail.preview].border_color_inactive`).
- **FR-006** : le compteur de fenêtres affiché à côté du nom du stage est lu via `roadie windows list --json | jq` filtré par `stage == X` et `desktop_id == N`. Refresh à chaque `window_*` event.
- **FR-007** : si plus de 3 desktops existent, seuls les 3 plus récents (basé sur `roadie desktop list --json` qui retourne les desktops dans l'ordre de dernière activité) sont affichés. Un item `roadie.overflow` montre `… +N` cliquable. Le compteur `N` est le nombre de desktops cachés.
- **FR-008** : un nouveau script `scripts/sketchybar/plugins/roadie_panel.sh` (handler) est appelé à chaque event SketchyBar custom roadie. Il regenère les items via remove + add pour rester simple (~50 LOC).
- **FR-009** : le bridge `scripts/sketchybar/plugins/roadie_event_bridge.sh` étend le filtre actuel pour inclure : `desktop_changed`, `stage_changed`, `stage_assigned`, `window_assigned`, `window_destroyed`, `window_created`. À chaque event, déclenche `sketchybar --trigger roadie_state_changed`.
- **FR-010** : le script d'install `scripts/sketchybar/install.sh` symlinke chaque fichier `scripts/sketchybar/{items,plugins}/*` vers `~/.config/sketchybar/sketchybar/{items,plugins}/`. Backup `.bak` si fichier cible existe et n'est pas déjà un symlink vers la même cible.
- **FR-011** : install.sh ajoute (ou met à jour) les 2 lignes nécessaires dans `~/.config/sketchybar/sketchybarrc` :
  - `source "$ITEM_DIR/roadie_panel.sh"`
  - `"$PLUGIN_DIR/roadie_event_bridge.sh" &`
  Idempotent : pas d'ajout en double si déjà présent.
- **FR-012** : le click sur une carte stage déclenche `roadie stage <stage_id> --display <displayUUID> --desktop <desktopID>` (scope explicite pour ne pas déranger l'autre display, cf SPEC-022).
- **FR-013** : le click sur le bouton "+" d'un desktop déclenche `roadie stage create <next_id> "stage <next_id>" --display X --desktop N`. `next_id` = max stage_id existant + 1.
- **FR-014** : le click sur l'overflow `… +N` déclenche un cycle vers le desktop suivant non-affiché (`roadie desktop focus next`). Solution simple, pas de menu déroulant.

### Non-Functional Requirements

- **NFR-001** : refresh de la barre ≤ 500 ms après un event roadie.
- **NFR-002** : LOC plafond strict : 250 LOC totales pour les 4 fichiers bash (panel.sh items + handler + bridge ajusté + install.sh).
- **NFR-003** : zéro dépendance externe nouvelle. Réutilise `jq` (déjà utilisé dans le bridge existant).
- **NFR-004** : compatible avec `sketchybarrc` existant — n'écrase aucun item utilisateur, ajoute seulement.

## Success Criteria *(mandatory)*

- **SC-001** : avec 2 desktops × 2 stages, SketchyBar affiche correctement les 2 groupes avec couleurs actives. Vérifié visuellement.
- **SC-002** : un switch de stage via ⌥1 → ⌥2 met à jour la couleur active dans la barre en ≤ 500 ms.
- **SC-003** : un drag-drop de fenêtre entre stages dans le navrail incrémente/décrémente les compteurs en ≤ 1 s.
- **SC-004** : un click sur une carte stage déclenche le switch.
- **SC-005** : avec 5 desktops, la barre montre 3 + l'overflow `… +2`.
- **SC-006** : `./scripts/sketchybar/install.sh` sur un fresh checkout fonctionne, `sketchybar --reload` affiche le panneau.
- **SC-007** : `wc -l` cumulé des 4 fichiers bash ≤ 250 LOC.

## Edge Cases

- **EC-001** : roadie daemon down. Le panneau affiche un état dégradé (ex: tous desktops grisés, message « roadie daemon down ») au lieu de crasher.
- **EC-002** : `roadie events --follow` crash et redémarre. Bridge déjà gère le retry (existant). Le panneau se resynchronise au reconnect.
- **EC-003** : un desktop avec 0 stage. Affiche juste le header + le bouton "+", pas de carte stage.
- **EC-004** : un stage avec 0 fenêtre. Compteur `· 0` (pas omis pour cohérence).
- **EC-005** : nom de stage très long (> 20 caractères). Tronqué à 18 char + `…`.
- **EC-006** : `[fx.rail.preview.stage_overrides]` absent du TOML. Fallback sur couleur active globale (ex: vert système `#34C759`).
- **EC-007** : SketchyBar pas installé sur la machine. `install.sh` détecte l'absence et abort proprement avec message d'erreur clair.

## Assumptions

- **A-001** : `jq` est disponible (déjà assumption du bridge existant).
- **A-002** : `roadie events --follow --types ...` accepte les types `stage_changed`, `stage_assigned`, `window_*` (vérifié SPEC-019 : la allow-list serveur a été étendue à 16 types).
- **A-003** : `roadie desktop list --json` retourne les desktops dans l'ordre de dernière activité (à vérifier en Phase 2 ; sinon ajout d'un sort côté script bash).
- **A-004** : `roadie stage list --json --display X --desktop N` existe et retourne `[{id, display_name, isActive, ...}]`. À vérifier sinon ajout dans la CLI.
- **A-005** : `roadie windows list --json` retourne pour chaque wid son `stage` (string id) et son `desktop_id` (int). Cf payload existant SPEC-019.

## Out of scope

- Animations dans SketchyBar (slide, fade) — natif limité, pas critique.
- Mode survol qui montre les icônes d'apps individuelles dans un popover SketchyBar.
- Configuration TOML de la barre elle-même (couleurs, padding) — pour l'instant on hérite des couleurs roadie. Une éventuelle config dédiée serait `[sketchybar]` à part, plus tard.
- Drag-drop directement depuis SketchyBar pour réassigner une fenêtre. Le navrail roadie le fait déjà.
- Menu contextuel sur clic-droit (rename, delete stage). Pour l'instant, uniquement clic-gauche pour switch.
