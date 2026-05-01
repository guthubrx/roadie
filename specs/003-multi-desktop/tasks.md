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

- [x] T001 Créer dossier `Sources/RoadieCore/desktop/` pour grouper les nouveaux modules de la couche desktop
- [x] T002 Créer dossier `Tests/RoadieCoreTests/desktop/` pour les tests unitaires de la couche desktop
- [x] T003 [P] Créer `tests/integration/06-multi-desktop-switch.sh` (squelette exécutable, exit 0 placeholder, droits +x)
- [x] T004 [P] Créer `tests/integration/07-multi-desktop-migration.sh` (squelette exécutable, droits +x)
- [x] T005 Mettre à jour `Package.swift` : aucune nouvelle dépendance, vérifier que SkyLight reste linké dans `RoadieCore` (déjà OK V1, juste un check explicite)

---

## Phase 2 — Foundational (prerequisites pour TOUTES les user stories)

**⚠️ Ces tâches DOIVENT être complétées avant toute Phase 3+. Aucun [US] car partagé.**

- [x] T010 Étendre `Sources/RoadieCore/PrivateAPI.swift` : ajouter bindings `@_silgen_name` pour `CGSGetActiveSpace(cid: CGSConnectionID) -> CGSSpaceID` et `CGSCopyManagedDisplaySpaces(cid: CGSConnectionID) -> CFArray?`
- [x] T011 Définir le type `CGSSpaceID = UInt64` et `CGSConnectionID = Int32` dans `Sources/RoadieCore/PrivateAPI.swift` (alias publics)
- [x] T012 Créer `Sources/RoadieCore/desktop/DesktopProvider.swift` : protocole `DesktopProvider` avec méthodes `currentDesktopUUID() -> String?`, `listDesktops() -> [DesktopInfo]`, `requestFocus(uuid: String)` (async fire-and-forget pour basculer via SkyLight)
- [x] T013 [P] Créer `Sources/RoadieCore/desktop/DesktopInfo.swift` : struct `DesktopInfo { uuid: String; index: Int; label: String? }` (Equatable, Sendable)
- [x] T014 Implémenter `Sources/RoadieCore/desktop/SkyLightDesktopProvider.swift` : implémentation prod du protocole, cross-référence `CGSGetActiveSpace` ↔ `CGSCopyManagedDisplaySpaces` pour récupérer l'UUID actif
- [x] T015 [P] Créer `Sources/RoadieCore/desktop/MockDesktopProvider.swift` : implémentation test scriptable (séquence de transitions injectables)
- [x] T016 Créer `Sources/RoadieCore/desktop/DesktopState.swift` : struct `DesktopState` avec champs (`desktopUUID`, `displayName?`, `tilerStrategy`, `currentStageID?`, `version`, `gapsOverride?`, `stages: [PersistedStage]`) — TreeNode reconstruit en mémoire (pattern V1)
- [x] T017 Implémenter sérialisation TOML de `DesktopState` (encode/decode via TOMLKit déjà présent V1) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [x] T018 Implémenter écriture atomique `DesktopState.write(to: URL)` (fichier `.tmp` + `rename`) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [x] T019 Implémenter lecture `DesktopState.read(from: URL)` avec validation (uuid non vide, currentStageID référencé) dans `Sources/RoadieCore/desktop/DesktopState.swift`
- [x] T020 Étendre `Sources/RoadieCore/Config.swift` : ajouter section `[multi_desktop]` avec champs `enabled: Bool` (défaut `false`) et `back_and_forth: Bool` (défaut `true`)
- [x] T021 Étendre `Sources/RoadieCore/Config.swift` : ajouter section `[[desktops]]` répétable parsée en `[DesktopRule]` (champs `match_index: Int?`, `match_label: String?`, `default_strategy?`, `gaps_*?`, `default_stage?`)
- [x] T022 Valider la config dans `Sources/RoadieCore/Config.swift` : règle DesktopRule doit avoir au moins un de `match_index` ou `match_label`, jamais les deux ; rejeter au reload sinon
- [x] T023 Étendre `Sources/RoadieCore/WindowRegistry.swift` (en réalité Types.swift où vit WindowState) : ajouter champ `desktopUUID: String?` à `WindowState`, défaut `nil` au boot, mis à jour lors des transitions

---

## Phase 3 — User Story 1 (P1) 🎯 MVP V2 : Suivre automatiquement le desktop courant

**Goal** : quand l'utilisateur bascule de desktop macOS, roadie sauvegarde l'état du desktop quitté, charge celui d'arrivée, en moins de 200 ms.

