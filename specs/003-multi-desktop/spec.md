# Feature Specification: Multi-desktop awareness (roadies V2) — DEPRECATED

**Feature Branch**: `003-multi-desktop`
**Created**: 2026-05-01
**Status**: **DEPRECATED 2026-05-02** — remplacée par [SPEC-011 Virtual Desktops](../011-virtual-desktops/spec.md).
**Dependencies**: SPEC-002-tiler-stage (V1 tiler + Stage Manager opérationnels)

> ⚠️ **Cette spec est abandonnée**. Le mécanisme de bascule via `CGSManagedDisplaySetCurrentSpace` (1 Roadie Desktop = 1 Mac Space natif) est cassé par une régression macOS Tahoe 26 documentée (yabai issue #2656) : le state interne change mais WindowServer ne rerender plus les fenêtres. Pivot vers le pattern AeroSpace dans [SPEC-011](../011-virtual-desktops/spec.md) — desktops virtuels gérés intégralement par roadie dans **un seul** Mac Space natif, sans aucun appel SkyLight pour la bascule.

**Input**: User description: "Multi-desktop awareness pour Roadie. Le daemon doit suivre le desktop macOS actif (Mission Control) et persister un état séparé par UUID de desktop : stages, tree BSP, layout per-desktop, gaps, assignments fenêtres-stage. Les stages V1 (raccourcis ⌥1/⌥2) sont préservés tels quels — un stage reste un groupe de fenêtres dans un même desktop, équivalent fonctionnel d'Apple Stage Manager. Le multi-desktop ajoute une dimension orthogonale. Détection du desktop courant via API SkyLight stable sans SIP désactivé. Pas de création/destruction/réordonnancement de desktops macOS. Nouvelles commandes CLI : roadie desktop list/focus/current/label, roadie events --follow. Compat ascendante stricte via multi_desktop.enabled = false par défaut. Multi-display reporté en V3."

---

## Vocabulaire (CRITIQUE — à respecter strictement)

- **Stage** = groupe de fenêtres sur **un même desktop macOS**, masquables ensemble (offscreen + setLeafVisible). C'est l'**équivalent Apple Stage Manager** déjà livré en V1. Switch via raccourcis ⌥1 / ⌥2 actuels. **Inchangé en V2**.
- **Desktop** (= "Space" macOS Mission Control) = bureau virtuel natif macOS, géré par le système. L'utilisateur navigue entre eux via Mission Control (Ctrl+→/←, gestures trackpad natifs, F3). **C'est ce qu'on rend conscient en V2**.
- Un **stage appartient à un desktop**. Sur chaque desktop, l'utilisateur peut avoir plusieurs stages indépendants.

Le nom du projet "Roadie" vient de l'analogie : un roadie prépare la scène (stage). Multi-desktop = "préparer plusieurs scènes pour plusieurs salles".

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Suivre automatiquement le desktop macOS courant (Priority: P1) 🎯 MVP V2

L'utilisateur travaille sur le **desktop 1** macOS avec ses applications de développement (terminal, éditeur). Il a configuré 2 stages roadie sur ce desktop (`⌥1` = "code" avec son terminal et son IDE, `⌥2` = "logs" avec un terminal de monitoring).

Il bascule sur le **desktop 2** via Ctrl+→ (Mission Control natif macOS) où il a Slack, Mail et son navigateur perso. Roadie détecte la transition en moins de 200 ms et **bascule automatiquement le contexte** : `roadie stage list` montre désormais les stages du desktop 2 (qui peuvent être totalement différents — par ex. 1 stage unique "comm" avec Slack+Mail, et 1 stage "browse" avec Firefox).

Quand l'utilisateur revient sur le desktop 1 (Ctrl+←), roadie retrouve **exactement** ses 2 stages "code" et "logs" tels qu'il les avait laissés, avec le même tree BSP, les mêmes assignations de fenêtres, le même stage actif au moment du départ.

**Why this priority** : c'est la fondation V2. Sans l'awareness desktop, les stages sont mélangés à travers tous les desktops macOS (comportement V1 actuel) ce qui rend l'expérience confuse dès qu'on utilise plus d'un desktop natif.

**Independent Test** : configurer 2 desktops macOS via Mission Control, créer 2 stages distincts sur chaque, basculer entre les desktops via Ctrl+→/←, vérifier que `roadie stage list` change de contenu et que `roadie stage 1` n'active que le stage 1 du desktop courant (jamais celui d'un autre desktop).

