# Feature Specification: Single source of truth pour la propriété stage/desktop d'une fenêtre

**Feature Branch**: `021-single-source-of-truth-stage-ownership`
**Status**: Draft
**Created**: 2026-05-03
**Dependencies**: SPEC-002 (Stage Manager), SPEC-013 (HideStrategy.corner), SPEC-018 (stages per-display), ADR-008 (install dev workflow)

## Vision

Le daemon roadie maintient aujourd'hui **deux sources de vérité** sur l'attribution d'une fenêtre à un stage :

| Source | Owner | Persistence |
|---|---|---|
| `WindowState.stageID` (champ par-fenêtre) | `WindowRegistry` (mémoire) | jamais sur disque, recalculé au boot depuis le 2 |
| `Stage.memberWindows: [StageMember]` (liste par stage) | `StageManager` (mémoire + disque) | `~/.config/roadies/stages/<UUID>/<desktop>/<stage>.toml` |

Ces deux sources divergent régulièrement au gré des sessions (crash daemon, switch desktop macOS via Mission Control non-tracé par roadie, drag-drop interrompu, migration V1→V2 partielle). Conséquence directe pour l'utilisateur : le navrail montre une fenêtre sur un stage et pas sur l'autre, alors que le daemon dit qu'elle est sur les deux. Bug observé plusieurs fois pendant la session 2026-05-03 (cf. ADR-008 et conversation associée).

Le mécanisme actuel de réconciliation (`reconcileStageOwnership`, appelé sur `windows.list` et `stage.list`) est un patch de symptôme : il prouve qu'on a deux sources et qu'on doit les recoller en permanence. Le bon move est de **tuer la source redondante**.

Cette spec élimine `WindowState.stageID` comme **champ stocké** et le transforme en **valeur calculée à la demande** depuis `memberWindows`. Inspiration directe : le pattern AeroSpace (chaque fenêtre est un nœud feuille de l'arbre, son workspace est trouvé en remontant `parent`). Pas de cache, pas de drift possible **par construction**.

En complément, la spec règle un second cas adjacent : la **propriété desktop macOS** d'une fenêtre. Aujourd'hui roadie cache implicitement cette info dans `(displayUUID, desktopID)` du scope où la wid figure dans `stagesV2`. Quand l'utilisateur déplace une fenêtre cross-desktop via Mission Control natif (Cmd+Drag, raccourcis Apple), roadie ne capte pas l'event → cache obsolète → bug de la wid 12 iTerm2 montré lors de la session. Inspiration : pattern yabai (`SLSCopySpacesForWindows(connID, mask, [wid])` à chaque besoin, OS = source unique).

## Non-buts

- **Pas de modification du format des fichiers TOML persistés**. `memberWindows` reste l'autorité métier, sa structure ne change pas.
- **Pas d'ajout de nouvelle dépendance** (pas de SLS privée nouvelle, on utilise celle déjà éprouvée par yabai en lecture seule, sans SIP off).
- **Pas de réécriture de SPEC-018** (stages per-display reste tel quel, c'est le mode de stockage qui ne change pas).
- **Pas de refactor des renderers** (SPEC-019 inchangée).
- **Pas de feature utilisateur visible** — c'est une refonte interne. Les UX ne doivent observer **aucun changement de comportement** sauf la disparition des bugs de drift.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Disparition du drift state.stageID ↔ memberWindows (Priority: P1, MVP)

En tant qu'utilisateur du stage manager, je veux que le navrail affiche **toujours** la même liste de fenêtres que celle qui est effectivement « sur ce stage » selon l'AX réel, peu importe combien le daemon a crashé, combien d'IPC entre rail et daemon ont eu lieu, ou combien de switch entre stages j'ai fait.

**Why this priority** : c'est le bug observé (et signalé multiple fois par l'utilisateur) qui motive la SPEC entière. Sans corriger la source du désync, on continuera à voir des vignettes manquantes ou en trop.

**Independent Test** : démarrer le daemon, ouvrir 4 fenêtres, les répartir sur 2 stages, faire un crash brutal du daemon (`kill -9`) en plein milieu d'une transition de stage, relancer. Le navrail au boot doit afficher exactement les fenêtres que macOS affiche actuellement à l'écran ou en parking offscreen. Aucune fenêtre ne doit être « manquante » dans une vignette ni présente en double dans deux stages différents du même scope.

**Acceptance Scenarios** :
1. **Given** un stage 1 contenant 3 fenêtres iTerm2 (wid 12, 15, 22) et un stage 2 contenant 2 fenêtres Firefox (wid 100, 200), **When** le daemon est tué `kill -9` puis relancé, **Then** la sortie de `roadie windows list` ET de `roadie stage list` montre strictement les mêmes wids dans les mêmes stages avant et après le restart.
2. **Given** le même état, **When** l'utilisateur drag-drop la wid 22 du stage 1 vers le stage 2 dans le navrail, **Then** la wid 22 apparaît dans le stage 2 et **uniquement** dans le stage 2 ; sa propriété de stage est immédiatement cohérente entre `windows.list`, `stage.list`, et le fichier TOML sur disque.
3. **Given** une wid orpheline présente dans `stage.windowIDs` mais absente du registry AX (app fermée pendant que daemon était down), **When** le daemon relance, **Then** la wid est nettoyée des `memberWindows` au boot avant le premier appel IPC du rail (pas de vignette fantôme dans le navrail).

### User Story 2 — Disparition du drift desktop macOS ↔ scope persisté (Priority: P1)

En tant qu'utilisateur de Mission Control, je veux pouvoir déplacer une fenêtre d'un desktop macOS à l'autre via les raccourcis Apple natifs (Ctrl+→/←, drag dans Mission Control, glisser vers le bord d'écran) **sans** que roadie perde la trace de cette fenêtre. Quand je reviens sur le desktop d'arrivée, le navrail doit montrer la fenêtre correctement attachée à un stage de ce desktop.

