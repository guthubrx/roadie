# Tasks — SPEC-011 Roadie Virtual Desktops

**Branch** : `011-virtual-desktops` | **Date** : 2026-05-02
**Plan** : [plan.md](./plan.md) | **Spec** : [spec.md](./spec.md)

Convention : `- [ ] T<nnn> [P?] [US<k>?] Description + chemin`. `[P]` = parallélisable (fichiers indépendants, pas de blocage). `[US<k>]` = associé à la User Story k.

---

## Phase 1 : Setup

Création du squelette module et suppression du code legacy SPEC-003.

- [x] T001 Créer le module SwiftPM `RoadieDesktops` : ajouter target dans `Package.swift` (type `library`, deps `RoadieCore`), créer dossier `Sources/RoadieDesktops/` avec un fichier vide `Module.swift`
- [x] T002 Créer le dossier de tests `Tests/RoadieDesktopsTests/` avec target SwiftPM associée dans `Package.swift`
- [x] T003 [P] Supprimer le dossier legacy SPEC-003 `Sources/RoadieCore/desktop/` (8 fichiers : DesktopInfo.swift, DesktopManager.swift, DesktopProvider.swift, DesktopState.swift, EventBus.swift, Migration.swift, MockDesktopProvider.swift, SkyLightDesktopProvider.swift) — référencé par R-010
- [x] T004 [P] Retirer `case .spaceFocus` (et son cas dans `toJSONObject()`) de `Sources/RoadieFXCore/OSAXCommand.swift` — ajouté en session précédente, jamais utilisé (R-010)
- [x] T005 [P] Retirer la déclaration `CGSManagedDisplaySetCurrentSpace` (et autres CGS spaces api) de `Sources/RoadieCore/PrivateAPI.swift` (FR-004)
- [x] T006 Nettoyer `Sources/roadied/CommandRouter.swift` : retirer toutes les références à `daemon.desktopManager`, `DaemonOSAXBridge.shared.send(.spaceFocus...)` et le fallback `dm.focus()` (à reconstruire en Phase 5)
- [x] T007 [P] Retirer `desktopManager` de `Sources/roadied/Daemon.swift` (ou équivalent) et toutes les références CGS associées — préparer pour réintroduction en Phase 5

---

## Phase 2 : Foundational

Briques de base bloquantes pour toutes les user stories : config, entités, parsing, EventBus, hook de manipulation de fenêtres.

- [x] T008 [P] Étendre `Sources/RoadieCore/Config.swift` : ajouter struct `DesktopsConfig` avec champs `enabled: Bool=true`, `count: Int=10`, `defaultFocus: Int=1`, `backAndForth: Bool=true`, `offscreenX: Int=-30000`, `offscreenY: Int=-30000`. Parser la section TOML `[desktops]` (R-011)
- [x] T009 [P] Ajouter test `Tests/RoadieCoreTests/ConfigDesktopsTests.swift` : parser un TOML d'exemple avec `[desktops]` et vérifier les valeurs (FR-018), tester rejet de `count = 0` et `count = 17` (FR-001)
- [x] T010 [P] Étendre `Sources/RoadieCore/WindowState.swift` (ou équivalent) avec champ `desktopID: Int` (default 1) et `expectedFrame: CGRect`. Mettre à jour `WindowRegistry` pour exposer un getter par desktopID
- [x] T011 [P] Créer `Sources/RoadieDesktops/DesktopState.swift` avec structs `RoadieDesktop`, `Stage`, `WindowEntry`, `Layout` (enum bsp/master_stack/floating). Conformes au schéma data-model.md (R-004)
- [x] T012 Créer `Sources/RoadieDesktops/Parser.swift` : sérialisation/désérialisation TOML pour `RoadieDesktop` (round-trip avec exemple data-model.md). Pas de dépendance externe — étendre le parseur ad-hoc existant ou l'adapter
- [x] T013 [P] Créer `Tests/RoadieDesktopsTests/ParserTests.swift` : round-trip parse(serialize(d)) == d sur 3 desktops d'exemple, plus tests de corruption (TOML invalide → throws)
- [x] T014 [P] Créer `Sources/RoadieDesktops/EventBus.swift` : actor `DesktopEventBus` avec `publish(event:)`, `subscribe() -> AsyncStream<Event>`, gestion des continuations multiples (R-007)
- [x] T015 [P] Créer `Tests/RoadieDesktopsTests/EventBusTests.swift` : 1 publisher + 2 subscribers reçoivent chacun l'event ; cleanup à la déconnexion ; latence < 50 ms
- [x] T016 Créer `Sources/RoadieDesktops/WindowMover.swift` : protocole + impl AX qui prend un `CGWindowID` et applique `setPosition(x, y)` via `AXUIElement.kAXPositionAttribute`. Utilise `_AXUIElementGetWindow` pour mapping AX↔CG (R-001, principe C constitution)