**Acceptance Scenarios** :
1. **Given** desktop 1 actif avec stage "code" et stage "logs" ; desktop 2 actif avec stage "comm". **When** l'utilisateur bascule du desktop 1 au desktop 2 via Ctrl+→. **Then** `roadie stage list` retourne uniquement "comm" en moins de 200 ms après la transition.
2. **Given** stage "code" actif sur desktop 1 avec 3 fenêtres tilées. **When** l'utilisateur passe sur desktop 2 puis revient sur desktop 1. **Then** stage "code" est toujours actif, les 3 fenêtres sont à leurs frames exactes pré-bascule.
3. **Given** un nouveau desktop macOS jamais visité par roadie. **When** l'utilisateur le focus pour la première fois. **Then** roadie initialise un état vierge (1 stage par défaut, tree vide qui se remplira avec les fenêtres présentes).

---

### User Story 2 - Gérer les desktops via la CLI roadie (Priority: P1)

L'utilisateur veut pouvoir lister, naviguer et nommer ses desktops depuis la CLI roadie sans passer par Mission Control. Il veut aussi pouvoir attribuer un nom mnémonique (ex: "dev", "comm", "rest") à chaque desktop pour les référencer dans des scripts.

**Why this priority** : intègre la commande `desktop` dans la grille CLI déjà familière (`stage`, `windows`, `daemon`) et débloque les workflows scriptés (changer de desktop depuis un raccourci BTT custom, intégrer dans un script de session).

**Independent Test** : utiliser `roadie desktop list` pour voir la liste, `roadie desktop label dev` pour renommer le desktop courant, `roadie desktop focus dev` pour y revenir depuis n'importe où.

**Acceptance Scenarios** :
1. **Given** 3 desktops macOS configurés. **When** l'utilisateur lance `roadie desktop list`. **Then** la sortie affiche un tableau avec colonnes `index | uuid | label | current | stage_count | window_count`.
2. **Given** l'utilisateur est sur desktop 2. **When** il lance `roadie desktop label dev`. **Then** desktop 2 reçoit le label "dev" persisté ; ultérieurement `roadie desktop focus dev` ramène sur ce desktop quel que soit son index actuel.
3. **Given** desktop courant `dev`. **When** `roadie desktop current --json` est lancé. **Then** la sortie JSON contient `{uuid, index, label: "dev", current_stage_id}`.
4. **Given** plusieurs desktops. **When** `roadie desktop focus prev|next|recent|first|last|N|<label>`. **Then** roadie demande à macOS de basculer (via API SkyLight stable, sans SIP désactivé).

---

### User Story 3 - Stream d'événements pour intégrations (Priority: P2)

L'utilisateur a une menu bar custom (SketchyBar, Stark, ou un script personnel) qui doit afficher en temps réel le desktop et le stage courant. Il veut un canal observable pour réagir aux transitions sans polling.

**Why this priority** : différenciateur UX vs AeroSpace, et demande typique des power-users macOS qui customisent leur menu bar. Inspire les `signal --add` de yabai et l'IPC events de Hyprland.

**Independent Test** : `roadie events --follow` produit du JSON-lines sur stdout ; basculer un desktop ou un stage doit générer immédiatement une ligne de la forme `{"event": "desktop_changed", "from": "uuid-A", "to": "uuid-B", "ts": "..."}`.

**Acceptance Scenarios** :
1. **Given** `roadie events --follow` lancé en background. **When** l'utilisateur change de desktop via Ctrl+→. **Then** une ligne JSON `desktop_changed` apparaît dans le flux dans les 200 ms.
2. **Given** un stage actif sur desktop 1. **When** l'utilisateur fait `⌥2`. **Then** une ligne `stage_changed` est émise avec `desktop_uuid` + `from` + `to`.
3. **Given** `roadie events --follow --filter desktop_changed`. **When** un stage change. **Then** rien n'apparaît (filtre actif).

---

### User Story 4 - Configuration par desktop (Priority: P2)

L'utilisateur veut que son desktop "présentation" ait des marges plus généreuses (`gaps_outer = 60` pour laisser de la place au public), tandis que son desktop "code" reste à `gaps_outer = 8`. Il veut aussi que chaque desktop puisse avoir sa propre stratégie de tiling (BSP par défaut, master-stack pour le desktop "monitoring").