**Independent Test** : 2 desktops macOS configurés, 2 stages distincts par desktop ; bascule via Ctrl+→ ; `roadie stage list` change de contenu et `roadie stage 1` n'active que le stage du desktop courant.

### Implémentation

- [x] T030 [US1] Créer `Sources/RoadieCore/desktop/DesktopManager.swift` : `@MainActor` final class avec dépendance injectée `DesktopProvider`, état interne `currentUUID: String?`, `recentUUID: String?`
- [x] T031 [US1] Implémenter dans `Sources/RoadieCore/desktop/DesktopManager.swift` la subscription à `NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification)` (lifecycle géré par DesktopManager via observerToken + deinit)
- [x] T032 [US1] Implémenter méthode `DesktopManager.handleSpaceChange()` : récupère nouvel UUID via `provider.currentDesktopUUID()`, si différent de `currentUUID` déclenche `onTransition(from:to:)`
- [x] T033 [US1] Définir hook `DesktopManager.onTransition: DesktopTransitionHandler?` injecté par `roadied/main.swift` pour câbler save+load
- [x] T034 [US1] `DesktopState.path(for: uuid)` retourne `~/.config/roadies/desktops/<uuid>.toml` (déjà implémenté en Phase 2 T016-T019)
- [x] T035 [US1] `StageManager.reload(stagesDir:)` dans `Sources/RoadieStagePlugin/StageManager.swift` : sauve frames courantes, reset, swap path, reload (approche : 1 seul StageManager dont le path est swappé au switch — empreinte mémoire constante, cf. research.md décision 3)
- [x] T036 [US1] Mode V1 préservé via if/else dans `roadied/main.swift.bootstrap()` : si `multi_desktop.enabled == false`, `stageManager.loadFromDisk()` global comme avant (kill switch effectif FR-020)
- [x] T037 [US1] Câblé dans `Sources/roadied/main.swift` : instancie `DesktopManager` si `multi_desktop.enabled == true`, branche `onTransition` qui fait `registry.applyDesktopUUID(to)` + `sm.reload(stagesDir: desktops/<uuid>/stages)` + `applyLayout()`
- [x] T038 [US1] `DesktopState.empty(uuid:, defaultStage:)` (déjà implémenté en Phase 2 T016-T019)
- [x] T039 [US1] `WindowRegistry.applyDesktopUUID(_:)` ajoutée : marque `desktopUUID = uuid` pour toutes les fenêtres dans le registry au moment de la transition (FR-007 + data-model)
- [x] T040 [US1] Migration V1→V2 dans `Sources/RoadieCore/desktop/Migration.swift` (helper `DesktopMigration.runIfNeeded`) appelée depuis `roadied/main.swift.bootstrap()` au démarrage V2 (FR-023)
- [x] T041 [US1] Compteur de latence dans `DesktopManager.handleSpaceChange()` : mesure du délai début→fin onTransition, log warn si > 200 ms (couvre SC-001)

### Tests US1