---

## Phase 3 : User Story 1 (P1) — Bascule instantanée

**Goal** : `roadie desktop focus N` déplace les fenêtres offscreen et restaure celles du desktop cible. C'est le cœur du pivot.

**Independent Test** : configurer 2 desktops avec des fenêtres aux positions distinctes, lancer `roadie desktop focus 2`, vérifier que les fenêtres du desktop 1 ont `frame.origin.x = -30000` et celles du desktop 2 sont à leur expectedFrame.

- [x] T017 [US1] Créer `Sources/RoadieDesktops/DesktopRegistry.swift` : actor avec dict `[Int: RoadieDesktop]`, `currentID`, `recentID`. Méthodes `load(from:)`, `save(_:)`, `setCurrent(id:)`, `desktop(id:)`. Implémenter persistance write-then-rename par desktop (FR-011). À la restauration, ignorer silencieusement les `cgwid` qui n'existent plus côté macOS sans bloquer (FR-024)
- [x] T018 [US1] Créer `Tests/RoadieDesktopsTests/DesktopRegistryTests.swift` : load/save round-trip ; setCurrent met à jour recentID ; load avec fichier corrompu logue warning + init vierge (FR-013)
- [x] T019 [US1] Créer `Sources/RoadieDesktops/DesktopSwitcher.swift` : actor avec `inFlight: Bool`, `pendingTarget: Int?`. Méthode `switch(to id: Int) async throws` qui : (1) valide range 1..count (FR-023), (2) hide windows of currentID via WindowMover, (3) show windows of N restorant expectedFrame, (4) registry.setCurrent(id: N), (5) bus.publish(desktop_changed) (FR-002, FR-006, R-003)
- [x] T020 [US1] Étendre DesktopSwitcher : implémenter back-and-forth — si `back_and_forth=true` et `target == currentID`, basculer vers `recentID` à la place (FR-006)
- [x] T021 [US1] Étendre DesktopSwitcher : implémenter no-op idempotent — si target == currentID et back_and_forth=false, return immédiat sans event (FR-006)
- [x] T022 [US1] Étendre DesktopSwitcher : implémenter queue collapsing — si `inFlight`, store `pendingTarget = N` et return ; à la fin de la bascule en cours, recurse vers `pendingTarget` si différent du courant (FR-025, R-003)
- [x] T023 [US1] Créer `Tests/RoadieDesktopsTests/DesktopSwitcherTests.swift` : test `testBasicSwitch` ; `testIdempotentNoop` ; `testBackAndForth` ; `testRangeCheck` (selector hors range → throws) ; `testRapidSwitchCollapsing` (3 switch enchaînés en 50 ms → seul le dernier appliqué)
- [x] T024 [US1] Câbler `Sources/roadied/CommandRouter.swift` : handler `desktop.focus` qui résout selector via `selectorResolve()`, appelle `DesktopSwitcher.switch(to:)`, retourne JSON {ok, current_id, previous_id, event_emitted}. Câbler aussi `desktop.list` qui retourne pour chaque desktop : id, label, current, recent, count fenêtres, count stages (FR-015), et `desktop.current` qui retourne id+label+active_stage_id (contrats/cli-desktop.md)
- [x] T025 [US1] Créer fonction `selectorResolve(_ s: String, registry:) -> Int?` dans `RoadieDesktops/Selector.swift` : gère `"1".."N"`, labels, `prev`/`next`/`recent`/`first`/`last`. Retourne nil si non résolu (contrats/cli-desktop.md)
- [x] T026 [US1] Étendre `Sources/roadie/main.swift` : sous-commande `desktop focus <selector>` qui pipe vers le daemon via socket Unix, exit 0/2 selon réponse
- [x] T027 [US1] Test perf manuel/auto `Tests/RoadieDesktopsTests/PerfTests.swift` : créer 10 fenêtres factices via `MockWindowMover`, mesurer `switch(to:)` < 200 ms p95 (FR-003, SC-001)
- [x] T028 [US1] Test ghost window `Tests/RoadieDesktopsTests/GhostTests.swift` : 100 bascules consécutives, vérifier que `windows on-screen` == `windows of currentDesktop` à chaque itération (SC-002)
- [x] T029 [US1] Test grep statique CI `Tests/StaticChecks/no-cgs.sh` (script shell) : `grep -lE 'CGS|SLS|SkyLight' Sources/RoadieDesktops/` doit retourner vide (SC-005, R-009)