**Why this priority** : permet la personnalisation par contexte, demande naturelle dès qu'on a plusieurs desktops avec des usages différents. Transposable de Hyprland workspace rules.

**Independent Test** : déclarer dans `roadies.toml` un override `[[desktops]] label = "présentation" gaps_outer = 60 default_strategy = "bsp"`. Au focus de ce desktop, vérifier visuellement que les marges changent.

**Acceptance Scenarios** :
1. **Given** config avec `[[desktops]] label = "code" default_strategy = "bsp"` et `[[desktops]] label = "monitoring" default_strategy = "master-stack"`. **When** l'utilisateur bascule entre les deux. **Then** chaque desktop applique sa stratégie sans intervention manuelle.
2. **Given** override `gaps_outer_bottom = 60` sur un desktop spécifique. **When** focus sur ce desktop. **Then** les fenêtres tilées laissent 60px en bas, autres desktops gardent leur valeur globale.

---

### Edge Cases

- **Premier boot V2 d'un utilisateur V1** : la migration doit mapper les stages V1 au desktop courant au moment du boot. Aucune perte de stage, aucun re-config requis.
- **Fenêtre déplacée par macOS d'un desktop à un autre** (drag dans Mission Control) : roadie doit la retirer du registry du desktop source au prochain switch et la reconnaître sur le desktop destination, sans crash ni fenêtre fantôme.
- **Plug/unplug d'un display** (V3 mais à anticiper) : les desktops du display déconnecté gelés, restaurés à la reconnexion.
- **Desktop macOS détruit par l'utilisateur** : roadie marque l'état comme orphelin, le supprime au prochain quit propre. Pas de panique.
- **Nombre élevé de desktops** : pas de limite arbitraire ; performance reste sous SC-001 jusqu'à 10 desktops × 10 stages.
- **`multi_desktop.enabled = false`** : roadie ignore les transitions de desktop, comportement V1 strict (mono-desktop logique). Tous les stages affichés peu importe le desktop physique.
- **API SkyLight indisponible** (futur macOS qui casserait l'API privée) : fallback vers comportement V1, log warning au boot.
- **Rapid-switching** entre desktops (debounce) : si l'utilisateur fait Ctrl+→ Ctrl+← Ctrl+→ rapidement (< 100 ms), seul l'état final compte ; pas de save-load intermédiaire qui fait clignoter.

---

## Requirements

### Functional Requirements — Desktop Awareness

- **FR-001** : Le daemon DOIT détecter le desktop macOS actif au boot et après chaque transition Mission Control. Détection via API SkyLight privée stable (`CGSGetActiveSpace` ou équivalent), sans nécessiter SIP désactivé.
- **FR-002** : Le daemon DOIT identifier chaque desktop par son `UUID` SkyLight (stable entre redémarrages tant que le desktop n'est pas détruit) et par son `index` (volatile, change si l'utilisateur réordonne les desktops).
- **FR-003** : La détection d'une transition de desktop DOIT déclencher un re-load du state correspondant en moins de 200 ms après la transition macOS.
- **FR-004** : Avant de quitter un desktop, le daemon DOIT sauvegarder son état complet : tree BSP, stages, stage actif, frames mémorisées, label éventuel, layout/gaps spécifiques.

### Functional Requirements — State per Desktop

- **FR-005** : L'état (stages, tree, layout, gaps, assignments) DOIT être indexé par UUID de desktop dans `~/.config/roadies/desktops/<uuid>.toml`. Lecture atomique au switch in, écriture atomique au switch out (via fichier temporaire + rename).
- **FR-006** : Au premier accès à un desktop jamais visité par roadie, l'état doit être initialisé avec un stage par défaut (configurable via `default_stage`) et un tree vide.
- **FR-007** : Les fenêtres physiquement présentes sur le desktop courant macOS DOIVENT apparaître dans le registry du desktop courant uniquement. Les fenêtres d'un autre desktop sont invisibles pour les commandes `roadie windows list` quand le desktop n'est pas actif.
- **FR-008** : Roadie ne DOIT JAMAIS modifier le desktop natif d'une fenêtre macOS. C'est macOS qui est maître de l'attribut `kAXSpaceID` ; roadie est lecteur.

### Functional Requirements — CLI desktop

- **FR-009** : La commande `roadie desktop list` DOIT afficher tous les desktops connus avec colonnes `index, uuid, label, current, stage_count, window_count`. Format texte par défaut, JSON avec `--json`.
- **FR-010** : La commande `roadie desktop focus <selector>` DOIT supporter les selectors `prev`, `next`, `recent`, `first`, `last`, `N` (index 1-based), `<label>`. Délègue à macOS via SkyLight.
- **FR-011** : La commande `roadie desktop current` DOIT retourner les infos du desktop actif (uuid, index, label, current_stage_id, stages count). JSON disponible.
- **FR-012** : La commande `roadie desktop label <name>` DOIT enregistrer un label pour le desktop courant, persisté entre sessions. Le label devient utilisable comme selector partout.
- **FR-013** : La commande `roadie desktop back` DOIT basculer vers le desktop précédent visité (option `back_and_forth = true` par défaut).

### Functional Requirements — Events

- **FR-014** : La commande `roadie events --follow` DOIT streamer les événements internes du daemon en JSON-lines sur stdout, sans buffering (auto-flush par event).
- **FR-015** : Les événements minimums à exposer en V2 : `desktop_changed`, `stage_changed`. Format `{"event": <name>, "ts": <ISO8601>, ...payload}`.
- **FR-016** : La commande DOIT supporter `--filter <event-name>` pour ne suivre qu'un sous-ensemble.

### Functional Requirements — Configuration

- **FR-017** : Une nouvelle section `[multi_desktop]` dans `roadies.toml` DOIT contenir au minimum `enabled = true|false` (défaut `false` pour compat V1) et `back_and_forth = true|false` (défaut `true`).
- **FR-018** : Section `[[desktops]]` répétable DOIT permettre de pré-définir des règles par desktop : matchage par `index` ou `label`, override de `default_strategy`, `gaps_outer*`, `gaps_inner`, `default_stage`.
- **FR-019** : `roadie daemon reload` DOIT appliquer les changements de config multi-desktop sans redémarrer le daemon, y compris activer/désactiver `multi_desktop.enabled` à chaud.

### Functional Requirements — Compatibilité ascendante

- **FR-020** : Si `multi_desktop.enabled = false` (défaut), roadie DOIT se comporter EXACTEMENT comme V1 : un seul state global, pas de reload au switch desktop, transitions Mission Control ignorées par le daemon.
- **FR-021** : La commande `roadie stage *` DOIT, en V2 avec multi-desktop activé, manipuler uniquement les stages **du desktop courant**. Aucun changement de syntaxe CLI.
- **FR-022** : Les 13 raccourcis BTT existants (focus/move HJKL, restart, stage 1/2 switch + assign) DOIVENT continuer à fonctionner sans modification, opérant toujours sur le desktop courant.
- **FR-023** : Au premier boot V2 d'un utilisateur V1 (présence de `~/.config/roadies/stages/` legacy sans `~/.config/roadies/desktops/`), les stages V1 DOIVENT être migrés au desktop courant à ce moment-là, sans perte ni renommage.

### Functional Requirements — Window→desktop pinning

- **FR-024** : Une règle config `[[window_rules]] bundle_id = "com.slack" pin_desktop = "comm"` DOIT, à l'apparition d'une fenêtre matching, demander à macOS de la déplacer vers le desktop cible. [NEEDS CLARIFICATION: faisabilité sans SIP désactivé. Fallback acceptable = règle en best-effort, log warning si macOS refuse].

### Key Entities

- **Desktop** : `(uuid, index, label?, last_active_at, state_path)` — représentation roadie d'un desktop macOS.
- **DesktopState** : `(desktop_uuid, stages: [Stage], current_stage_id, root_node: TreeNode, tiler_strategy, gaps_overrides?)` — l'état complet persisté par desktop.
- **DesktopRule** (config) : `(matcher: index|label, default_strategy?, gaps?, default_stage?)` — règles statiques en config.
- **Event** : `(event_name, ts, payload)` — message émis sur le canal events.
- **WindowState** (modifié) : `(...existing, desktop_uuid)` — chaque fenêtre est associée à exactement un desktop courant.

---

## Success Criteria

### Measurable Outcomes

- **SC-001** : Au switch d'un desktop macOS, la mise à jour du contexte roadie (chargement du state cible) se fait en moins de **200 ms** côté utilisateur (du moment où Mission Control termine sa transition jusqu'à ce que `roadie stage list` reflète le nouveau desktop).
- **SC-002** : Sur 100 cycles de switch desktop A↔B avec des stages et fenêtres assignés, le state est restauré à l'identique 100 % des cas (frames à ±2 px, stages identiques, stage actif identique).
- **SC-003** : Le daemon supporte au moins **10 desktops × 10 stages** sans dégradation perceptible (switch < 200 ms maintenu).
- **SC-004** : `roadie events --follow` ne perd aucun événement sur 1000 transitions consécutives (test par scripted Mission Control + diff stdout).
- **SC-005** : Compatibilité ascendante stricte : un utilisateur V1 qui upgrade vers V2 sans toucher à sa config DOIT retrouver ses stages exactement comme avant, 0 régression.
- **SC-006** : Aucune dépendance nouvelle au runtime (toujours frameworks système macOS uniquement, ajout des bindings SkyLight stable). Vérifié via `otool -L`.
- **SC-007** : Aucun fichier d'état desktop n'excède **50 KB** sur disque pour un usage typique (10 stages × 20 fenêtres). Pas de bloat sur quit/relance.
- **SC-008** : LOC Swift ajoutées pour la V2 multi-desktop ne DOIVENT pas dépasser **800 lignes effectives** (mesure via `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} +` après-avant). Plafond cumulé V1+V2 strict reste 4 000 LOC.
- **SC-009** : Aucun crash du daemon sur 24 h d'utilisation continue avec switch desktops réguliers (≥ 50 transitions).

