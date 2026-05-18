# Feature Specification: Roadie Target Mode

<!-- SPEC-FORMALISM:START -->
## Fiche Synthèse

Spec: 009-roadie-target-mode
Titre: Roadie Target Mode
Statut: Implemented
Priorité: P1
Tâches: 68/68 (100%)
Tests: 364/364 (100%)

Résumé:
- Contexte: Vimac et Homerow montrent qu'un bureau macOS peut devenir navigable par labels, recherche et inspection plutôt que par coordonnées souris.
- Objectif: Donner à Roadie une couche de cibles actionnables pour humains et agents, couvrant les objets Roadie, un picker clavier, une base overlay, des actions enrichies et les zones sensibles applicatives exposées par Accessibility.
- Dépendances: SPEC-002, SPEC-003, SPEC-004, SPEC-005, SPEC-008

Fichiers:
- spec.md: ✓
- tasks.md: ✓
- plan.md: ✓
<!-- SPEC-FORMALISM:END -->

**Feature Branch**: `009-roadie-target-mode`
**Created**: 2026-05-17
**Status**: Implemented
**Priority**: P1
**Dependencies**: SPEC-002, SPEC-003, SPEC-004, SPEC-005, SPEC-008
**Input**: User description: "Récupérer les concepts de Vimac, Homerow et Neru sans copier le code : hints, recherche, labels, inspecteur, cibles Roadie, zones sensibles applicatives, grille récursive, record/replay et interface exploitable par agents."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Lister et inspecter les cibles Roadie (Priority: P1)

Un utilisateur ou un agent peut demander à Roadie la liste structurée des cibles disponibles : stages visibles, fenêtres, displays, desktops et bookmarks. Chaque cible possède un label court, un type, un état, une action par défaut et un diagnostic lisible.

**Why this priority**: Cette surface est le socle commun des usages humains et agents. Elle apporte de la valeur sans manipuler le layout ni dépendre d'un overlay visuel.

**Independent Test**: Exécuter une commande de liste et une commande d'inspection sur un état simulé doit retourner des cibles déterministes et un diagnostic exploitable sans capture écran.

**Acceptance Scenarios**:

1. **Given** plusieurs stages et fenêtres connus de Roadie, **When** l'utilisateur liste les cibles, **Then** Roadie retourne des labels courts uniques et des métadonnées par cible.
2. **Given** une fenêtre exclue du tiling ou pinée, **When** l'utilisateur inspecte sa cible, **Then** Roadie explique son app, titre, rôle, scope, pin, stage, display et raison d'inclusion ou d'exclusion.
3. **Given** un agent ne dispose pas de capture écran, **When** il demande les cibles en JSON, **Then** il peut identifier une fenêtre ou une stage par texte, label, type et scope.

---

### User Story 2 - Activer une cible Roadie par label ou recherche (Priority: P1)

Un utilisateur peut taper un label ou une requête textuelle pour focaliser une fenêtre, changer de stage, changer de display ou envoyer la fenêtre active vers une cible.

**Why this priority**: C'est le gain quotidien direct inspiré de Homerow : moins de clic précis, moins d'ambiguïté avec les IDs, moins de dépendance à AltTab.

**Independent Test**: Sur un snapshot simulé, une action `focus` ou `send-active` vers une cible doit résoudre la bonne cible et appeler le service Roadie approprié.

**Acceptance Scenarios**:

1. **Given** une stage nommée "Work" visible dans le navrail, **When** l'utilisateur active le label associé, **Then** Roadie bascule vers cette stage.
2. **Given** une fenêtre active et une stage cible visible, **When** l'utilisateur lance l'action d'envoi vers cette cible, **Then** Roadie assigne la fenêtre active à cette stage sans suivre le focus si la configuration le demande.
3. **Given** plusieurs cibles dont le nom contient "gray", **When** l'utilisateur recherche "gray", **Then** Roadie retourne uniquement les cibles pertinentes avec labels conservés.

---

### User Story 3 - Exposer des zones sensibles applicatives (Priority: P2)

Quand l'utilisateur active le mode applicatif expérimental, Roadie peut lister les éléments actionnables de la fenêtre active : boutons, liens, champs, lignes, zones scrollables ou menus exposés par Accessibility.

