# Feature Specification: WM-Parity Hyprland/Yabai (Lot Consolidé)

**Feature Branch**: `026-wm-parity`
**Created**: 2026-05-05
**Status**: Draft
**Dependencies**: SPEC-016 (rules infrastructure), SPEC-022 (per-display stage scope), SPEC-025 (observability)
**Input**: lot consolidé de 9 fonctionnalités inspirées de Hyprland et yabai pour amener `roadied` à parité fonctionnelle, en SIP-on strict, sous plafond LOC ~700-900.

## User Scenarios & Testing

### User Story 1 — Quick-wins commandes tree (Priority: P1)

L'utilisateur veut équilibrer, faire pivoter ou inverser la disposition de ses fenêtres tilées via 3 commandes CLI simples. C'est l'apport le plus immédiat en ROI/effort : opérations atomiques, déterministes, aucun comportement passif, parité directe avec yabai (`--balance`, `--rotate`, `--mirror`).

**Why this priority**: Effort minime (~80 LOC total estimé), gain quotidien fort (reset rapide après resize manuels, repositionnement express), aucune surface de risque (pas de toggle, pas de poll, pas de hook). Ces commandes débloquent le ressenti "tiling expressif" qui manque par rapport à yabai.

**Independent Test**: Avec 3 fenêtres tilées dans un layout BSP déséquilibré (70/15/15), exécuter `roadie tiling balance` → vérifier que les 3 fenêtres ont la même surface (33% chacune, ±1px). Exécuter `roadie tiling rotate 90` → vérifier que les containers H sont devenus V (et inversement) et que l'orientation visuelle a basculé. Exécuter `roadie tiling mirror x` → vérifier que les positions left/right sont inversées dans chaque container horizontal.

**Acceptance Scenarios**:

1. **Given** 3 fenêtres avec adaptiveWeight respectifs (3.0, 0.5, 0.5), **When** l'utilisateur exécute `roadie tiling balance`, **Then** tous les adaptiveWeight sont égaux à 1.0 et la prochaine apply produit des frames de surface équivalente.
2. **Given** un layout BSP racine `[H: A, [V: B, C]]`, **When** l'utilisateur exécute `roadie tiling rotate 90`, **Then** la racine devient `[V: A, [H: B, C]]` (orientations inversées récursivement).
3. **Given** un layout `[H: A, B, C]`, **When** l'utilisateur exécute `roadie tiling mirror x`, **Then** le layout devient `[H: C, B, A]` (ordre des children inversé pour les containers horizontaux).
4. **Given** une seule fenêtre tilée, **When** l'utilisateur exécute n'importe laquelle des 3 commandes, **Then** la commande est un no-op silencieux (pas d'erreur, pas de log warn).

---

### User Story 2 — Smart gaps solo (Priority: P1)

Quand un display ne contient qu'une seule fenêtre tilée, l'utilisateur veut que les marges (outer + inner gaps) soient automatiquement supprimées pour que la fenêtre occupe tout l'écran utile. Comportement opt-in (préserve l'existant par défaut).

**Why this priority**: ~10 LOC, gros impact visuel net (fenêtre solo = vraie utilisation plein écran). Pattern standard Hyprland (`smart_gaps`).

**Independent Test**: Avec `[tiling] smart_gaps_solo = true` dans le TOML, ouvrir une seule fenêtre tilée sur le display X → vérifier que la frame de la fenêtre = visibleFrame du display (zéro gap). Ouvrir une seconde fenêtre tilée sur le même display → les gaps reprennent leur valeur configurée.

**Acceptance Scenarios**:

1. **Given** `smart_gaps_solo = false` (défaut), **When** une seule fenêtre est tilée, **Then** les gaps configurés s'appliquent normalement (comportement actuel inchangé).
2. **Given** `smart_gaps_solo = true` et `gaps_outer = 8`, `gaps_inner = 10`, **When** une seule fenêtre est tilée sur display X, **Then** la fenêtre occupe `display.visibleFrame` exact (gaps = 0 sur ce display).
3. **Given** `smart_gaps_solo = true` et 2 fenêtres tilées, **When** l'utilisateur ferme l'une des 2, **Then** la fenêtre restante voit ses gaps mis à 0 au prochain `applyAll`.

---

### User Story 3 — Scratchpad toggle (Priority: P2)