---

## Assumptions

- L'API privée SkyLight `CGSGetActiveSpace` (et observers associés) reste disponible et stable sur macOS Sonoma 14, Sequoia 15, Tahoe 26 (même hypothèse que `_AXUIElementGetWindow` pour SPEC-001 et `_SLPSSetFrontProcessWithOptions` pour SPEC-002, validée par yabai et AeroSpace).
- L'utilisateur a `Réglages Système > Bureau & Dock > Mission Control > Displays have separate Spaces` configuré selon ses préférences ; roadie respecte le choix sans le contraindre.
- Le nombre de desktops macOS configurés par l'utilisateur reste raisonnable (< 20).
- Les apps Electron / certains comportements atypiques (Cursor, VSCode) ne posent pas de problème spécifique au multi-desktop au-delà de ce qui est déjà géré en V1 (PeriodicScanner, kAXMainWindowChangedNotification).
- Les tests d'intégration s'appuient sur un environnement avec au moins 2 desktops macOS configurés manuellement avant le test.

---

## Research Findings *(extrait analyse comparative yabai / AeroSpace / Hyprland / 39.roadies.off)*

- **yabai** : utilise `CGSGetActiveSpace` + observer, API privée SkyLight, lecture seule sans SIP off. Référence stable depuis 10 ans. Notre voie technique reprend ce pattern.
- **AeroSpace** : ne s'intègre PAS aux Spaces macOS natifs (workspaces internes simulés). Notre approche diffère car notre objectif est précisément de SUIVRE Mission Control, pas de le remplacer.
- **Hyprland** : modèle de workspace très riche (numbered + named + special + persistent). Inspirations transposables : commandes prev/next/recent, events stream, workspace rules — mais sa sémantique propre n'est pas applicable telle quelle.
- **39.roadies.off** (ancienne version Roadie) : avait conçu la persistance par `spaceUUID` + `displayUUID` (forward-compatible multi-display) mais n'avait implémenté que le mono-display. **Le modèle d'index par UUID est repris ici** (FR-005).

Aucun **red flag** identifié : approche techniquement éprouvée par yabai depuis 10 ans, contrainte SIP-off respectée, scope V2 délibérément restreint au mono-display.

---

## Out of Scope (V2)

- **Création / destruction / réordonnancement** de desktops macOS (interdit par FR-005 SPEC-002 — nécessiterait SIP désactivé).
- **Multi-display** : strictement reporté en V3. V2 = mono-display strict (un seul écran physique observé, plusieurs desktops sur cet écran OK).
- **Workspace overview / Mission Control roadie-style** : pas d'aperçu graphique des desktops/stages. L'UI reste CLI-driven, l'utilisateur s'appuie sur Mission Control natif pour la visualisation.
- **Trackpad gestures custom** : on respecte les gestures natifs macOS (3-doigts horizontal pour switch desktop), pas de hook gesture roadie en V2.
- **Sync state cross-machine** (iCloud, etc.) : strictement local.
- **Fenêtre épinglée à un desktop avec contrainte forte** (FR-024 best-effort uniquement, pas de blocage si macOS refuse le déplacement).