**Why this priority**: C'est le bénéfice Vimac/Homerow au-delà du window manager. Il doit rester séparé du moteur de layout pour éviter qu'une app mal exposée ne perturbe les stages.

**Independent Test**: Sur un arbre AX simulé, Roadie doit filtrer les éléments actionnables, limiter le volume, produire des labels et marquer les erreurs ou timeouts sans casser les cibles Roadie.

**Acceptance Scenarios**:

1. **Given** une fenêtre active avec boutons et liens AX, **When** l'utilisateur liste les cibles applicatives, **Then** Roadie retourne les éléments actionnables visibles avec rôle, titre et frame.
2. **Given** une app Electron ou Firefox lente à répondre, **When** l'interrogation dépasse le budget configuré, **Then** Roadie retourne un résultat partiel ou une erreur contrôlée sans relayout.
3. **Given** les cibles applicatives sont désactivées, **When** l'utilisateur liste les cibles, **Then** Roadie ne parcourt pas l'arbre AX profond.

---

### User Story 4 - Préparer l'overlay de hints Roadie (Priority: P2)

Une couche runtime expose les labels à afficher et les commandes d'activation/masquage nécessaires pour brancher ensuite un overlay graphique sans dupliquer le moteur de cibles.

**Why this priority**: L'overlay concrétise l'expérience Vimac/Homerow pour les objets Roadie, mais la valeur d'automatisation existe déjà via CLI/JSON. La première livraison doit donc contracter le runtime sans toucher au navrail.

**Independent Test**: Les commandes `targets show` et `targets hide` retournent un état cohérent sans modifier le layout, et `targets show` réutilise exactement le même inventaire que `targets list`.

**Acceptance Scenarios**:

1. **Given** des stages visibles dans le navrail, **When** `targets show` est appelé, **Then** Roadie retourne les labels des cibles visibles et ignore les stages vides masquées.
2. **Given** l'overlay graphique n'est pas encore branché, **When** `targets hide` est appelé, **Then** Roadie répond proprement sans action de layout.
3. **Given** une implémentation graphique future, **When** elle consomme les cibles, **Then** elle utilise les IDs et labels de `targets list` au lieu de recalculer ses propres labels.

---

### User Story 5 - Fournir un inspecteur orienté debug et agent (Priority: P1)

Un utilisateur ou un agent peut demander "pourquoi Roadie considère cette fenêtre/stage ainsi ?" et obtenir une réponse structurée avec raisons, règles et derniers événements.

**Why this priority**: Les derniers bugs Roadie ont montré que la compréhension des décisions internes est aussi importante que l'action elle-même.

**Independent Test**: Sur des fenêtres pinées, flottantes, exclues ou assignées par règle, l'inspecteur doit fournir des raisons lisibles et les mêmes champs en JSON.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée, **When** elle est inspectée, **Then** Roadie indique son pin scope, si elle est float, son scope effectif et la règle ou action manuelle associée.
2. **Given** une fenêtre non tileable, **When** elle est inspectée, **Then** Roadie indique la raison probable : subrole, mobilier, modalité, taille ou absence de scope.
3. **Given** une stage, **When** elle est inspectée, **Then** Roadie indique son ordre visible, son ID, son nom, son display, son desktop, ses fenêtres et son mode.

---

### User Story 6 - Picker clavier par recherche (Priority: P1)

Un utilisateur peut taper une requête courte, obtenir les cibles candidates, puis activer directement la cible unique sans mémoriser les IDs techniques.

**Why this priority**: C'est le morceau Homerow le plus rentable après le listing : il accélère le quotidien sans dépendre d'un overlay graphique.

**Independent Test**: Sur une liste de cibles simulées, `pick` doit sélectionner une cible unique, refuser une ambiguïté et produire un JSON exploitable.

**Acceptance Scenarios**:

1. **Given** une seule cible contenant "gray", **When** l'utilisateur lance `targets pick gray`, **Then** Roadie active cette cible avec l'action par défaut.
2. **Given** plusieurs cibles contenant "term", **When** l'utilisateur lance `targets pick term`, **Then** Roadie retourne les candidates et signale l'ambiguïté sans changer le layout.
3. **Given** une cible stale, **When** l'utilisateur tente de la picker, **Then** l'erreur reste structurée et traçable.

---

### User Story 7 - Actions enrichies sur cibles (Priority: P2)