L'utilisateur veut pouvoir lancer un terminal/calculette/lecteur via une commande, le cacher quand il n'en a plus besoin, et le rappeler instantanément avec un raccourci. Pattern Hyprland "special workspace". La fenêtre est sticky par défaut (visible quel que soit le stage actif sur le display courant).

**Why this priority**: Forte utilité quotidienne power-user (terminal volant, prise de notes rapide). Effort estimé ~120 LOC. Pas critique pour la parité de base mais transforme l'expérience.

**Independent Test**: Configurer `[[scratchpads]] name = "term" cmd = "open -na 'iTerm'"`. Exécuter `roadie scratchpad toggle term` → un iTerm se lance et apparaît visible. Re-exécuter `roadie scratchpad toggle term` → l'iTerm devient invisible (offscreen) sans être quitté. Re-exécuter à nouveau → revient à sa position visible précédente.

**Acceptance Scenarios**:

1. **Given** scratchpad `term` non-lancé, **When** l'utilisateur exécute `roadie scratchpad toggle term`, **Then** la commande `cmd` est lancée, la fenêtre résultante est marquée scratchpad, et elle est visible au centre de l'écran courant.
2. **Given** scratchpad `term` visible, **When** l'utilisateur exécute `roadie scratchpad toggle term`, **Then** la fenêtre est cachée offscreen mais le process reste vivant.
3. **Given** scratchpad `term` caché, **When** l'utilisateur exécute `roadie scratchpad toggle term`, **Then** la fenêtre revient à sa dernière position visible.
4. **Given** aucune section `[[scratchpads]]` dans le TOML, **When** l'utilisateur exécute `roadie scratchpad toggle term`, **Then** la commande renvoie une erreur claire "scratchpad not configured".

---

### User Story 4 — Sticky cross-stage par-fenêtre (Priority: P2)

L'utilisateur veut marquer certaines fenêtres (via rule TOML) comme "toujours visibles" indépendamment du stage actif sur le display. Trois portées : `stage`, `desktop`, `all`. Default `stage`.

**Why this priority**: Complète logiquement les rules existantes (SPEC-016) et débloque des cas d'usage clés (Slack visible partout, lecteur musique sur tous les stages). Effort modéré (~80 LOC) car PinEngine existe déjà.

**Independent Test**: Configurer `[[rules]] match.bundle_id = "com.tinyspeck.slackmacgap" sticky_scope = "stage"`. Lancer Slack → vérifier qu'il apparaît dans le memberWindows de chaque stage du desktop courant sur son display. Switcher entre stages → Slack reste visible. Switcher de desktop → Slack disparaît (scope=stage, pas desktop).

**Acceptance Scenarios**:

1. **Given** une rule `sticky_scope = "stage"` sur Slack, **When** Slack est créé sur stage 1, **Then** Slack apparaît visible sur stage 1, 2, 3 du même desktop+display, mais pas sur les autres desktops.
2. **Given** `sticky_scope = "desktop"`, **When** l'utilisateur switche de desktop sur le même display, **Then** Slack reste visible sur le nouveau desktop.
3. **Given** `sticky_scope = "all"`, **When** l'utilisateur change de display, **Then** Slack est dupliqué visuellement (ou sur le display actif via re-positionnement) sur le nouveau display courant.
4. **Given** absence de `sticky_scope` dans la rule, **When** la rule s'applique, **Then** la fenêtre se comporte normalement (rattachée à un seul stage).

---

### User Story 5 — Follow focus bidirectionnel (Priority: P3)

L'utilisateur expérimenté veut activer le focus suivant la souris (`focus_follows_mouse`) et/ou le curseur sautant sur la fenêtre focalisée par raccourci (`mouse_follows_focus`). Default OFF pour les deux : opt-in obligatoire car comportements UX disruptifs si activés sans intention.

**Why this priority**: Demande utilisateur explicite, parité Linux WMs. Effort modéré (~150 LOC pour les deux). Priorité 3 car non vital pour utilisateur novice et risque de feedback loop si mal implémenté.

**Independent Test**:
- `focus_follows_mouse = true` : déplacer la souris au-dessus d'une fenêtre non-focused (sans cliquer) → après 100ms, le focus AX bascule sur cette fenêtre.
- `mouse_follows_focus = true` : exécuter `cmd+L` (focus right) → le curseur saute au centre de la nouvelle fenêtre focalisée.
- Les deux activés simultanément : aucun feedback loop infini (le mouse_follows_focus ne déclenche pas le focus_follows_mouse).

