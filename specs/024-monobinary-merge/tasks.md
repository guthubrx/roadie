---
description: "Task list — SPEC-024 Migration mono-binaire (fusion roadied + roadie-rail)"
---

# Tasks: Migration mono-binaire (fusion roadied + roadie-rail)

**Input** : Design documents from `/specs/024-monobinary-merge/`
**Prerequisites** : plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests** : Tests inclus là où ils sont mentionnés explicitement dans la spec (Article H' constitution-002 : pyramide unitaire + intégration + acceptation manuelle). Pas de TDD strict imposé.

**Organization** : tâches groupées par user story pour livraison incrémentale. US1+US2+US4 partagent largement la même infrastructure (refactor Package.swift, fusion lifecycle), US3 et US5 sont en aval.

## Format: `[ID] [P?] [Story] Description`

- **[P]** : peut tourner en parallèle (fichiers différents, pas de dépendance bloquante)
- **[Story]** : user story rattachée (US1, US2, US3, US4, US5)
- Chemins absolus depuis la racine repo

## Path Conventions

- Single project — Swift Package Manager
- Sources : `Sources/<module>/`
- Tests : `Tests/<module>Tests/`
- Scripts : `scripts/`

---

## Phase 1: Setup (infrastructure partagée)

**Purpose** : préparer le terrain technique avant toute migration de logique.

- [ ] T001 Créer une branche de sauvegarde `pre-024-baseline` depuis HEAD pour rollback éventuel : `git branch pre-024-baseline 024-monobinary-merge~0`
- [ ] T002 Capturer la baseline LOC : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` et écrire le résultat dans `specs/024-monobinary-merge/loc-baseline.txt`
- [ ] T003 [P] Capturer un snapshot des sorties CLI publiques pour comparaison post-migration (FR-008, SC-004) : exécuter `roadie stage list --json`, `roadie desktop list --json`, `roadie display list --json`, `roadie daemon status --json` et sauvegarder dans `specs/024-monobinary-merge/snapshots/cli-v1/`
- [ ] T004 [P] Capturer un snapshot d'events (10 secondes) via `timeout 10 roadie events --follow > specs/024-monobinary-merge/snapshots/events-v1.jsonl` après avoir déclenché manuellement quelques actions

---

## Phase 2: Foundational — EventBus interne (BLOQUANT pour toutes les US)

**Purpose** : étendre le bus d'événements existant pour qu'il porte tous les events nécessaires au rail in-process. Sans ce socle, US3 (cohérence) et US1 (refactor RailController) ne peuvent pas démarrer.

- [ ] T010 Créer le type `RoadieEvent` enum (Sendable) couvrant `stageChanged`, `desktopChanged`, `windowCreated/Destroyed/Focused/Assigned/Unassigned`, `stageCreated/Deleted/Renamed`, `displayConfigurationChanged`, `thumbnailUpdated`, `configReloaded`, dans `Sources/RoadieCore/RoadieEvent.swift`
- [ ] T011 Créer ou étendre le bus dans `Sources/RoadieCore/RoadieEventBus.swift` (actor avec AsyncStream, méthodes `publish(_:)`, `subscribe()`, `subscriberCount`). Si `DesktopEventBus` peut être généralisé sans LOC excessive (≤ +30 LOC), le faire ; sinon créer un bus parallèle dédié et déprécier progressivement `DesktopEventBus`.
- [ ] T012 [P] Tests unitaires `RoadieEventBus` dans `Tests/RoadieCoreTests/RoadieEventBusTests.swift` : `testPublishToMultipleSubscribers`, `testSubscriberCancellationCleansUp`, `testEventOrderPreserved` (3 tests minimum, conformément à `contracts/eventbus-internal.md`)
- [ ] T013 Brancher les producteurs existants au nouveau bus :
  - `StageManager` (RoadieStagePlugin/StageManager.swift) → publie sur stageChanged/Created/Deleted/Renamed, windowAssigned/Unassigned
  - `DesktopRegistry` (RoadieDesktops/DesktopRegistry.swift) → publie desktopChanged
  - `GlobalObserver` (RoadieCore) → windowCreated/Destroyed/Focused
  - `ScreenObserver` (RoadieCore) → displayConfigurationChanged
  - `ThumbnailCache` → thumbnailUpdated
  - Hook config reload existant → configReloaded
- [ ] T014 Refactor `IPCServer.eventForwarder` (RoadieCore/Server.swift) : devient un subscriber du bus unifié, sérialise chaque `RoadieEvent` en JSON-line selon le schéma figé (cf. `contracts/ipc-public-frozen.md`). Vérifier non-régression du flux `events --follow`.
- [ ] T015 Ajouter au démarrage du `Daemon.bootstrap()` (après le bloc Accessibility) un check **log-only** des permissions Screen Recording : appeler `CGPreflightScreenCaptureAccess()` (jamais `CGRequestScreenCaptureAccess()` depuis ce contexte launchd, cf. crash observé) et émettre un log JSON-lines `{"level": "info|warn", "msg": "screen_capture_state", "granted": true|false}`. Si denied : message stderr clair pointant vers Réglages Système. Cf. FR-015.

**Checkpoint** : Foundational terminé quand `T010-T015` passent + tests T012 verts + `roadie events --follow` continue à émettre les events au format identique à V1 (vérifié contre snapshot T004) + T015 logue l'état de Screen Recording au boot.

---

## Phase 3: US1 — Installation simplifiée (Priority: P1) 🎯 MVP

**Story Goal** : un seul binaire `roadied` distribué, une seule entrée TCC par catégorie, expérience installation utilisateur claire et minimale.

**Independent Test** : sur une machine TCC reset, installer V2 et vérifier qu'il n'y a qu'une seule entrée "roadied" dans Réglages Système → Accessibilité ET → Enregistrement d'écran (SC-001).

- [ ] T020 [US1] Modifier `Package.swift` : retirer le product `executable(name: "roadie-rail", ...)`. Convertir le target `RoadieRail` de `.executableTarget` vers `.target` (library). Ajouter `RoadieRail` aux dépendances de l'`executableTarget` `roadied`.
- [ ] T021 [US1] Supprimer `Sources/RoadieRail/main.swift` (entry point obsolète) — vérifier que `Sources/RoadieRail/AppDelegate.swift` n'est plus référencé en tant qu'app delegate global. Conserver provisoirement la classe `AppDelegate` ; sa logique sera transférée en T024.
- [ ] T022 [US1] Créer `Sources/roadied/RailIntegration.swift` (~30 LOC) : encapsule `func startRail(eventBus: RoadieEventBus, thumbnailCache: ThumbnailCache) -> RailController` qui crée et retourne le RailController, l'appel se fait depuis `Daemon.bootstrap()` ou juste après. Le RailController est stocké dans une propriété forte du `Daemon` (équivalent de `AppState.daemon` côté V1).
- [ ] T023 [US1] Modifier `Sources/RoadieRail/RailController.swift` : (a) le constructeur prend `eventBus: RoadieEventBus` et `thumbnailCache: ThumbnailCache` injectés, (b) `start()` subscribe au bus via `for await event in bus.subscribe() { handleEvent(event) }`, (c) supprime toute référence à `RailIPCClient` et `EventStream`, (d) supprime le parsing TOML local `RailConfig.load()` au profit du `Config` partagé du daemon, (e) **préserve l'isolation `@MainActor` actuelle** sur le contrôleur et toutes ses méthodes manipulant AppKit/SwiftUI (NSPanel, NSEvent, NSScreen). Cf. FR-014.
- [ ] T024 [US1] Supprimer `Sources/RoadieRail/Networking/RailIPCClient.swift` et `Sources/RoadieRail/Networking/EventStream.swift`. Adapter `Sources/RoadieRail/Networking/ThumbnailFetcher.swift` pour appeler directement `thumbnailCache.fetchOrCapture(wid:)` au lieu d'envoyer une requête `window.thumbnail` sur socket.
- [ ] T025 [US1] Supprimer `Sources/RoadieRail/AppDelegate.swift` et la logique PID lockfile `~/.roadies/rail.pid` (launchd garantit l'unicité par Label, plus besoin de lockfile applicatif).
- [ ] T026 [US1] Supprimer les helpers tolérants `decodeBool`, `decodeInt`, `decodeString` à la fin de `Sources/RoadieRail/RailController.swift` (~30 LOC) — l'accès in-process aux structures Swift typées les rend obsolètes (cf. research.md R5).
- [ ] T027 [US1] Modifier `scripts/install-dev.sh` (Phase migration V1→V2, cf. quickstart.md section 1) :
  - Supprimer la section `RAIL_BUNDLE` build/sign/deploy
  - Ajouter une section "migration V1→V2" qui : `pkill roadie-rail`, `launchctl bootout com.roadie.roadie-rail` (si présent), `rm -rf ~/Applications/roadie-rail.app`, `rm -f ~/.roadies/rail.pid`, `tccutil reset ScreenCapture com.roadie.roadie-rail` (best-effort)
  - Conserver le déploiement de `~/Applications/roadied.app` et `~/.local/bin/roadie`
- [ ] T028 [US1] Vérifier la compilation : `swift build` doit produire `roadied` (avec rail intégré) + `roadie` (CLI). Aucun produit `roadie-rail`.
- [ ] T029 [US1] Test d'acceptation US1 : `./scripts/install-dev.sh` sur machine, suivi de vérifications visuelles dans Réglages Système → Confidentialité (1 seule entrée roadied par catégorie). Documenter résultat dans `implementation.md`.

**Checkpoint** : US1 terminé quand le binaire unique tourne, le rail est visible, les TCC sont à 1 entrée par catégorie, et `roadie daemon status --json` retourne `arch_version: 2`.

---

## Phase 4: US2 — Cycle de développement plus court (Priority: P1)

**Story Goal** : `swift build && deploy && restart` plus rapide qu'en V1, opérations simplifiées pour les mainteneurs.

**Independent Test** : chronométrer 5 itérations consécutives `swift build && ./scripts/install-dev.sh && verify-daemon-up` avant et après. Ratio attendu ≥ 1,25× (SC-002).

- [ ] T030 [US2] Ajouter le champ `arch_version: 2` dans la réponse de `daemon.status` (modifier `Sources/RoadieCore/Server.swift` ou `CommandRouter.swift`). Documenter dans `contracts/ipc-public-frozen.md`. (FR-020, SC-009)
- [ ] T031 [US2] [P] Mettre à jour le README.md et README.fr.md : section "Installation" ne mentionne qu'une seule app à autoriser. Section "What roadie does today" met à jour la note sur les permissions TCC.
- [ ] T032 [US2] Créer un script `scripts/bench-dev-cycle.sh` qui chronomètre 5 itérations de `swift build && ./scripts/install-dev.sh && (timeout 5 roadie daemon status > /dev/null)`. Comparer à un baseline V1 capturé au préalable. Sauvegarder résultats dans `specs/024-monobinary-merge/bench-dev-cycle.log`.

**Checkpoint** : US2 terminé quand `bench-dev-cycle.sh` montre une réduction ≥ 25 % du temps total.

---

## Phase 5: US4 — Compatibilité ascendante stricte (Priority: P1)

**Story Goal** : tous les CLI publics, raccourcis BTT, plugins SketchyBar, scripts shell utilisateurs continuent à fonctionner sans modification.

**Independent Test** : exécuter checklist complète quickstart.md sections A/B/C et comparer chaque sortie à snapshot T003/T004.

- [ ] T040 [US4] Créer un test d'intégration `Tests/RoadieCoreTests/IPCContractFrozenTests.swift` qui vérifie que chaque commande de `contracts/ipc-public-frozen.md` répond avec le même schéma JSON qu'en V1. Pour chaque commande : envoyer la requête, vérifier la présence des clés attendues dans la réponse.
- [ ] T041 [US4] [P] Créer un test d'intégration `Tests/RoadieCoreTests/EventStreamFrozenTests.swift` qui subscribe à `events --follow`, déclenche des actions (stage_change, desktop_change, window_create), et vérifie que les events arrivent avec le schéma JSON figé.
- [ ] T042 [US4] Exécuter manuellement la checklist quickstart.md section A (CLI commands) sur la machine. Cocher les items dans `implementation.md`.
- [ ] T043 [US4] Exécuter manuellement la checklist quickstart.md section B (raccourcis BTT). Cocher les items dans `implementation.md`. Si un raccourci casse → STOP, créer un ticket bug bloquant.
- [ ] T044 [US4] Exécuter manuellement la checklist quickstart.md section C (SketchyBar). Cocher les items dans `implementation.md`.

**Checkpoint** : US4 terminé quand T040/T041 passent + sections A/B/C cochées à 100 %.

---

## Phase 6: US3 — Cohérence visuelle garantie (Priority: P2)

**Story Goal** : élimination des fenêtres temporelles de désynchronisation rail/tiling. Le rail reflète à tout instant l'état exact.

**Independent Test** : test stress de 30 minutes (drag-drop intensif, switch desktop, ouverture/fermeture rapide de 20 fenêtres). Aucune divergence rail/tiling observable (SC-003).

- [ ] T050 [US3] Vérifier que `RailController.handleEvent(_ event: RoadieEvent)` (refactor T023) couvre **exhaustivement** tous les cases du enum, sans default branch silencieux. Compile-time check : Swift impose la complétude des switch sur enum.
- [ ] T051 [US3] [P] Vérifier que `RailController` ne maintient plus de `state.stagesByDisplay` parallèle à `stageManager.stagesV2`. Si oui, le supprimer. Le rail doit lire l'état actuel depuis `daemon.snapshot()` (ou méthode équivalente sur `Daemon`) au lieu d'un cache local.
- [ ] T052 [US3] Test d'intégration `Tests/RoadieRailTests/RailStateConsistencyTests.swift` : créer 3 stages, faire 100 publish d'events sur le bus, vérifier qu'à la fin l'état lu via le rail correspond à 100 % à l'état du `StageManager`.
- [ ] T053 [US3] Test stress manuel (cf. quickstart.md section E) sur 30 min. Documenter résultat dans `implementation.md`. Si divergence observée → STOP et investigation.
- [ ] T054 [US3] Vérifier le cas crash daemon : `pkill -9 roadied` puis attendre respawn launchd ≤ 30 s. Le rail doit revenir avec un état correct (pas d'état périmé qui aurait survécu côté process séparé V1, comportement nouveau acceptable).

**Checkpoint** : US3 terminé quand T052 passe + T053 sans divergence + T054 OK.

---

## Phase 7: US5 — Performance préservée ou améliorée (Priority: P3)

**Story Goal** : le rail apparaît en moins de 100 ms p95 sur hover edge. Aucune régression mémoire.

**Independent Test** : script bench dédié qui mesure p95 sur 100 itérations.

- [ ] T060 [US5] Créer `scripts/bench-rail-latency.sh` qui simule 100 hovers edge (via `cliclick` ou `osascript`) et mesure le temps entre l'event hover et la première frame visible (lecture via screen capture du panel ou via instrumentation locale). Calculer p50, p95, p99.
- [ ] T061 [US5] Exécuter le bench avant et après migration. Comparer. Cible : p95 ≤ 100 ms (SC-006). Documenter dans `bench-rail-latency.log`.
- [ ] T062 [US5] [P] Mesure mémoire : ouvrir 10 fenêtres, laisser le rail tourner 5 minutes, mesurer la RSS du process (`ps -p $(pgrep -f roadied) -o rss`). Cible : ≤ baseline V1 + 5 % (SC-005 indirect).

**Checkpoint** : US5 terminé quand T061 passe sous la cible et T062 sans régression > 5 %.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose** : finalisation, documentation, audits, cleanup.

- [ ] T070 Mesurer la LOC effective post-migration : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`. Comparer au baseline T002. Vérifier delta ≤ −150 LOC (cible) ou ≤ +50 LOC (plafond strict, FR-013, SC-005). Documenter dans `implementation.md`.
- [ ] T071 [P] Créer/mettre à jour ADR `docs/decisions/ADR-009-monobinary-merge.md` qui documente la décision archi mono-binaire, le trade-off d'isolation crash, le pattern EventBus retenu.
- [ ] T072 [P] Mettre à jour `docs/architecture.md` (s'il existe, sinon créer) pour refléter la nouvelle topologie 1-process.
- [ ] T073 [P] Désinstaller manuellement les artefacts V1 résiduels qu'install-dev.sh n'aurait pas attrapés : grep dans le système pour toute référence orpheline à `roadie-rail`.
- [ ] T074 Mettre à jour `scripts/uninstall.sh` (créer si manquant) pour le cleanup complet selon FR-017.
- [ ] T075 [P] Mettre à jour la checklist `specs/024-monobinary-merge/checklists/requirements.md` : marquer tous les items terminés.
- [ ] T076 Audit `/audit` sur le scope SPEC-024 : doit retourner grade ≥ A-. Si findings critiques → corriger avant de clore.
- [ ] T077 Mise à jour de `implementation.md` : section finale REX (rétrospective), enseignements, prochaines actions.

---

## Dependencies entre phases

```text
Setup (T001-T004)
    ↓
Foundational (T010-T014)  ← BLOQUANT pour toutes les US
    ↓
US1 (T020-T029)  ← MVP, débloque US2 et US4
    ↓
├── US2 (T030-T032)  ← polit l'UX et la doc
├── US4 (T040-T044)  ← teste la non-régression
└── US3 (T050-T054)  ← teste la cohérence interne
        ↓
       US5 (T060-T062)  ← perf, peut tourner en parallèle de Polish
        ↓
       Polish (T070-T077)
```

**Path MVP** : Setup → Foundational → US1 = livraison incrémentale fonctionnelle minimale (le binaire unique tourne, rail visible, TCC simplifiée).

**Path complet** : MVP + US2 + US4 + US3 + US5 + Polish = livraison finale conforme à tous les acceptance criteria du spec.

---

## Parallel Execution Examples

### Pendant Phase 2 (Foundational)

```text
T012 (tests EventBus) peut tourner en parallèle de T013 (refactor producteurs)
si les tests sont écrits contre le contrat T010+T011 et n'attendent pas T013.
```

### Pendant Phase 3 (US1)

```text
T020-T024 sont séquentiels (modifient des fichiers étroitement liés)
T025-T026 peuvent tourner en parallèle après T024 (suppressions indépendantes)
T027 (install-dev.sh) peut être préparé en parallèle de T020-T026 (fichier indépendant)
```

### Pendant Phase 5/6 (US4/US3)

```text
T040 + T041 + T052 sont 3 fichiers de test différents → exécution parallèle possible
T042 + T043 + T044 + T053 sont des tests manuels → exécution séquentielle (1 humain)
```

### Pendant Phase 8 (Polish)

```text
T071 + T072 + T073 + T075 sont tous indépendants → 4 mises à jour en parallèle
T076 (audit) doit attendre T070 (LOC mesure)
```

---

## Implementation Strategy

### Approche recommandée : MVP-first incrémental

1. **Setup + Foundational + US1** = livre le mono-binaire fonctionnel. À ce stade, l'utilisateur peut déjà utiliser le produit V2 dans son daily driver (= l'auteur lui-même). Time-box 1-2 jours.
2. **US4** = couvre la non-régression CLI/BTT/SketchyBar. Critique avant de pousser à un public élargi. Time-box 0,5 jour.
3. **US3** = stress test, valide la cohérence interne. Time-box 0,5 jour.
4. **US2 + US5** = polit perf et UX. Time-box 0,5 jour.
5. **Polish** = ADR, docs, audits. Time-box 0,5 jour.

**Total estimé** : 3-4 jours de travail effectif (selon disponibilité dev).

### Critères de gate entre phases

- **Setup → Foundational** : `loc-baseline.txt` et `cli-v1/` snapshots existent.
- **Foundational → US1** : T012 verts (tests EventBus), T014 sans régression sur `events --follow`.
- **US1 → US4** : compilation `swift build` OK, `roadied` boote, rail visible.
- **US4 → US3** : T040/T041 verts, T042-T044 cochés.
- **US3 → US5** : T052 vert, T053 sans divergence.
- **US5 → Polish** : T061 sous la cible 100 ms p95.
- **Polish → merge** : T076 audit grade ≥ A-, T077 implementation.md complet.

### Rollback strategy

Si à n'importe quelle phase un blocage technique majeur survient :
1. `git checkout pre-024-baseline` (branche T001)
2. `./scripts/install-dev.sh` (revient à V1)
3. Ouvrir un ticket de blocage avec contexte précis
4. Décider : abandon de la migration OU correction ciblée puis reprise

Aucun risque pour les données utilisateur (config TOML, stages persistés inchangés).

---

## Estimation et synthèse

| Phase | Tâches | Critique pour MVP ? | Effort estimé |
|-------|--------|---------------------|---------------|
| Setup | T001-T004 (4) | Oui (snapshots) | 30 min |
| Foundational | T010-T015 (6) | Oui (bus interne + perms boot) | 0,5 jour |
| US1 | T020-T029 (10) | Oui (MVP) | 1-1,5 jour |
| US2 | T030-T032 (3) | Non | 0,5 jour |
| US4 | T040-T044 (5) | Oui (compat) | 0,5 jour |
| US3 | T050-T054 (5) | Recommandé | 0,5 jour |
| US5 | T060-T062 (3) | Non | 0,5 jour |
| Polish | T070-T077 (8) | Recommandé | 0,5 jour |
| **TOTAL** | **44 tâches** | | **3,5-4 jours** |

**MVP scope (livrable minimal validé)** : Phases 1+2+3+5 = ~2-2,5 jours.