Un utilisateur peut déclencher des actions plus riches que le focus simple : click, double-click, right-click pour app targets, focus bookmark, et préparation des actions pin/bookmark/move.

**Why this priority**: Ces actions transforment la liste de cibles en vraie surface de contrôle, tout en restant bornées par type de cible.

**Independent Test**: Les actions non supportées doivent être refusées proprement, les app targets doivent router vers le provider d'événements souris et les bookmarks doivent utiliser le service existant.

**Acceptance Scenarios**:

1. **Given** une cible bookmark live, **When** l'utilisateur active son focus, **Then** Roadie rejoint la fenêtre bookmarkée.
2. **Given** une cible app button, **When** l'utilisateur demande `double-click`, **Then** Roadie envoie deux clics au centre de son frame.
3. **Given** une cible stage, **When** l'utilisateur demande `right-click`, **Then** Roadie refuse `unsupported_action`.

---

### User Story 8 - Mode labels-only et intégration raccourcis (Priority: P2)

Roadie expose un état `show/hide` suffisamment structuré pour que BTT, Karabiner ou un overlay Roadie puissent afficher seulement les labels et activer par label.

**Why this priority**: Cela permet de brancher les raccourcis sans forcer immédiatement une nouvelle fenêtre overlay dans le chemin critique.

**Independent Test**: `targets show --json` doit retourner un état d'overlay avec les mêmes labels que `targets list`, et `targets hide` doit être idempotent.

**Acceptance Scenarios**:

1. **Given** un raccourci BTT, **When** il lance `targets show --json`, **Then** il reçoit labels, IDs, frames et actions.
2. **Given** l'utilisateur tape un label, **When** le raccourci lance `targets activate LABEL`, **Then** l'action correspondante s'applique.
3. **Given** l'overlay n'est pas affiché, **When** `targets hide` est appelé, **Then** Roadie répond sans erreur.

---

### User Story 9 - Inspecteur renforcé pour agents (Priority: P2)

Un agent ou un utilisateur peut obtenir les raisons d'action possibles, les diagnostics de stale target et le contexte Roadie sans capture écran.

**Why this priority**: Les agents doivent agir par état structuré et non par coordonnées visuelles fragiles.

**Independent Test**: L'inspection JSON d'une cible doit rester stable et inclure les actions supportées.

**Acceptance Scenarios**:

1. **Given** une cible avec plusieurs actions, **When** elle est inspectée, **Then** le JSON expose les actions disponibles.
2. **Given** une cible ambiguë, **When** l'agent tente une résolution, **Then** les candidates sont retournées sans mutation.
3. **Given** une app target partielle, **When** elle est inspectée, **Then** le diagnostic indique la source et les limites.

---

### User Story 10 - Navigation applicative future bornée (Priority: P3)

Roadie prépare les extensions de navigation type scroll-mode et labels applicatifs complets, mais uniquement derrière la configuration expérimentale.

**Why this priority**: La valeur existe, mais le risque de lenteur AX et de comportements divergents par application impose un périmètre expérimental.

**Independent Test**: Les options expérimentales doivent rester désactivées par défaut et ne jamais relayout une fenêtre.

**Acceptance Scenarios**:

1. **Given** les app targets désactivés, **When** `targets list` est appelé, **Then** Roadie ne parcourt pas l'arbre AX.
2. **Given** l'utilisateur active les app targets, **When** une app dépasse le timeout, **Then** Roadie retourne un résultat partiel sans changer de stage.
3. **Given** une future commande de scroll, **When** elle n'est pas disponible, **Then** Roadie la documente comme non livrée au lieu d'exposer un comportement incomplet.

---

### User Story 11 - Grille récursive multi-écran (Priority: P1)

Un utilisateur ou un agent peut afficher une grille sur l'écran actif, subdiviser récursivement la zone par chemin de labels et cibler une cellule sans capture écran.

**Why this priority**: C'est le complément Neru/Vimac qui couvre les zones non exposées par AX et donne aux agents un vocabulaire spatial stable.

**Independent Test**: Sur un display simulé, Roadie doit produire des cellules déterministes, résoudre un chemin imbriqué et calculer le chemin d'un point.

**Acceptance Scenarios**:

1. **Given** un écran 900x900 et une grille 3x3, **When** Roadie génère les cellules, **Then** les 9 cellules ont des labels et frames déterministes.
2. **Given** le chemin `AA`, **When** Roadie le résout, **Then** il pointe vers le premier neuvième de la première cellule.
3. **Given** l'utilisateur demande l'overlay visuel de grille, **When** la config l'autorise, **Then** Roadie affiche les mêmes labels que le rapport JSON.

---

### User Story 12 - Actions souris sur grille (Priority: P1)

Un utilisateur ou un agent peut déclencher click, double-click, right-click, move, scroll et drag entre deux cellules.

**Why this priority**: La grille n'est utile que si elle devient actionnable et pas seulement descriptive.

**Independent Test**: Les commandes refusent les chemins invalides et produisent un résultat structuré sans muter le layout Roadie.

**Acceptance Scenarios**:

1. **Given** une cellule valide, **When** l'utilisateur lance `roadie grid click A`, **Then** Roadie poste un clic au centre de la cellule.
2. **Given** deux cellules valides, **When** l'utilisateur lance `roadie grid drag A L`, **Then** Roadie poste une séquence drag de centre à centre.
3. **Given** la grille désactivée, **When** une action est demandée, **Then** Roadie retourne `target_grid_disabled`.

---

### User Story 13 - Record enrichi par cibles AX/Roadie (Priority: P1)

Un utilisateur peut enregistrer une courte manipulation. Chaque événement garde les coordonnées, mais aussi la cible Roadie/AX la plus spécifique et un chemin de grille de secours quand possible.

**Why this priority**: C'est la brique qui permet de montrer une manipulation à un agent sans dépendre uniquement d'une vidéo ou de screenshots.

**Independent Test**: Le modèle de recording doit round-tripper en JSON et l'association au plus petit frame contenant le clic doit être déterministe.

**Acceptance Scenarios**:

1. **Given** un clic sur un bouton AX, **When** Roadie enregistre, **Then** l'événement contient le target appElement si l'AX context est activé.
2. **Given** un clic dans une zone sans target AX, **When** Roadie enregistre, **Then** l'événement contient au minimum les coordonnées et le chemin de grille si possible.
3. **Given** `record_text_input=false`, **When** l'utilisateur tape du texte, **Then** Roadie conserve les key codes sans enregistrer le texte saisi.

---

### User Story 14 - Replay robuste et agent-friendly (Priority: P2)

Un utilisateur ou agent peut rejouer une macro : Roadie tente la cible stable lorsque possible puis retombe sur la position enregistrée.

**Why this priority**: Le replay utile doit survivre aux petites variations de layout ou d'application.

**Independent Test**: Le replay refuse explicitement si la config est désactivée et lit les enregistrements depuis le répertoire configuré.

**Acceptance Scenarios**:

1. **Given** une macro existante et `replay_enabled=true`, **When** l'utilisateur lance `roadie record replay NAME`, **Then** Roadie rejoue les événements dans l'ordre temporel.
2. **Given** une cible appElement encore disponible, **When** un mouse-up enregistré la référence, **Then** Roadie tente l'action click via Target Mode.
3. **Given** la cible n'est plus disponible, **When** le replay continue, **Then** Roadie utilise la position enregistrée au lieu d'échouer toute la macro.

---

### User Story 15 - AX boost Firefox/Electron/navigateurs (Priority: P2)

Quand l'utilisateur active le boost AX, Roadie explore aussi les attributs visibles, navigation order, rows, columns, contents et tabs, avec déduplication, profondeur et timeout.

**Why this priority**: Les applications Electron/Firefox exposent souvent des arbres AX non standards ; sans boost, les labels applicatifs restent trop pauvres.

**Independent Test**: La config doit décoder `ax_boost_enabled`, `max_depth` et les bundles additionnels, et la découverte reste bornée.

**Acceptance Scenarios**:

1. **Given** `ax_boost_enabled=true`, **When** Roadie scanne une app, **Then** il parcourt plus que `AXChildren` tout en respectant `max_depth`.
2. **Given** une app trop lente, **When** le timeout est atteint, **Then** Roadie retourne un rapport partiel sans relayout.
3. **Given** un bundle ID listé dans `additional_boost_bundle_ids`, **When** cette app est frontmost, **Then** Roadie active aussi le boost pour elle.

---

### Edge Cases