- [x] T045 [P] [US1] `Tests/RoadieCoreTests/desktop/DesktopManagerTests.swift` (6 tests) : initial transition with from=nil, user transition A→B, resolveSelector basic, resolveSelector by label, back-and-forth, focus delegation
- [x] T046 [P] [US1] `Tests/RoadieCoreTests/desktop/DesktopStateTests.swift` (9 tests) : round-trip TOML, atomic write (pas de .tmp résiduel), validation 3 cas (uuid vide, currentStageID inconnu, accept stages vides), empty factory, path, gaps resolve partial+full
- [x] T047 [P] [US1] `Tests/RoadieCoreTests/desktop/MigrationTests.swift` (1 test) : runIfNeeded no-op safe (la migration utilise des chemins en dur ~/.config/... — vrais déplacements testés via T049 shell)
- [x] T048 [US1] `tests/integration/06-multi-desktop-switch.sh` complet : osascript Ctrl+→/←, mesure latence avec timestamps Python ms, assertion < 250 ms (avec marge sleep), assertion uuid changé (validation runtime sur machine setup utilisateur)
- [x] T049 [US1] `tests/integration/07-multi-desktop-migration.sh` complet : sandbox HOME tmpdir, faux state V1 main+work+active.toml, lance roadied avec HOME override, asserte backup horodaté + desktops/<uuid>/stages/* + suppression V1

**Checkpoint US1** : un utilisateur peut activer V2, créer 2 stages sur desktop 1, basculer sur desktop 2, créer 1 stage différent, revenir sur desktop 1, retrouver ses 2 stages exacts. MVP V2 livrable.

---

## Phase 4 — User Story 2 (P1) : CLI desktop

**Goal** : commandes `roadie desktop list/focus/current/label/back` opérationnelles.

**Independent Test** : `roadie desktop list` affiche le tableau, `roadie desktop label dev` puis `roadie desktop focus dev` ramène sur le bon desktop.

### Implémentation

- [x] T060 [US2] Handler `desktop.list` dans `Sources/roadied/CommandRouter.swift` : JSON `{current_uuid, desktops: [{index, uuid, label, stage_count, window_count}]}` ; lecture seule autorisée même quand `multi_desktop.enabled = false`
- [x] T061 [US2] Handler `desktop.current` : retourne uuid, index, label, current_stage_id, stage_count, window_count, tiler_strategy
- [x] T062 [US2] Handler `desktop.focus` : valide selector via `DesktopManager.resolveSelector`, délègue à `provider.requestFocus(uuid:)`
- [x] T063 [US2] `DesktopManager.resolveSelector(_:)` : `prev|next|recent|first|last|N|<label>`, gère `back_and_forth` (déjà fait Phase 3 US1)
- [x] T064 [US2] Handler `desktop.label` : validation alphanumérique + `-_`, max 32 chars ; vide → retire ; persiste dans DesktopManager.labels
- [x] T065 [US2] Handler `desktop.back` : alias de `resolveSelector("recent")` + focus
- [x] T066 [US2] Verbe `desktop` côté CLI dans `Sources/roadie/main.swift` : list, focus <selector>, current, label <name>, back ; flag `--json`
- [x] T067 [US2] Codes d'exit dans `Sources/roadie/main.swift` : 0 succès, 2 invalid_argument, 3 daemon down, 4 multi_desktop_disabled, 5 unknown_desktop/stage/window
- [x] T068 [US2] Blocage commandes desktop si `multi_desktop.enabled == false` avec message "multi_desktop disabled, set enabled=true in roadies.toml" (sauf `desktop.list` lecture)
- [x] T069 [US2] Formattage texte `desktop list` aligné `INDEX  UUID  LABEL  CURRENT  STAGES  WINDOWS` dans `sendDesktopListAsTable`

### Tests US2

- [x] T075 [P] [US2] Tests resolveSelector dans `DesktopManagerTests.swift` (déjà couverts Phase 3 US1 — 6 tests : prev/next/recent/first/last/index/label/inconnu/back-and-forth)
- [x] T076 [US2] Section T076 dans `06-multi-desktop-switch.sh` : assertions `desktop list --json` (current_uuid + desktops[]), `focus next` change uuid, `label _test_audit_$$` + `focus _test_audit_$$` revient au bon desktop, cleanup label

**Checkpoint US2** : la grille CLI desktop est complète, scriptable, intégrable dans BTT.

---

## Phase 5 — User Story 3 (P2) : Stream d'événements

**Goal** : `roadie events --follow` push des événements JSON-lines à chaque transition desktop ou stage.

**Independent Test** : `roadie events --follow` en background, basculer un desktop, voir une ligne `desktop_changed` apparaître dans le flux en moins de 200 ms.

### Implémentation

- [x] T080 [US3] `EventBus` `@MainActor final class` dans `Sources/RoadieCore/desktop/EventBus.swift` : `publish(_:)` + `subscribe() -> AsyncStream<DesktopEvent>` + singleton `.shared`
- [x] T081 [US3] Struct `DesktopEvent` (name, ts, payload) avec `toJSONLine()` ISO8601 millisec UTC + champ commun `version: Int = 1`
- [x] T082 [US3] Émission `desktop_changed` depuis `DesktopManager.handleSpaceChange()` avec from/to/from_index/to_index/from_label/to_label
- [x] T083 [US3] Émission `stage_changed` depuis `StageManager.switchTo()` avec desktop_uuid/from/to/from_name/to_name (extrait UUID du stagesDir)
- [x] T084 [US3] Mode push dans `Sources/RoadieCore/Server.swift.processRequest` : intercepte `events.subscribe` avant le routing standard, send ack puis souscrit `EventBus` et push chaque event au fil de l'eau
- [x] T085 [US3] Verbe `events --follow` dans `Sources/roadie/main.swift` : connexion persistante, lecture buffer + processBuffer pour réassembler les lignes JSON, write stdout
- [x] T086 [US3] `--filter <event-name>` répétable : filtre côté client par parsing `event` field
- [x] T087 [US3] Déconnexion gracieuse : `signal(SIGINT/SIGTERM)` exit 0 ; `connection.cancelled` ou `failed` → exit 3 (daemon down)

### Tests US3

- [x] T090 [P] [US3] `Tests/RoadieCoreTests/desktop/EventBusTests.swift` (5 tests) : JSON line conforme contracts, single subscriber delivery, multi-subscribers, ordre préservé, singleton shared
- [x] T091 [US3] Section T091 dans `06-multi-desktop-switch.sh` : `roadie events --follow --filter desktop_changed > /tmp/events.log &` + 5 switches + `grep -c '"event":"desktop_changed"' >= 5` + cleanup background

**Checkpoint US3** : SketchyBar / menu bar custom peut consommer le flux et afficher en temps réel le desktop+stage courant.

---

## Phase 6 — User Story 4 (P2) : Configuration par desktop

**Goal** : règles `[[desktops]]` dans `roadies.toml` appliquent un layout/gaps/default-stage spécifiques à chaque desktop.

**Independent Test** : déclarer `[[desktops]] label = "présentation" gaps_outer = 60`, focus desktop "présentation", visuellement les marges sont 60px.

### Implémentation

- [x] T100 [US4] `GapsOverride.resolve(over: OuterGaps) -> OuterGaps` dans `DesktopState.swift` (déjà fait Phase 2 T016-T019)
- [x] T101 [US4] `Daemon.applyDesktopRule(for: desktopUUID)` dans `roadied/main.swift` : matche par index OU label (mutuellement exclusif validé), applique `defaultStrategy` via `layoutEngine.setStrategy`, applique `gapsOverride` dans `currentDesktopGaps`, applique `defaultStage` initial via `sm.switchTo`
- [x] T102 [US4] `LayoutEngine.apply(rect:, outerGaps:, gapsInner:)` accepte déjà OuterGaps per-call (héritage SPEC-002, pas de modification nécessaire)
- [x] T103 [US4] Câblage dans `Daemon.onTransition` : appelle `applyDesktopRule(for: to)` avant `applyLayout()` ; `applyLayout()` utilise `currentDesktopGaps ?? config.tiling.effectiveOuterGaps`

### Tests US4

- [x] T108 [P] [US4] Tests `effectiveGaps` dans `DesktopStateTests.swift` (couverts Phase 3 US1 — `test_gapsOverride_resolvePartial` + `test_gapsOverride_resolveFull`)
- [x] T109 [US4] Test manuel documenté dans `quickstart.md` Test 4 — `[[desktops]]` rule avec gaps différents

**Checkpoint US4** : personnalisation par desktop fonctionnelle, transposable des Hyprland workspace rules à minima.

---

## Phase 7 — Polish & cross-cutting

- [x] T120 Reload à chaud `daemon.reload` étendu : `Daemon.reconfigureMultiDesktop(newConfig:)` active/désactive `DesktopManager` à chaud + valide les `[[desktops]]` rules, met à jour `back_and_forth` (FR-019)
- [x] T121 [P] Logs structurés `desktop_changed` dans `DesktopManager.handleSpaceChange()` (`logDebug`/`logWarn` selon latence) avec from/to/ms — déjà actif en US1
- [x] T122 [P] Procédure rollback V2→V1 documentée dans `quickstart.md` Troubleshooting
- [x] T123 [P] `examples/roadies.toml.example` créé : config complète commentée avec sections `[multi_desktop]` (enabled+back_and_forth) et `[[desktops]]` (3 exemples : code/présentation/monitoring), à copier dans `~/.config/roadies/roadies.toml`
- [x] T124 Phase 2 dans `08-multi-desktop-soak.sh` : SIGTERM le daemon en plein switch (sleep 0.05 entre osascript et kill -TERM), assertion zéro `.tmp` résiduel dans `~/.config/roadies/desktops/`
- [x] T125 [P] Squelette `tests/integration/08-multi-desktop-soak.sh` (boucle 1h via osascript, vérification daemon vivant)
- [x] T125b [P] Squelette `tests/integration/09-multi-desktop-roundtrip.sh` (100 cycles A↔B, structure pour completion manuelle)
- [x] T125c [P] Squelette `tests/integration/10-v1-shortcuts-intact.sh` (vérifie exit codes V1 + multi_desktop disabled exit 4)
- [x] T126 Mesure LOC V2 : prod nouveau = 474, extensions V1 = 535, total prod = 1009 LOC (cible 800 légèrement dépassée mais cumul V1+V2 = ~3023 sous plafond strict 4000)
- [x] T127 [P] README.md racine étendu : section V2 multi-desktop ajoutée avec liens vers spec/plan/quickstart V2 + nouvelles commandes CLI
- [x] T128 Mise à jour `implementation.md` final avec REX V2

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
