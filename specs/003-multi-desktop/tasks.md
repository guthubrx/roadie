# Tasks: Multi-desktop awareness (roadies V2)

**Feature** : SPEC-003 multi-desktop
**Branch** : `003-multi-desktop`
**Date** : 2026-05-01
**Input** : [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichier différent, pas de dépendance avec une tâche en cours)
- `[USn]` = rattache la tâche à User Story n (uniquement dans phases user stories)
- Setup / Foundational / Polish : pas de label `[US]`
- Tests inclus selon Phase 1 plan : XCTest unitaires + intégration shell

---

## Phase 1 — Setup

- [ ] T001 Créer dossier `Sources/RoadieCore/desktop/` pour grouper les nouveaux modules de la couche desktop
- [ ] T002 Créer dossier `Tests/RoadieCoreTests/desktop/` pour les tests unitaires de la couche desktop
- [ ] T003 [P] Créer `tests/integration/06-multi-desktop-switch.sh` (squelette exécutable, exit 0 placeholder, droits +x)
- [ ] T004 [P] Créer `tests/integration/07-multi-desktop-migration.sh` (squelette exécutable, droits +x)
- [ ] T005 Mettre à jour `Package.swift` : aucune nouvelle dépendance, vérifier que SkyLight reste linké dans `RoadieCore` (déjà OK V1, juste un check explicite)

---

## Phase 2 — Foundational (prerequisites pour TOUTES les user stories)

**⚠️ Ces tâches DOIVENT être complétées avant toute Phase 3+. Aucun [US] car partagé.**

- [ ] T010 Étendre `Sources/RoadieCore/PrivateAPI.swift` : ajouter bindings `@_silgen_name` pour `CGSGetActiveSpace(cid: CGSConnectionID) -> CGSSpaceID` et `CGSCopyManagedDisplaySpaces(cid: CGSConnectionID) -> CFArray?`
- [ ] T011 Définir le type `CGSSpaceID = UInt64` et `CGSConnectionID = Int32` dans `Sources/RoadieCore/PrivateAPI.swift` (alias publics)
- [ ] T012 Créer `Sources/RoadieCore/desktop/DesktopProvider.swift` : protocole `DesktopProvider` avec méthodes `currentDesktopUUID() -> String?`, `listDesktops() -> [DesktopInfo]`, `requestFocus(uuid: String)` (async fire-and-forget pour basculer via SkyLight)
- [ ] T013 [P] Créer `Sources/RoadieCore/desktop/DesktopInfo.swift` : struct `DesktopInfo { uuid: String; index: Int; label: String? }` (Equatable, Sendable)
- [ ] T014 Implémenter `Sources/RoadieCore/desktop/SkyLightDesktopProvider.swift` : implémentation prod du protocole, cross-référence `CGSGetActiveSpace` ↔ `CGSCopyManagedDisplaySpaces` pour récupérer l'UUID actif
- [ ] T015 [P] Créer `Sources/RoadieCore/desktop/MockDesktopProvider.swift` : implémentation test scriptable (séquence de transitions injectables)
- [ ] T016 Créer `Sources/RoadieCore/desktop/DesktopState.swift` : struct `DesktopState` avec champs (`desktopUUID`, `displayName?`, `tilerStrategy`, `currentStageID?`, `version`, `gapsOverride?`, `stages: [Stage]`, `rootNode: TreeNode`) — voir [data-model.md](./data-model.md)
- [ ] T017 Implémenter sérialisation TOML de `DesktopState` (encode/decode via TOMLKit déjà présent V1) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [ ] T018 Implémenter écriture atomique `DesktopState.write(to: URL)` (fichier `.tmp` + `rename`) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [ ] T019 Implémenter lecture `DesktopState.read(from: URL)` avec validation (uuid non vide, format UUID, currentStageID référencé) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [ ] T020 Étendre `Sources/RoadieCore/Config.swift` : ajouter section `[multi_desktop]` avec champs `enabled: Bool` (défaut `false`) et `back_and_forth: Bool` (défaut `true`)
- [ ] T021 Étendre `Sources/RoadieCore/Config.swift` : ajouter section `[[desktops]]` répétable parsée en `[DesktopRule]` (champs `match_index: Int?`, `match_label: String?`, `default_strategy?`, `gaps_*?`, `default_stage?`)
- [ ] T022 Valider la config dans `Sources/RoadieCore/Config.swift` : règle DesktopRule doit avoir au moins un de `match_index` ou `match_label`, jamais les deux ; rejeter au reload sinon
- [ ] T023 Étendre `Sources/RoadieCore/WindowRegistry.swift` : ajouter champ `desktopUUID: String?` à `WindowState`, défaut `nil` au boot, mis à jour lors des transitions