**Acceptance Scenarios**:

1. **Given** `focus_follows_mouse = false`, **When** la souris survole une fenêtre, **Then** le focus reste inchangé (comportement courant).
2. **Given** `focus_follows_mouse = true`, **When** la souris survole une fenêtre B alors que A est focused, **Then** après 100ms de stabilité, B reçoit le focus.
3. **Given** `mouse_follows_focus = true`, **When** un raccourci HJKL change le focus, **Then** le curseur est warpé au centre de la nouvelle fenêtre focalisée.
4. **Given** les deux activés, **When** un raccourci change le focus (donc warp curseur), **Then** ce warp ne re-déclenche pas un focus_follows_mouse en cascade.

---

### User Story 6 — Signal hooks (Priority: P3)

L'utilisateur power-user veut exécuter une commande shell quand un événement WM survient (focus change, fenêtre créée, stage changé, etc.). Pattern yabai/Hyprland. Définition par-rule dans le TOML, exécution async fire-and-forget.

**Why this priority**: Permet l'extensibilité utilisateur sans recompiler (notifications, sons, scripts custom). Effort modéré (~150 LOC). Priorité 3 car niche (power-users uniquement).

**Independent Test**: Configurer `[[signals]] event = "window_focused" cmd = "afplay /System/Library/Sounds/Tink.aiff"`. Changer le focus de fenêtre via raccourci → entendre le son Tink à chaque changement.

**Acceptance Scenarios**:

1. **Given** aucune section `[[signals]]`, **When** un événement survient, **Then** rien ne s'exécute (no-op).
2. **Given** un signal défini sur `window_focused`, **When** le focus change, **Then** la commande shell est lancée avec les variables d'env `ROADIE_WID`, `ROADIE_BUNDLE_ID`, etc. injectées.
3. **Given** un signal dont la commande met >5s, **When** elle est lancée, **Then** elle est tuée par timeout, log warn, et le daemon n'est pas bloqué.
4. **Given** `[signals] enabled = false`, **When** un événement survient, **Then** aucune commande n'est exécutée même si des `[[signals]]` sont définis.

---

### Edge Cases

- **Tree vide** (commande `balance`/`rotate`/`mirror` sur un stage sans fenêtre tilée) : no-op silencieux, pas d'erreur.
- **Tree d'un seul leaf** (1 fenêtre) : `balance`/`rotate`/`mirror` sont no-op (rien à équilibrer/tourner). `smart_gaps_solo` actif → frame = visibleFrame.
- **Scratchpad lancé mais fenêtre ne s'ouvre jamais** (cmd échoue ou app a un splash long) : log error après timeout 5s, prochaine bascule retentera le lancement.
- **Scratchpad toggled pendant que la fenêtre est en train d'animer** : ignorer si une animation est en cours sur cette wid (utiliser le flag `lastUserResizeByWid` ou similaire pour éviter les race conditions).
- **Sticky scope=all avec multi-display** : la fenêtre doit apparaître sur le display courant uniquement (pas duplication réelle, juste suivi du display actif). Documenté comme "follow active display".
- **focus_follows_mouse activé pendant un drag souris** : le drag prend le pas (pas de focus change pendant un drag actif). Réutiliser le flag `MouseDragHandler.isDragging`.
- **mouse_follows_focus déclenché par un focus issu d'un click** : le warp est skippé (la souris est déjà sur la fenêtre, inutile).
- **mouse_follows_focus + focus_follows_mouse activés simultanément** : le warp pose un flag transitoire 200ms qui inhibe le focus_follows_mouse (anti-feedback loop).
- **Signal cmd avec injection shell malveillante** (`; rm -rf /`) : la commande est exécutée telle qu'écrite dans le TOML, c'est la responsabilité de l'utilisateur. Documenter le risque de sécurité dans la doc.
- **Signal lancé en boucle infinie** (script qui ne termine jamais) : timeout 5s strict, kill SIGTERM puis SIGKILL si nécessaire.

## Requirements

### Functional Requirements

#### Tree commands (US1)
- **FR-001**: Le système DOIT exposer la commande `roadie tiling balance` qui réinitialise tous les `adaptiveWeight` des leaves du tree courant (current stage + display) à 1.0.
- **FR-002**: Le système DOIT exposer la commande `roadie tiling rotate <angle>` où `<angle>` ∈ {90, 180, 270}, qui transforme récursivement le tree :
  - 90° : inverse l'orientation (H↔V) à chaque container, sans changer l'ordre des children.
  - 180° : inverse l'ordre des children à chaque container, sans changer l'orientation.
  - 270° : combine 90° + 180°.