**Checkpoint US1** : MVP fonctionnel. À ce stade : `roadie desktop focus N` marche, fenêtres bougent visuellement, tests verts.

---

## Phase 4 : User Story 2 (P1) — Stages préservés à l'identique

**Goal** : ⌥+1, ⌥+2 continuent à fonctionner sur les stages du desktop courant uniquement, aucune régression.

**Independent Test** : créer 2 stages sur desktop 1, basculer au desktop 2, créer 2 stages, vérifier que `roadie stage list` ne montre que les stages du desktop courant et que ⌥+1/⌥+2 n'affectent pas l'autre desktop.

- [x] T030 [US2] Modifier `Sources/RoadieStagePlugin/StageManager.swift` : injecter référence à `DesktopRegistry`, filtrer toutes les opérations (`list`, `focus`, `create`, `destroy`, `assign`) par `currentDesktopID` (FR-009)
- [x] T031 [US2] Étendre `StageManager` : à chaque `desktop_changed`, sauvegarder l'état stages du desktop quitté et charger celui du desktop d'arrivée. Restaurer `active_stage_id` du desktop d'arrivée (R-008, FR-008)
- [x] T032 [US2] Migrer la persistance des stages : depuis `~/.config/roadies/stages/N.toml` vers tableau `[[stages]]` dans `~/.config/roadies/desktops/<id>/state.toml` (R-008)
- [x] T033 [US2] Tests `Tests/RoadieStagePluginTests/StageManagerDesktopScopeTests.swift` : 2 desktops avec stages distincts, vérifier que `list` ne retourne que les stages du desktop courant ; switch desktop fait basculer correctement les stages (FR-009, SC-003)
- [x] T034 [US2] Re-runner la suite stages V1 existante (si elle existe) : aucune régression (SC-003). Si suite absente, écrire un test E2E minimal (créer stage, ajouter fenêtre, focus stage, vérifier visibilité). Vérifier que les raccourcis BTT existants (⌥+1, ⌥+2) appellent toujours `roadie stage focus` et que le résultat est limité au desktop courant (FR-010)

**Checkpoint US2** : 0 régression V1, stages V2 fonctionnels per-desktop.

---

## Phase 5 : User Story 3 (P1) — État persisté par desktop

**Goal** : redémarrage daemon → desktops, fenêtres, stages, layouts intégralement restaurés.

**Independent Test** : config 2 desktops avec contenu, kill daemon, relance, vérifier `roadie desktop list` identique et fenêtres physiquement restaurées au focus du desktop courant.

- [x] T035 [US3] Étendre `DesktopRegistry.save(_:)` : write-then-rename atomique sur `~/.config/roadies/desktops/<id>/state.toml`. Appelée après chaque mutation (bascule, label, assign window, stage change) (FR-011)
- [x] T036 [US3] Au boot daemon (`Daemon.start()` ou équivalent dans `Sources/roadied/main.swift`) : `DesktopRegistry.load()` itère sur `~/.config/roadies/desktops/<id>/` pour i in 1..count, charge ou init vierge en cas d'absence (FR-012)
- [x] T037 [US3] Si state corrompu pour un desktop (parsing throw), logger warning structuré et init vierge pour ce desktop, sans bloquer le boot (FR-013)
- [x] T038 [US3] Restaurer `currentID` au boot : utiliser le dernier `currentID` persisté ou `defaultFocus` config si absent. Effectuer la bascule visuelle (show windows of currentID) avant la première commande utilisateur (FR-012)
- [x] T039 [US3] Tests `Tests/RoadieDesktopsTests/PersistenceTests.swift` : kill simulé du registry, recharge, vérifier full restoration positions/labels/stages/layout (SC-006)
- [x] T040 [US3] Test corruption `Tests/RoadieDesktopsTests/CorruptionRecoveryTests.swift` : injecter un fichier state.toml invalide, boot, vérifier desktop concerné = vierge, autres intacts, warning loggé

**Checkpoint US3** : MVP final P1. Bascule + stages + persistance fonctionnels et stables.

---

## Phase 6 : User Story 4 (P2) — Labels

**Goal** : labeliser les desktops et basculer par nom.

**Independent Test** : `roadie desktop label code`, puis `roadie desktop focus code` bascule vers ce desktop.