- Si deux cibles ont le même nom ou la même app, les labels restent uniques et les IDs restent disponibles.
- Si une cible disparaît entre liste et activation, l'action échoue proprement avec `stale_target`.
- Si Accessibility n'est pas autorisé, les cibles Roadie restent disponibles et les cibles applicatives indiquent `accessibility_denied`.
- Si une app expose plus d'éléments que la limite configurée, Roadie tronque et indique `truncated=true`.
- Si une requête ne matche rien, Roadie retourne une liste vide et un message non ambigu.
- Si la grille est désactivée, aucune action souris de grille n'est postée.
- Si le record dépasse le nombre maximal d'événements, Roadie tronque l'enregistrement sans planter le daemon.
- Si le replay ne peut pas retrouver une cible AX, il retombe sur les coordonnées enregistrées.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST expose a target listing command returning Roadie-owned targets: stages, windows, displays, desktops and bookmarks.
- **FR-002**: Roadie MUST assign deterministic short labels to targets using a configurable alphabet and stable ordering.
- **FR-003**: Roadie MUST support text filtering where case, accents and repeated spaces do not prevent a match.
- **FR-004**: Roadie MUST expose target inspection for windows, stages, displays and app targets with human-readable and JSON output.
- **FR-005**: Roadie MUST support target activation actions for Roadie targets: focus window, switch stage, focus display and send active window to stage.
- **FR-006**: Roadie MUST keep app-target discovery isolated from layout maintenance so app AX failures cannot trigger stage or layout changes.
- **FR-007**: Roadie MUST keep app-target discovery disabled by default unless the user enables the experimental capability.
- **FR-008**: Roadie MUST limit app-target discovery by scope, count and time budget.
- **FR-009**: Roadie MUST emit structured events for target listing, inspection and activation failures.
- **FR-010**: Roadie MUST provide JSON contracts suitable for agents without requiring screenshots.
- **FR-011**: Roadie SHOULD provide an overlay-driven hint mode for Roadie targets built on the same target model.
- **FR-012**: Roadie SHOULD allow app targets to include role, title, value summary, frame, action kind and source window.
- **FR-013**: Roadie MUST never copy or depend on GPL source from Vimac; only concepts and independently implemented behavior are allowed.
- **FR-014**: Roadie MUST expose a `pick` flow that resolves a text query or label and either activates a unique target or returns candidates without mutation.
- **FR-015**: Roadie MUST support bookmark focus through the target activation path.
- **FR-016**: Roadie SHOULD support double-click and right-click app target actions when the target frame is known.
- **FR-017**: Roadie MUST expose `show/hide` overlay state in JSON without requiring the visual overlay to be running.
- **FR-018**: Roadie MUST keep labels-only and visual overlay integration decoupled from stage switch, focus and border refresh.
- **FR-019**: Roadie SHOULD document BTT/Karabiner integration points without making them required runtime dependencies.
- **FR-020**: Roadie MUST mark unimplemented Vimac/Homerow-like capabilities as future or experimental rather than silently pretending they exist.
- **FR-021**: Roadie MUST make Target Mode capabilities independently configurable: core target mode, picker, overlay, app target discovery, app mouse actions and future scroll mode.
- **FR-022**: Roadie MUST keep risky app-level mouse actions disabled by default even when app target discovery is enabled.
- **FR-023**: Roadie MUST provide a configurable recursive grid with rows, columns, max depth, alphabet, scope and overlay flag.
- **FR-024**: Roadie MUST expose grid cells as structured JSON with path, label, display, scope, root frame, frame and center.
- **FR-025**: Roadie MUST support grid actions: click, double-click, right-click, move, scroll-up, scroll-down and drag.
- **FR-026**: Roadie MUST keep grid actions isolated from tiling and stage maintenance.
- **FR-027**: Roadie MUST provide macro recording behind experimental configuration.
- **FR-028**: Roadie MUST enrich recorded click events with nearest Roadie/AX target and grid fallback when configured.
- **FR-029**: Roadie MUST avoid recording text input by default while preserving key codes for replay.
- **FR-030**: Roadie MUST provide macro replay behind explicit experimental configuration.
- **FR-031**: Roadie MUST try target-based replay before coordinate fallback when target context is available.
- **FR-032**: Roadie MUST support AX boost traversal with additional child attributes, deduplication, timeout and max depth.
- **FR-033**: Roadie MUST make grid, record, replay and AX boost independently configurable.
- **FR-034**: Roadie MUST support both full-display and focused-window recursive grid scopes so users can bind them to different shortcuts.
- **FR-035**: Roadie MUST document that Vimac/Homerow/Neru concepts are reimplemented independently without copying source.