- **FR-003**: Le système DOIT exposer la commande `roadie tiling mirror <axis>` où `<axis>` ∈ {x, y}, qui inverse l'ordre des children pour tous les containers de l'orientation correspondante (x → containers H, y → containers V).
- **FR-004**: Les commandes balance/rotate/mirror DOIVENT déclencher un `applyLayout()` immédiat après mutation du tree.
- **FR-005**: Les commandes balance/rotate/mirror DOIVENT être idempotentes-friendly : invoquées sur un tree vide ou single-leaf, elles sont no-op silencieux (pas d'erreur, pas de log warn).

#### Smart gaps solo (US2)
- **FR-006**: Le système DOIT lire la clé `[tiling] smart_gaps_solo` (boolean, default `false`) du TOML.
- **FR-007**: Quand `smart_gaps_solo = true`, le système DOIT, au moment du calcul de layout par display, vérifier le nombre de leaves tiled visibles sur ce display ; si `count == 1`, les gaps `outer` et `inner` DOIVENT être forcés à 0 pour ce display uniquement.
- **FR-008**: Le comportement par-display DOIT être indépendant : un display avec 1 fenêtre voit gaps=0, un autre display avec 3 fenêtres voit gaps configurés normalement, sur le même applyAll.

#### Scratchpad (US3)
- **FR-009**: Le système DOIT lire la section `[[scratchpads]]` du TOML, chaque entrée comportant `name` (string unique) et `cmd` (string, commande shell de lancement).
- **FR-010**: Le système DOIT exposer la commande `roadie scratchpad toggle <name>` qui :
  - Si scratchpad pas encore lancé : exécute `cmd` async, attache la première fenêtre matchant l'app produite.
  - Si scratchpad lancé et visible : cache la fenêtre offscreen (HideStrategy.corner ou opacity).
  - Si scratchpad lancé et caché : restore la fenêtre à sa dernière position visible.
- **FR-011**: Une fenêtre marquée scratchpad DOIT être sticky cross-stage par défaut sur son display (visible quel que soit le stage actif).
- **FR-012**: Si la commande `cmd` ne produit aucune fenêtre détectable dans les 5s suivant son lancement, le système DOIT log warn et marquer le scratchpad comme "non lancé" pour permettre une nouvelle tentative.

#### Sticky cross-stage (US4)
- **FR-013**: Le système DOIT supporter dans `[[rules]]` un nouveau champ `sticky_scope` (enum: `"stage"`, `"desktop"`, `"all"`), default `"stage"` quand non spécifié dans une rule sticky.
- **FR-014**: Une fenêtre matchée par une rule avec `sticky_scope = "stage"` DOIT apparaître dans `memberWindows` de toutes les stages partageant le même `(displayUUID, desktopID)`.
- **FR-015**: Une fenêtre `sticky_scope = "desktop"` DOIT être visible sur tous les desktops d'un même display, et donc rester visible lors d'un switch de desktop sur ce display.
- **FR-016**: Une fenêtre `sticky_scope = "all"` DOIT être déplacée vers le display actif courant lors d'un changement de display, restant visible peu importe le scope (display, desktop, stage).
- **FR-017**: La sémantique sticky DOIT respecter les hide/show existants : pas de double affichage, pas de drift dans `widToScope`.

#### Follow focus bidirectionnel (US5)
- **FR-018**: Le système DOIT lire `[focus] focus_follows_mouse` (boolean, default `false`).
- **FR-019**: Quand `focus_follows_mouse = true`, le système DOIT installer un monitor `NSEvent` sur `mouseMoved`, throttlé à 100ms, qui détecte la fenêtre sous le curseur et la focalise via `FocusManager.setFocus(_:)`.
- **FR-020**: Le focus_follows_mouse DOIT être inhibé pendant un drag souris actif (`MouseDragHandler.isDragging == true`).
- **FR-021**: Le système DOIT lire `[focus] mouse_follows_focus` (boolean, default `false`).
- **FR-022**: Quand `mouse_follows_focus = true`, chaque appel à `FocusManager.setFocus(_:)` issu d'un raccourci clavier (HJKL focus, alt+N stage switch, warp/move) DOIT déclencher un `CGWarpMouseCursorPosition` au centre de la nouvelle fenêtre focalisée.
- **FR-023**: Le warp curseur du mouse_follows_focus DOIT poser un flag transitoire de 200ms qui inhibe le focus_follows_mouse, prévenant un feedback loop.
- **FR-024**: Le mouse_follows_focus ne DOIT PAS se déclencher pour les changements de focus issus d'un click souris (pour éviter des warp inutiles).

#### Signal hooks (US6)
- **FR-025**: Le système DOIT lire `[signals] enabled` (boolean, default `true`) et la liste `[[signals]]` du TOML.
- **FR-026**: Chaque entrée `[[signals]]` DOIT comporter `event` (enum string) et `cmd` (string shell).
- **FR-027**: Les events supportés DOIVENT être : `window_focused`, `window_created`, `window_destroyed`, `stage_changed`, `desktop_changed`, `display_changed`.
- **FR-028**: Le système DOIT exécuter chaque signal correspondant async via `Process`, non-bloquant pour l'EventBus.
- **FR-029**: Le système DOIT injecter dans l'environnement de la commande shell les variables `ROADIE_EVENT`, `ROADIE_WID`, `ROADIE_BUNDLE_ID`, `ROADIE_STAGE`, `ROADIE_DESKTOP`, `ROADIE_DISPLAY` (selon disponibilité).
- **FR-030**: Chaque signal DOIT avoir un timeout strict de 5s ; au-delà le process est tué (SIGTERM puis SIGKILL).
- **FR-031**: Quand `[signals] enabled = false`, AUCUN signal ne DOIT être lancé même si des `[[signals]]` sont définis.

### Key Entities

- **ScratchpadDef**: nom unique, commande de lancement, état "lancé/caché", wid attachée, dernière position visible.
- **StickyRule** (extension de Rule existante) : champ `sticky_scope` ajouté, valeurs `stage`/`desktop`/`all`.
- **SignalDef**: event name, command string. Pas de state runtime au-delà du compteur de timeouts pour observabilité.
- **TreeOp** (concept implicite, pas une struct) : opérations pures sur l'arbre BSP — balance (mutation in-place de adaptiveWeight), rotate (mutation orientation + children), mirror (reverse children).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% des 9 features livrées avec tests unitaires verts (≥1 test par feature critique : balance/rotate/mirror logic, smart_gaps detection, sticky scope matching, signal env injection, anti-feedback loop).
- **SC-002**: Plafond LOC strict total cumulé ≤900 lignes effectives (hors tests, hors commentaires) ; cible 700.
- **SC-003**: 0 régression sur les 13 fixes structurels antérieurs (vérifiée via `roadie-monitor` invariants à 0 sur 24h post-merge).
- **SC-004**: Latence p95 `applyAll` reste <250ms après activation simultanée de smart_gaps + sticky + 2 follow-focus + 3 signal hooks.
- **SC-005**: Aucun feedback loop détectable sur 5 minutes d'activité avec `focus_follows_mouse=true` ET `mouse_follows_focus=true` activés (mesure : ratio focus_change_5m vs baseline doit rester <2x).
- **SC-006**: 100% des 9 toggles configurables fonctionnent correctement en activation/désactivation à chaud via `roadie daemon reload`.
- **SC-007**: Constitution gate G respectée : `find Sources/ -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` après merge reste ≤ plafond + 900.

## Assumptions

- Les hooks `LayoutHooks.applyLayout` et `LayoutEngine.tiler.protocol.{balance,rotate,mirror}` peuvent être étendus dans `BSPTiler` et `MasterStackTiler` ; pour MasterStack, certaines opérations (rotate/mirror) sont no-op ou se traduisent en swap master/stack quand applicable.
- `MouseDragHandler.isDragging` est déjà exposé et peut être lu par le focus_follows_mouse watcher.
- `EventBus.shared.subscribe(_:)` accepte des handlers async et ne bloque pas le main thread sur des Process spawn.
- `WindowRegistry.allWindows` retourne les fenêtres avec leurs frames à jour pour la détection scratchpad cmd→wid.
- La commande `cmd` du scratchpad est un script shell standard, l'utilisateur prend la responsabilité de la sécurité (pas de sandbox).
- Le `sticky_scope = "all"` n'implique pas de cloning visuel cross-display (impossible sans osax) mais un déplacement vers le display actif courant.