---

## Phase 3 — User Story 1 (P1) 🎯 MVP V2 : Suivre automatiquement le desktop courant

**Goal** : quand l'utilisateur bascule de desktop macOS, roadie sauvegarde l'état du desktop quitté, charge celui d'arrivée, en moins de 200 ms.

**Independent Test** : 2 desktops macOS configurés, 2 stages distincts par desktop ; bascule via Ctrl+→ ; `roadie stage list` change de contenu et `roadie stage 1` n'active que le stage du desktop courant.

### Implémentation

- [ ] T030 [US1] Créer `Sources/RoadieCore/desktop/DesktopManager.swift` : actor `@MainActor` avec dépendance injectée `DesktopProvider`, état interne `currentUUID: String?`, `recentUUID: String?`
- [ ] T031 [US1] Implémenter dans `Sources/RoadieCore/desktop/DesktopManager.swift` la subscription à `NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification)` (lifecycle géré par DesktopManager)
- [ ] T032 [US1] Implémenter méthode `DesktopManager.handleSpaceChange()` : récupère nouvel UUID via `provider.currentDesktopUUID()`, si différent de `currentUUID` déclenche `onTransition(from:to:)`
- [ ] T033 [US1] Définir hook `DesktopManager.onTransition: (@MainActor (from: String?, to: String) async -> Void)?` injecté par `roadied/main.swift` pour câbler save+load
- [ ] T034 [US1] Implémenter `DesktopState.path(for: uuid)` qui renvoie `~/.config/roadies/desktops/<uuid>.toml` (création du dossier parent si absent) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [ ] T035 [US1] Implémenter dans `Sources/RoadieStagePlugin/StageManager.swift` un mode multi-desktop : stockage interne `[desktopUUID: StageState]` (au lieu d'un state global unique), méthode `loadDesktop(uuid)` et `saveCurrentDesktop()` qui dump le state actif
- [ ] T036 [US1] Préserver le mode V1 dans `Sources/RoadieStagePlugin/StageManager.swift` : si `Config.multiDesktop.enabled == false`, le state reste global comme avant (kill switch effectif)
- [ ] T037 [US1] Câbler dans `Sources/roadied/main.swift` : instancier `DesktopManager` au boot uniquement si `multi_desktop.enabled == true`, brancher `onTransition` qui fait `stageManager.saveCurrentDesktop()` puis `stageManager.loadDesktop(to)` puis `tiler.applyLayout()`
- [ ] T038 [US1] Ajouter dans `Sources/RoadieCore/desktop/DesktopState.swift` la création d'un état vierge (`DesktopState.empty(uuid:, defaultStage:)`) utilisé au premier accès à un desktop jamais visité (FR-006)
- [ ] T039 [US1] Mettre à jour `Sources/RoadieCore/WindowRegistry.swift` : à chaque `desktop_changed`, marquer `desktopUUID = currentUUID` pour toutes les fenêtres présentes dans le registry au moment de la transition (les fenêtres visibles macOS sur le desktop courant). Les fenêtres orphelines d'un desktop précédent gardent leur `desktopUUID` antérieur jusqu'à reapparition. Conforme au data-model (`desktopUUID: String? — Mise à jour au boot et à chaque transition de desktop`) (FR-007)
- [ ] T040 [US1] Implémenter migration V1→V2 dans `Sources/roadied/main.swift` au premier boot V2 : si `~/.config/roadies/stages/` existe et `~/.config/roadies/desktops/` n'existe pas, déplacer les fichiers vers `~/.config/roadies/desktops/<current-uuid>.toml`, créer backup horodaté `~/.config/roadies/stages.v1-backup-YYYYMMDD/` (FR-023)
- [ ] T041 [US1] Garder un compteur de latence dans `DesktopManager` : mesurer délai entre `activeSpaceDidChangeNotification` et fin de `applyLayout()`, log warning si > 200 ms (couvre SC-001)

### Tests US1

- [ ] T045 [P] [US1] Créer `Tests/RoadieCoreTests/desktop/DesktopManagerTests.swift` : test unitaire transition simulée via `MockDesktopProvider`, vérifier que `onTransition` est appelé avec le bon `from`/`to`
- [ ] T046 [P] [US1] Créer `Tests/RoadieCoreTests/desktop/DesktopStateTests.swift` : tests round-trip TOML (write puis read produit le même state), tests validation (uuid invalide rejeté, currentStageID inconnu rejeté)
- [ ] T047 [P] [US1] Ajouter dans `Tests/RoadieCoreTests/desktop/DesktopStateTests.swift` test de migration V1→V2 : créer une arborescence `~/.config/roadies/stages/*.toml` factice dans tmpdir, lancer la migration, vérifier que `~/.config/roadies/desktops/<uuid>.toml` est créé et que le backup est présent
- [ ] T048 [US1] Compléter `tests/integration/06-multi-desktop-switch.sh` : scripté `osascript` pour basculer Mission Control desktop 1↔2, vérifier que `roadie stage list` change de contenu, asserter latence < 200 ms (timestamp avant/après)
- [ ] T049 [US1] Compléter `tests/integration/07-multi-desktop-migration.sh` : préparer un `~/.config/roadies/stages/` V1, lancer roadied avec `multi_desktop.enabled=true`, vérifier que `~/.config/roadies/desktops/<uuid>.toml` est créé et que le backup existe

**Checkpoint US1** : un utilisateur peut activer V2, créer 2 stages sur desktop 1, basculer sur desktop 2, créer 1 stage différent, revenir sur desktop 1, retrouver ses 2 stages exacts. MVP V2 livrable.

---

## Phase 4 — User Story 2 (P1) : CLI desktop

**Goal** : commandes `roadie desktop list/focus/current/label/back` opérationnelles.

**Independent Test** : `roadie desktop list` affiche le tableau, `roadie desktop label dev` puis `roadie desktop focus dev` ramène sur le bon desktop.

### Implémentation

- [ ] T060 [US2] Étendre `Sources/roadied/CommandRouter.swift` : nouveau handler `desktop.list` qui retourne JSON `{current_uuid, desktops: [{index, uuid, label, stage_count, window_count}]}` (voir [contracts/cli-protocol.md](./contracts/cli-protocol.md))
- [ ] T061 [US2] Étendre `Sources/roadied/CommandRouter.swift` : handler `desktop.current` qui retourne le DesktopInfo + `current_stage_id` + counts
- [ ] T062 [US2] Étendre `Sources/roadied/CommandRouter.swift` : handler `desktop.focus` avec selectors `prev|next|recent|first|last|N|<label>`, délègue à `DesktopProvider.requestFocus(uuid:)` (FR-010)
- [ ] T063 [US2] Implémenter résolution selector dans `Sources/RoadieCore/desktop/DesktopManager.swift` : méthode `resolveSelector(_ s: String) -> String?` qui retourne l'UUID cible, gère `back_and_forth` quand selector match `currentUUID` (FR-013)
- [ ] T064 [US2] Étendre `Sources/roadied/CommandRouter.swift` : handler `desktop.label` qui pose un label sur le desktop courant (validation : alphanumérique + `-_`, max 32 chars), persiste dans `DesktopState.displayName`
- [ ] T065 [US2] Étendre `Sources/roadied/CommandRouter.swift` : handler `desktop.back` alias de `desktop.focus recent`
- [ ] T066 [US2] Étendre `Sources/roadie/main.swift` : nouveau verbe `desktop` avec sous-commandes `list`, `focus <selector>`, `current`, `label <name>`, `back` ; flag `--json` global
- [ ] T067 [US2] Implémenter codes d'exit dans `Sources/roadie/main.swift` : 0 succès, 2 selector invalide, 3 daemon non joignable, 4 `multi_desktop.enabled=false`, 5 desktop introuvable (voir [contracts/cli-protocol.md](./contracts/cli-protocol.md))
- [ ] T068 [US2] Bloquer toutes les sous-commandes `desktop *` (sauf `list --json` lecture) si `multi_desktop.enabled == false` avec message explicite "multi_desktop disabled, set enabled=true in roadies.toml"
- [ ] T069 [US2] Implémenter formattage texte du tableau `desktop list` dans `Sources/roadie/main.swift` : colonnes alignées `INDEX UUID LABEL CURRENT STAGES WINDOWS` (voir contracts)

### Tests US2

- [ ] T075 [P] [US2] Étendre `Tests/RoadieCoreTests/desktop/DesktopManagerTests.swift` avec test `resolveSelector` : couvrir `prev`/`next`/`recent`/`first`/`last`/index/label/inconnu
- [ ] T076 [US2] Compléter `tests/integration/06-multi-desktop-switch.sh` : ajouter assertions sur `roadie desktop list --json`, `roadie desktop focus next`, `roadie desktop label X` puis `focus X`

**Checkpoint US2** : la grille CLI desktop est complète, scriptable, intégrable dans BTT.

---

## Phase 5 — User Story 3 (P2) : Stream d'événements

**Goal** : `roadie events --follow` push des événements JSON-lines à chaque transition desktop ou stage.

**Independent Test** : `roadie events --follow` en background, basculer un desktop, voir une ligne `desktop_changed` apparaître dans le flux en moins de 200 ms.

### Implémentation

- [ ] T080 [US3] Créer `Sources/RoadieCore/desktop/EventBus.swift` : actor `EventBus` avec API `publish(event: Event)` et `subscribe() -> AsyncStream<Event>`
- [ ] T081 [US3] Définir struct `Event` dans `Sources/RoadieCore/desktop/EventBus.swift` : champs `eventName`, `ts: Date`, `payload: [String: AnyCodable]`, méthode `toJSONLine() -> String` (voir [contracts/events-stream.md](./contracts/events-stream.md))
- [ ] T082 [US3] Émettre event `desktop_changed` depuis `Sources/RoadieCore/desktop/DesktopManager.swift.handleSpaceChange()` avec champs `from`, `to`, `from_index`, `to_index`, `from_label`, `to_label` (voir contracts)
- [ ] T083 [US3] Émettre event `stage_changed` depuis `Sources/RoadieStagePlugin/StageManager.swift` à chaque switch (incluant via raccourci ⌥1/⌥2) avec champs `desktop_uuid`, `from`, `to`, `from_name`, `to_name`
- [ ] T084 [US3] Étendre `Sources/roadied/CommandRouter.swift` : handler `events.subscribe` qui ouvre un mode push sur la connexion socket (le client reste connecté, le daemon push les events au fil de l'eau jusqu'à fermeture)
- [ ] T085 [US3] Étendre `Sources/roadie/main.swift` : nouveau verbe `events` avec sous-option `--follow`, qui ouvre la connexion `events.subscribe` et streame les lignes vers stdout (auto-flush)
- [ ] T086 [US3] Implémenter `--filter <event-name>` (répétable) dans `Sources/roadie/main.swift` : filtrage côté client, ne stream que les events matching
- [ ] T087 [US3] Gérer dans `Sources/roadie/main.swift` la déconnexion gracieuse : Ctrl+C ferme proprement, exit 0 ; daemon mort exit 3 (voir contracts)

### Tests US3

- [ ] T090 [P] [US3] Créer `Tests/RoadieCoreTests/desktop/EventBusTests.swift` : test publish→subscribe livraison ordonnée, multi-subscribers reçoivent tous les events, format JSON conforme contracts
- [ ] T091 [US3] Étendre `tests/integration/06-multi-desktop-switch.sh` : lancer `roadie events --follow > /tmp/events.log &` en background, faire 5 switches, asserter 5 lignes `desktop_changed` dans le log avec timestamps croissants

**Checkpoint US3** : SketchyBar / menu bar custom peut consommer le flux et afficher en temps réel le desktop+stage courant.

---

## Phase 6 — User Story 4 (P2) : Configuration par desktop

**Goal** : règles `[[desktops]]` dans `roadies.toml` appliquent un layout/gaps/default-stage spécifiques à chaque desktop.

**Independent Test** : déclarer `[[desktops]] label = "présentation" gaps_outer = 60`, focus desktop "présentation", visuellement les marges sont 60px.

### Implémentation

- [ ] T100 [US4] Implémenter dans `Sources/RoadieCore/desktop/DesktopState.swift` la résolution des effective gaps : `effectiveGaps(global: OuterGaps, override: OuterGaps?) -> OuterGaps` (override remplace par champ, pas globalement)
- [ ] T101 [US4] Implémenter dans `Sources/RoadieCore/desktop/DesktopManager.swift` l'application d'une `DesktopRule` au premier accès à un desktop matching : pose `displayName` si `match_label`, applique `default_strategy`, `gaps_*`, `default_stage` initial
- [ ] T102 [US4] Étendre `Sources/RoadieTiler/LayoutEngine.swift` : passer `OuterGaps` per-desktop au lieu du global config dans `applyLayout()` (continuation de la signature `apply(rect:, outerGaps:, gapsInner:)` déjà ajoutée en SPEC-002)
- [ ] T103 [US4] Câbler dans `Sources/roadied/main.swift` : à chaque `onTransition`, lire `DesktopState.tilerStrategy` et instancier le bon `Tiler` (BSP/master-stack), passer les gaps effectifs au `LayoutEngine`

### Tests US4

- [ ] T108 [P] [US4] Étendre `Tests/RoadieCoreTests/desktop/DesktopStateTests.swift` : test `effectiveGaps` couvrant override total, override partiel (top seul), pas d'override
- [ ] T109 [US4] Test manuel documenté dans `quickstart.md` (déjà présent) : configurer 2 desktops avec gaps différents, vérifier visuellement

**Checkpoint US4** : personnalisation par desktop fonctionnelle, transposable des Hyprland workspace rules à minima.

---

## Phase 7 — Polish & cross-cutting

- [ ] T120 Reload à chaud de la config dans `Sources/roadied/CommandRouter.swift` handler `daemon.reload` : appliquer les nouveaux `[multi_desktop]` et `[[desktops]]` sans redémarrer le daemon, y compris activer/désactiver `enabled` dynamiquement (FR-019)
- [ ] T121 [P] Logs structurés `desktop_changed` dans `daemon.log` au format `[YYYY-MM-DD HH:MM:SS.mmm] desktop_changed from=<uuid> to=<uuid> latency_ms=<n>` (cohérent avec V1, utile troubleshooting)
- [ ] T122 [P] Documenter dans `quickstart.md` la procédure rollback V2→V1 (déjà présente, vérifier exactitude des commandes)
- [ ] T123 [P] Ajouter dans `~/.config/roadies/roadies.toml` exemple commenté section `[multi_desktop]` et `[[desktops]]` (template uniquement, pas activé)
- [ ] T124 Test de robustesse : tuer SIGTERM le daemon en plein switch desktop, redémarrer, vérifier qu'aucun fichier `~/.config/roadies/desktops/*.toml.tmp` n'est laissé (atomicité préservée)
- [ ] T125 [P] Test de fumée 24h documenté : script `tests/integration/08-multi-desktop-soak.sh` qui simule 50+ transitions sur 1h via osascript, asserte 0 crash (SC-009 partiel)
- [ ] T125b [P] Test de fidélité 100 cycles : script `tests/integration/09-multi-desktop-roundtrip.sh` — créer 2 stages avec 3 fenêtres chacun sur desktop A, basculer 100 fois A↔B via osascript, asserter à chaque retour sur A que les 3 frames sont à ±2px et que stage actif est identique (couvre SC-002)
- [ ] T125c [P] Test de non-régression V1 : script `tests/integration/10-v1-shortcuts-intact.sh` — avec `multi_desktop.enabled=false`, asserter que les 13 raccourcis BTT existants (focus HJKL, move HJKL, restart, ⌥1/⌥2 switch+assign) répondent comme en V1, pas de référence implicite à un desktop courant (couvre FR-022)
- [ ] T126 Mesurer LOC ajoutées V2 : `find Sources/RoadieCore/desktop Tests/RoadieCoreTests/desktop -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` + extensions diff vs main, vérifier ≤ 800 effectives (SC-008)
- [ ] T127 [P] Mettre à jour `README.md` racine projet : ajouter section "Multi-desktop V2" pointant vers `quickstart.md`
- [ ] T128 Mettre à jour `implementation.md` final avec REX (Phase 10 SpecKit) — bilan tâches, difficultés, recommandations

---

## Dependencies

**Sequential phases** :
1. Phase 1 (Setup) → bloque tout
2. Phase 2 (Foundational) → bloque toutes les user stories
3. Phase 3 (US1) = MVP V2 → libre
4. Phase 4 (US2) → dépend de Phase 3 (CLI consomme `DesktopManager`)
5. Phase 5 (US3) → dépend de Phase 3 (events émis depuis DesktopManager + StageManager)
6. Phase 6 (US4) → dépend de Phase 3 (config par desktop appliquée au switch)
7. Phase 7 (Polish) → après toutes les US

**Parallel opportunities** intra-phase :
- T003 / T004 / T005 (Phase 1) : 3 fichiers indépendants
- T013 / T015 (Phase 2) : DesktopInfo + MockDesktopProvider, pas de dépendance
- T045 / T046 / T047 (US1 tests) : 3 fichiers de test différents
- T075 (US2 tests) parallélisable avec T076
- T090 / T091 (US3 tests) parallélisables
- T108 (US4 tests) parallélisable avec T109
- T121 / T122 / T123 / T125 / T127 (Phase 7) : tous fichiers différents, paralllélisables

---

## Implementation Strategy

**MVP V2 = Phase 1 + Phase 2 + Phase 3 (US1) + tests US1 + minimum Phase 7 (T120, T126).**

Cela suffit à livrer la promesse multi-desktop : suivre automatiquement le desktop courant, persister par UUID, migration V1→V2. Les phases 4 (CLI), 5 (events) et 6 (config par desktop) sont des incréments **livrables séparément** sans casser le MVP.

**Ordre recommandé d'exécution** :
1. Setup + Foundational (T001-T023) — 23 tâches
2. US1 implémentation + tests (T030-T049) — 18 tâches → **🎯 MVP V2 livrable**
3. US2 (T060-T076) — 12 tâches → CLI complète
4. US3 (T080-T091) — 10 tâches → events stream
5. US4 (T100-T109) — 7 tâches → config par desktop
6. Polish (T120-T128) — 9 tâches

**Total : 81 tâches**, dont 18 parallélisables `[P]`.

---

## Independent Testability per User Story

| US | Test indépendant | Critère pass |
|---|---|---|
| US1 | Bascule desktop 1↔2 avec stages distincts | `roadie stage list` change, latence < 200 ms, restauration fidèle |
| US2 | `roadie desktop list/focus/current/label/back` | 5 commandes répondent correctement, codes exit conformes |
| US3 | `roadie events --follow` + bascule | event JSON apparaît dans flux, format conforme contracts |
| US4 | 2 desktops avec gaps différents | gaps visuels appliqués au switch, sans redémarrage |

---

## Format validation (auto-check)

✅ Toutes les tâches commencent par `- [ ] T<nnn>`
✅ Phases user stories incluent `[USk]`
✅ Setup / Foundational / Polish n'incluent pas `[USk]`
✅ Chemins fichiers explicites pour chaque tâche d'implémentation
✅ `[P]` posé uniquement sur tâches indépendantes (fichier différent, pas de dépendance live)