- [x] T041 [P] [US4] Ajouter validation label dans `Sources/RoadieDesktops/Validation.swift` : regex `^[a-zA-Z0-9_-]{0,32}$` + liste des labels réservés (`prev`, `next`, `recent`, `first`, `last`, `current`)
- [x] T042 [US4] Étendre `RoadieDesktop.label` getter/setter dans Registry, persistance immédiate après modification
- [x] T043 [US4] Câbler handler `desktop.label` dans `Sources/roadied/CommandRouter.swift` : args `name`, validation, set ou unset (vide → nil), retour JSON
- [x] T044 [US4] Étendre `selectorResolve` : si selector ne matche pas un int, chercher dans les labels des desktops (insensitive case ? non, case-sensitive simple)
- [x] T045 [US4] Étendre `Sources/roadie/main.swift` : sous-commande `desktop label <name>` (vide retire)
- [x] T046 [P] [US4] Tests `Tests/RoadieDesktopsTests/LabelTests.swift` : label valide accepté, invalide rejeté, label réservé rejeté, focus par label fonctionne, retrait label vide

**Checkpoint US4** : labels et selection par nom opérationnels.

---

## Phase 7 : User Story 5 (P2) — Stream events

**Goal** : `roadie events --follow` streame les transitions en JSON-lines.

**Independent Test** : lancer le subscriber, déclencher 3 bascules, vérifier 3 lignes JSON correctes en moins de 50 ms chacune.

- [x] T047 [US5] Câbler `DesktopEventBus.publish` dans `DesktopSwitcher.switch` : émission `desktop_changed` après mutation, jamais sur no-op (contrats/events-stream.md)
- [x] T048 [US5] Câbler émission `stage_changed` dans `StageManager` après chaque bascule de stage
- [x] T049 [US5] Handler `events.subscribe` dans `Sources/roadied/CommandRouter.swift` : ouvre une long-poll, écrit chaque event sur le socket en JSON-line, gère cleanup à la déconnexion (max 16 subscribers concurrents)
- [x] T050 [US5] Sous-commande `roadie events --follow [--types T1,T2]` dans `Sources/roadie/main.swift` : ouvre socket, lit en stream, écrit sur stdout, exit 0 sur SIGINT
- [x] T051 [P] [US5] Tests `Tests/RoadieDesktopsTests/EventStreamTests.swift` : subscribe + bascule → event reçu en moins de 50 ms (SC-007) ; filtre `--types` respecté ; cleanup propre à la déconnexion

**Checkpoint US5** : intégrations menu bar (SketchyBar) opérationnelles.

---

## Phase 8 : User Story 6 (P2) — Migration V1 et SPEC-003

**Goal** : utilisateur V1 démarre la nouvelle version, retrouve son environnement.

**Independent Test** : prendre un dossier `~/.config/roadies/stages/` V1 existant, premier boot V2, vérifier que tous les stages et fenêtres sont mappés sur desktop 1 sans intervention.

- [x] T052 [US6] Créer `Sources/RoadieDesktops/Migration.swift` : fonction `migrateV1ToV2(stagesDir:desktopsDir:)` qui lit les fichiers V1 et écrit `desktops/1/state.toml` (R-005, FR-021)
- [x] T053 [US6] Détecter SPEC-003 : si `~/.config/roadies/desktops/<UUID>/` existe (UUID = 36 chars hex), renommer en `.archived-spec003-<UUID>/` et logger warning (R-006, FR-022)
- [x] T054 [US6] Au boot daemon : si `desktops/` vide ET `stages/` non vide, appeler `migrateV1ToV2()`. Conserver `stages/` read-only pour rollback 1 release (R-005)
- [x] T055 [P] [US6] Tests `Tests/RoadieDesktopsTests/MigrationTests.swift` : fixtures V1 + run migration → state desktop 1 correct, 0 fenêtre perdue (SC-004) ; fixtures SPEC-003 → archive correcte ; idempotence (2e boot ne refait pas la migration)

**Checkpoint US6** : utilisateurs V1 migrent sans friction.

---

## Phase 9 : User Story 7 (P3) — Désactivation opt-out

**Goal** : `[desktops] enabled = false` rend roadie strictement V1.

**Independent Test** : poser `enabled=false`, redémarrer, `roadie desktop focus 2` retourne erreur claire ; `roadie stage list` continue de fonctionner.