**Why this priority** : c'est le bug wid 12 iTerm2 observé en session — la fenêtre s'était déplacée vers desktop 1 via macOS natif, mais roadie pensait toujours qu'elle était sur desktop 2 → vignette manquante. Sans cette correction, le multi-desktop V2 reste cassé pour les utilisateurs qui mixent navigation Apple native et raccourcis roadie.

**Independent Test** : ouvrir 1 fenêtre iTerm2 sur desktop 1. Via Mission Control natif (Ctrl+drag), la déplacer vers desktop 2. Vérifier que `roadie windows list` retourne `desktop_id=2` pour cette wid sans aucune action manuelle de l'utilisateur côté roadie.

**Acceptance Scenarios** :
1. **Given** une wid Firefox sur desktop 1 stage 1, **When** l'utilisateur glisse la fenêtre dans Mission Control vers desktop 2, **Then** dans la seconde qui suit, `roadie windows list` montre `desktop_id=2` pour cette wid, et la vignette apparaît dans le panneau navrail du desktop 2.
2. **Given** la même wid déplacée à l'instant T0, **When** l'utilisateur switch sur desktop 2 à T1 = T0+5s, **Then** le navrail du desktop 2 contient déjà la vignette de cette fenêtre (pas de retard d'affichage) ; aucun reload manuel `daemon reload` n'est nécessaire.
3. **Given** la wid déplacée vers desktop 2, **When** le daemon est tué et relancé, **Then** au boot la wid est bien rattachée au desktop 2 (pas au desktop 1 d'origine) — la persistance reflète la réalité macOS courante, pas un état figé.

### User Story 3 — Suppression de `reconcileStageOwnership` (Priority: P2)

En tant que mainteneur du projet, je veux que la fonction `reconcileStageOwnership` (StageManager.swift:371-461, ~90 LOC) **soit supprimée** parce qu'elle devient sans objet : avec une seule source de vérité, il n'y a plus rien à réconcilier. Cette suppression réduit la complexité et la surface de bug.

**Why this priority** : optimisation post-refactor, pas une dépendance bloquante. Mais sans cette suppression, on garde du code mort qui peut introduire de la confusion.

**Independent Test** : `grep -r "reconcileStageOwnership" Sources/ Tests/` doit retourner 0 occurrence après livraison. La suite de tests existante doit passer sans cette fonction.

**Acceptance Scenarios** :
1. **Given** le code post-refactor, **When** on greppe `reconcileStageOwnership` dans `Sources/`, **Then** aucune occurrence trouvée.
2. **Given** la suite de tests `swift test`, **When** exécutée après suppression, **Then** 100 % verts.

### User Story 4 — Robustesse aux mutations concurrentes (Priority: P2)

En tant qu'utilisateur power qui fait du Cmd+Tab rapide entre apps simultanément à des switch de stage via raccourcis BTT, je veux que **aucune fenêtre ne se retrouve dans un état incohérent** (présente dans deux stages, fantôme dans un stage vide, désync state mémoire ↔ disque).

**Why this priority** : robustesse plus qu'une feature visible. Sans cette garantie, le bug de drift peut réapparaître subtilement sous charge.

**Independent Test** : script qui déclenche 100 transitions stage/desktop en moins de 5 s (mix CLI + AX simulé). À la fin, audit complet de cohérence : pour chaque wid dans le registry, son `stageID()` calculé doit pointer vers un stage qui contient effectivement la wid dans ses `memberWindows`. Et inversement, pour chaque entrée `memberWindows`, la wid doit exister dans le registry.

**Acceptance Scenarios** :
1. **Given** 100 transitions exécutées sur 5 s, **When** on inspecte le registry et tous les fichiers TOML, **Then** `wid → stage` (calculé) et `stage → wids` (lu) sont symétriques à 100 %.
2. **Given** une transition interrompue mid-flight (Task cancelled), **Then** l'état final est soit l'état pré-transition complet, soit l'état post-transition complet, jamais entre les deux.

## Requirements *(mandatory)*

### Functional Requirements — élimination du double state stage

- **FR-001** : `WindowState.stageID` DOIT être supprimé en tant que **champ stocké**. Toute écriture sur ce champ (8 call-sites identifiés au moment de la rédaction) DOIT être supprimée.
- **FR-002** : la valeur « stage de la wid » DOIT devenir calculable via une nouvelle API `StageManager.scopeOf(wid: WindowID) -> StageScope?` (en mode `per_display`) et `StageManager.stageIDOf(wid: WindowID) -> StageID?` (en mode `global`).
- **FR-003** : la résolution DOIT être en O(stages × members) en pire cas. Avec un index inverse `widToScope: [WindowID: StageScope]` reconstruit à chaque mutation de `stagesV2`/`stages`, l'accès devient O(1) amorti. Cet index est **dérivé**, pas une source de vérité (équivalent au cache qu'on tue ; mais il vit dans `StageManager` et est invalidé par tous les chemins de mutation, pas dispersé dans le codebase).
- **FR-004** : si pour rétrocompatibilité d'API, le champ `WindowState.stageID` doit rester accessible en lecture, il DOIT être transformé en `var` calculée délégant à `StageManager.scopeOf(wid)?.stageID`. Aucune affectation `state.stageID = X` ne doit être possible (compile error).
- **FR-005** : la fonction `StageManager.reconcileStageOwnership()` DOIT être supprimée, ainsi que les 4 call-sites identifiés (CommandRouter `windows.list`, `stage.list`, et 2 dans main.swift). Test : `grep -r reconcileStageOwnership Sources/ Tests/` retourne 0.
- **FR-006** : au boot du daemon, le rebuild de `state.stageID` à partir des fichiers TOML (block main.swift:871-883 — « CAUSE RACINE Grayjay ») DOIT être supprimé. La résolution se fait à la demande via FR-002.
- **FR-007** : toute logique qui filtrait sur `state.stageID` DOIT être convertie pour interroger `StageManager.scopeOf(wid)`. Les call-sites concernés incluent : `MouseRaiser.swift:119` (click-in-other-stage detection), `LayoutEngine` (insertions BSP), `CommandRouter` (réponse `windows.list`).
- **FR-008** : la persistence sur disque (sérialisation `Stage.memberWindows`) DOIT rester strictement inchangée. Les fichiers TOML existants côté utilisateurs doivent rester lisibles et sémantiquement équivalents post-refactor.

### Functional Requirements — élimination du cache desktop par-wid

- **FR-010** : roadie ne DOIT plus inférer le desktop d'une wid uniquement depuis le scope où elle figure dans `stagesV2`. Quand le daemon a besoin de connaître le desktop courant d'une wid, il DOIT interroger SkyLight via `SLSCopySpacesForWindows(connectionID, mask: 0x7, [wid])` (déjà utilisé en lecture par yabai sans SIP off, pattern éprouvé).
- **FR-011** : le mapping `space_id` SkyLight → `(displayUUID, desktopID)` roadie DOIT réutiliser la table existante `DesktopRegistry` (SPEC-013). Si le space_id retourné par SkyLight ne mappe à aucun desktop connu, fallback sur le scope persisté (ne pas cracher).
- **FR-012** : la résolution du desktop d'une wid DOIT être appelée à 3 moments :
  1. **Au boot** du daemon, pour chaque wid détectée par AX scan, comparer son desktop SkyLight au desktop persisté ; si différent, déplacer la wid vers le scope correct **avant** la première réponse IPC.
  2. **Sur l'event AX `kAXFocusedWindowChanged`** quand une wid focused n'est pas dans le scope courant : avant de déclencher `followAltTabFocus`, vérifier que le desktop SkyLight de la wid matche son scope persisté ; sinon, ré-attribuer la wid au desktop SkyLight courant.
  3. **Sur poll périodique léger** (toutes les 2 s pour les wids tileables visibles à l'écran). Permet de capter les déplacements via Mission Control natif sans event AX dédié. Configurable via `[multi_desktop].window_desktop_poll_ms` (défaut 2000, 0 = désactivé).
- **FR-013** : les écritures TOML qui résultent d'une ré-attribution detectée par poll DOIVENT être idempotentes : si le scope persisté est déjà correct, aucune écriture disque n'a lieu (évite churn inutile).
- **FR-014** : `roadie windows list` (et payload IPC `windows.list`) DOIT continuer à retourner `desktop_id` pour chaque wid, mais ce champ DOIT désormais être calculé via FR-010, pas lu d'un cache.

### Functional Requirements — invariants de cohérence

- **FR-020** : à tout moment, si `wid ∈ stagesV2[scope].memberWindows` et `wid ∈ registry.allWindows`, alors `StageManager.scopeOf(wid)?.stageID == scope.stageID`. Garanti par construction (FR-002).
- **FR-021** : à tout moment, une wid ne DOIT figurer dans **plus d'un scope** dans `stagesV2`. Lors d'un `assign(wid: to:)`, le retrait des autres scopes DOIT être inconditionnel (déjà le cas en partie via le code F11 commentaire StageManager.swift:629, mais la SPEC l'impose explicitement). Test : itérer toutes les paires de scopes, vérifier l'intersection des `memberWindows` est vide.
- **FR-022** : au boot, après scan AX initial, toute wid présente dans plusieurs fichiers TOML DOIT être réduite à une seule attribution (la plus récente d'après `lastActiveAt` du scope). Les autres entrées DOIVENT être supprimées sur disque immédiatement.
- **FR-023** : un audit `roadie daemon audit` (nouvelle commande, optionnelle) DOIT permettre de vérifier les invariants ci-dessus à la demande, retourner un rapport JSON, et NE PAS modifier l'état (read-only).

### Non-Functional Requirements

- **NFR-001** : aucun appel SkyLight (`SLSCopySpacesForWindows`) en hot path AX (per-frame). Le poll FR-012.3 reste le seul chemin régulier, à fréquence configurée.
- **NFR-002** : performance lookup `scopeOf(wid)` ≤ 1 µs (index inverse en `Dictionary`).
- **NFR-003** : zéro régression observable côté utilisateur sur les SPECs livrées (002, 013, 014, 018). La suite de tests existante DOIT passer 100 % post-refactor sans modification.
- **NFR-004** : LOC nettes du refactor. Cible **réduction nette ≥ 50 LOC** (suppression de `reconcileStageOwnership` + 8 call-sites de mutation de `state.stageID` − ajouts pour l'index inverse et le hook SkyLight). Audit `wc -l Sources/RoadieStagePlugin/StageManager.swift Sources/roadied/main.swift Sources/RoadieCore/Types.swift` avant/après.
- **NFR-005** : la fonction `SLSCopySpacesForWindows` doit être déclarée en `@_silgen_name` ou via header bridge minimal (≤ 10 LOC bridging). Pattern documenté yabai.

## Success Criteria *(mandatory)*

- **SC-001** : `grep -r "registry.update.*stageID\s*=" Sources/` retourne 0 occurrences (toute mutation de `state.stageID` éliminée).
- **SC-002** : `grep -r "reconcileStageOwnership" Sources/ Tests/` retourne 0.
- **SC-003** : test scénarios US1 + US2 + US4 passent intégralement (script de stress 100 transitions sur 5 s, 0 incohérence détectée par `roadie daemon audit`).
- **SC-004** : LOC nettes ≤ LOC pré-refactor − 50 sur la zone (3 fichiers Sources/RoadieStagePlugin/StageManager.swift, Sources/roadied/main.swift, Sources/RoadieCore/Types.swift).
- **SC-005** : test manuel — déplacer une fenêtre via Mission Control entre desktop 1 et 2, observer dans `roadie windows list --json` que `desktop_id` reflète la position macOS courante en moins de 3 s.
- **SC-006** : zero régression sur les SPECs précédentes — `swift test` passe 100 %, audit visuel du navrail post-refactor identique pré-refactor sur 5 cas typiques.

## Edge Cases

- **EC-001** : SkyLight retourne un `space_id` inconnu de `DesktopRegistry` (ex: bureau macOS créé après le boot du daemon). Fallback : ré-fetcher la liste des desktops via `CGSCopyManagedDisplaySpaces`, mettre à jour `DesktopRegistry`, retry. Si toujours inconnu après 1 retry : log warning + utiliser le scope persisté.
- **EC-002** : poll FR-012.3 actif pendant que l'utilisateur draggue activement une fenêtre cross-desktop. Le space_id retourné par SkyLight peut osciller (mid-flight). Mitigation : exiger 2 polls consécutifs avec le même space_id avant de déclencher la ré-attribution (debounce simple).
- **EC-003** : wid figure dans 2 fichiers TOML au boot (état hérité d'une session précédente buggée). FR-022 résout : garde l'attribution la plus récente (`lastActiveAt`), supprime les autres.
- **EC-004** : utilisateur retire la perm Accessibility en plein run. SkyLight reste accessible (lecture seule, pas TCC). Mais AX n'est plus accessible → `state.frame` figé → poll continue à fonctionner mais devient sans effet utile. Pas un regression, comportement identique à HEAD.
- **EC-005** : fenêtre native fullscreen (qui crée son propre desktop macOS). SkyLight retourne le `space_id` du fullscreen-desktop. `DesktopRegistry` peut ne pas le connaître. Géré par EC-001.
- **EC-006** : daemon kill -9 pendant un `assign(wid:to:scope)` (entre la mutation `stagesV2` et l'écriture TOML). Au reboot, FR-022 nettoie les inconsistances. Aucune action utilisateur requise.
- **EC-007** : multiple displays avec UUIDs identiques (théoriquement impossible mais constaté en pratique sur certains adapters HDMI). Les `(displayUUID, desktopID, stageID)` continuent à dédoublonner correctement, EC trivial.

## Assumptions

- **A-001** : `SLSCopySpacesForWindows(connID, mask: 0x7, [wid])` retourne le `space_id` du desktop visible courant pour la wid (pas son desktop d'origine). Vérifié par yabai en prod depuis 5+ ans, pattern stable.
- **A-002** : la latence d'un appel `SLSCopySpacesForWindows` est ≤ 1 ms en charge typique (< 100 wids). Vérifiable via micro-bench.
- **A-003** : `DesktopRegistry` SPEC-013 expose déjà la table `space_id → (displayUUID, desktopID)`. Si non, ajout mineur en pré-requis (≤ 30 LOC).
- **A-004** : aucun consommateur externe de roadie ne dépend du champ `WindowState.stageID` au-delà des call-sites internes énumérés. Pas de SDK public, pas de plugin tiers — vérifié par grep.
- **A-005** : la migration des fichiers TOML existants n'est pas nécessaire. Le format ne change pas (FR-008).

## Décisions à valider AVANT démarrage plan

1. **Nom de l'API publique** : `StageManager.scopeOf(wid:)` ou `StageManager.ownership(of:)` ou autre ? **Reco** : `scopeOf(wid:)` court et symétrique avec `windowsIn(scope:)`.
2. **Index inverse `widToScope`** : recalculé à chaque mutation, OU mis à jour incrémentalement ? **Reco** : incrémental (perf, simplicité — `assign()` retire de l'ancien scope dans l'index, ajoute au nouveau).
3. **Poll FR-012.3** : `Timer.scheduledTimer` 2 Hz côté daemon, OU `CFRunLoopTimer` plus précis, OU `Task @MainActor` async ? **Reco** : `Task` async avec `try await Task.sleep`, simple et OS-friendly. Identique à ce qui se fait pour le thumbnail refresh dans le rail.
4. **Fallback sur poll désactivé** (`window_desktop_poll_ms = 0`) : tolérer le drift Mission Control ? **Reco** : oui, c'est un opt-out explicite ; documenter le tradeoff dans le commentaire TOML.
5. **Audit CLI `roadie daemon audit`** : SC P2 (utile pour debug en prod) ou SC P3 (nice-to-have) ? **Reco** : P2, ne pas bloquer le MVP, peut être livré en suite indépendante.
6. **Bridging SLSCopySpacesForWindows** : header C dans Sources/RoadieCore/include/, OU déclaration `@_silgen_name` directe Swift ? **Reco** : `@_silgen_name`, plus court, déjà utilisé pour AX dans le projet — vérifier la cohérence avec patterns en place.

## Dependencies

- **SPEC-002** : Stage Manager — fournit `StageManager`, `Stage`, `StageMember`. C'est le code refactoré.
- **SPEC-013** : DesktopRegistry — fournit le mapping `space_id → desktop`. Pré-requis si non encore exposé publiquement.
- **SPEC-018** : stages per-display — la sémantique `stagesV2[StageScope]` est conservée, c'est le mode de stockage qui ne change pas.
- **ADR-008** : install dev workflow — pour rebuild + redéployer après chaque commit du refactor sans perdre la perm Accessibility.

## Out of scope (peut faire l'objet de specs ultérieures)

- **Refactor `WindowState.expectedFrame`** : autre champ stocké qui pourrait suivre une logique similaire (calculé à partir de la dernière frame on-screen captée). Hors scope ici, c'est un bug différent (SPEC-013).
- **Suppression de `Stage.memberWindows.savedFrame`** : redondant avec `WindowState.expectedFrame`. Hors scope.
- **Migration vers une représentation d'arbre AeroSpace-style** (chaque wid = nœud feuille, parent = TilingContainer/Workspace). Plus radical, demande refactor LayoutEngine + StageManager simultanés. Pas nécessaire pour résoudre le bug actuel — MVP = juste tuer la duplication.
- **Index inverse exposé via IPC** (ex: `wid.scope` direct sans passer par `windows.list`). Optimisation utilisateur, peut venir plus tard.