### Key Entities *(include if feature involves data)*

- **Target**: Actionable object known to Roadie or Accessibility. Attributes include ID, label, type, title, subtitle, scope, frame, confidence, source and supported actions.
- **TargetQuery**: User or agent query describing source, filter text, max results and inclusion of app targets.
- **TargetAction**: Operation requested against a target, such as focus, switch, send-active, inspect or click.
- **TargetInspection**: Structured explanation of a target's identity, state, rules, eligibility and recent events.
- **AppTarget**: Accessibility-derived UI element within the frontmost window, isolated from layout operations.
- **TargetPickResult**: Result of resolving a label or query, including candidates, selected target, action result and ambiguity/stale errors.
- **TargetOverlayState**: Runtime description of visible labels, mode and source report consumed by future overlays or shortcut tools.
- **TargetGridCell**: Spatial cell on a display with path, label, frame, center and display metadata.
- **TargetMacroRecording**: JSON recording containing timed events, target context and grid fallback.
- **TargetMacroEvent**: Mouse, key or scroll event with timestamp and optional AX/Roadie target.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A CLI call can list Roadie targets in JSON in under 100 ms p95 on a snapshot with 50 windows and 20 stages.
- **SC-002**: A user or agent can resolve a visible stage or window by label or text query with no dependency on stage IDs.
- **SC-003**: Inspecting a window returns at least app, title, window ID, display, desktop, stage, tileability, pin state and diagnostic reasons.
- **SC-004**: App-target discovery failure never changes a window frame, stage assignment or active stage.
- **SC-005**: Tests cover label generation, filtering, Roadie target listing, inspection and stale-target handling.
- **SC-006**: Documentation explains the distinction between Roadie targets and experimental app targets.
- **SC-007**: A unique `targets pick` query activates the target, while an ambiguous query returns candidates and does not mutate Roadie.
- **SC-008**: `targets show --json` exposes an overlay state derived from the same target inventory as `targets list`.
- **SC-009**: Bookmark targets can be focused through `targets activate` without a separate bookmark command.
- **SC-010**: Disabling Target Mode, picker or app mouse actions in TOML produces explicit structured errors and no mutation.
- **SC-011**: A grid report over a simulated 3x3 display produces deterministic cells and nested paths.
- **SC-012**: Macro recordings round-trip as JSON and prefer the smallest containing target for click context.
- **SC-013**: `roadie grid show --json`, `roadie record list` and `roadie config validate` run successfully with the new config.

## Roadmap intégrée des 10 étapes

1. **Figer le socle Target Mode**: commit propre, tests, JSON stable, documentation.
2. **Overlay visuel de labels Roadie**: labels sur fenêtres, stages, displays et bookmarks, branchés sur `TargetOverlayState`.
3. **Raccourcis BTT/Karabiner**: scripts d'entrée qui appellent `targets show`, `targets pick` et `targets activate`.
4. **Picker/recherche à la Homerow**: résolution texte, candidates ambiguës, action unique.
5. **Activation fiable des app targets expérimentaux**: rôles AX bornés, timeouts, click/double-click/right-click.
6. **Mode labels-only**: labels tapables sans overlay lourd, adapté aux raccourcis.
7. **Actions enrichies sur cibles**: focus, switch, send-active, inspect, click, double-click, right-click, puis pin/bookmark/move dans une itération suivante.
8. **Scroll/navigation applicative type Vimac**: future phase expérimentale, seulement après stabilisation app targets.
9. **Inspecteur plus complet**: raisons d'action, stale targets, diagnostics agent.
10. **Mode agent propre**: contrats JSON stables pour décider sans screenshot, enrichis par grille et macro record/replay.

## Assumptions

- Roadie remains a window/stage manager first; full app control is experimental and isolated.
- BTT/Karabiner remain the recommended activation layer for hotkeys.
- The first implementation may expose the model via CLI/JSON before a polished visual overlay.
- App targets are queried only for the frontmost or focused window unless explicitly expanded later.
- The code must be independently written and must not copy GPL implementation from Vimac.