- [x] T056 [US7] Au boot, si `config.desktops.enabled == false`, ne pas instancier `DesktopSwitcher` ni câbler les handlers `desktop.*`. Conserver un `DesktopRegistry` minimal en mémoire avec un unique desktop id=1 (sans persistance per-desktop), pour que `StageManager` continue d'avoir un `currentDesktopID` cohérent et que `stage.*` fonctionne sans filtre observable (FR-020). Aucune fenêtre n'est jamais déplacée offscreen dans ce mode
- [x] T057 [US7] Dans `CommandRouter`, si feature désactivée, court-circuiter tous les handlers `desktop.*` avec erreur `multi_desktop_disabled` + message explicite (FR-020)
- [x] T058 [US7] Vérifier que `stage.*` continue de fonctionner sur l'unique desktop (FR-020)
- [x] T059 [P] [US7] Test `Tests/RoadieDesktopsTests/DisabledTests.swift` : config enabled=false, desktop.focus retourne erreur ; stage.list fonctionne

**Checkpoint US7** : feature toggle propre.

---

## Phase 10 : Polish & Cross-Cutting

- [x] T060 [P] Vérifier compteur LOC effectif `find Sources/RoadieDesktops -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` < 900 (plafond plan.md)
- [x] T061 [P] Vérifier taille binaire `roadied` < 5 MB après build release (constitution gate)
- [x] T062 [P] Re-run grep statique no-CGS sur `Sources/RoadieDesktops/` (SC-005)
- [x] T063 [P] Mettre à jour `README.md` (≤ 200 mots) : explication pivot + recommandation "désactiver Displays have separate Spaces" (SC-010)
- [x] T064 [P] Mettre à jour `CHANGELOG.md` ou équivalent : entrée V2-pivot, mention SPEC-003 deprecated, lien vers SPEC-011
- [x] T065 Re-runner toute la suite de tests `swift test` : tous verts
- [x] T066 Mesurer perf manuelle SC-001 : avec 10 fenêtres ouvertes, `time roadie desktop focus 2` < 200 ms p95 (10 mesures min)
- [x] T067 Vérifier qu'aucune ancienne référence à `desktopManager`, `SkyLight*Provider`, `CGSManagedDisplaySetCurrentSpace`, `OSAXCommand.spaceFocus` ne subsiste : `git grep` doit retourner vide (R-010)
- [x] T068 Mettre à jour `quickstart.md` si découvertes pendant l'implémentation (ajustements troubleshooting)
- [x] T069 Marquer SPEC-007 si elle existe et chevauche avec SPEC-011 : statut DEPRECATED ou clarification de scope

---

## Dependencies & Story Order

```
Phase 1 (Setup) ──┐
                  ▼
Phase 2 (Foundational) ──┐
                          ▼
Phase 3 (US1 P1) ─────► Phase 6 (US4 P2)
        │                     │
        ▼                     ▼
Phase 4 (US2 P1) ◄── déps Registry du US1
        │
        ▼
Phase 5 (US3 P1)
        │
        ├────────► Phase 7 (US5 P2)
        │
        └────────► Phase 8 (US6 P2) ────► Phase 9 (US7 P3)
                              │
                              ▼
                       Phase 10 (Polish)
```

- **MVP minimal** : Phases 1+2+3+4+5 (US1+US2+US3 = les 3 P1).
- **Release V2 complète** : MVP + US4+US5+US6 (P2).
- **Optionnel** : US7 (P3, opt-out).

## Parallelization Examples

**Phase 1 (setup)** : T003 + T004 + T005 + T007 en parallèle (suppression code legacy, fichiers indépendants).

**Phase 2 (foundational)** : T008 + T010 + T011 + T014 + T016 en parallèle (5 fichiers indépendants).

**Phase 3 (US1)** : T017 (registry) doit précéder T019 (switcher). Mais T024 (router) + T025 (selector) + T026 (CLI) parallélisables une fois le switcher prêt.

**Phase 6 (US4)** : T041 + T046 en parallèle dès que registry/switcher prêts.

**Phase 10 (polish)** : T060 + T061 + T062 + T063 + T064 + T067 + T068 tous parallèles.

## Implementation Strategy

1. **Sprint 1 — MVP P1** : Phases 1 → 5. Bascule + stages + persistance. Demo possible.
2. **Sprint 2 — Adoption** : Phase 6 (labels) + Phase 8 (migration V1). Utilisateurs V1 peuvent migrer sans friction.
3. **Sprint 3 — Intégrations** : Phase 7 (events stream). SketchyBar et menu bars custom.
4. **Sprint 4 — Polish** : Phase 9 (opt-out) + Phase 10 (cross-cutting). Release V2 finale.

À chaque sprint, audit `/audit` mode fix sur le scope ajouté pour valider qualité.
