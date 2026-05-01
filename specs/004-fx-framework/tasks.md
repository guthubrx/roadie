# Tasks: Framework SIP-off opt-in (SPEC-004)

**Feature** : SPEC-004 fx-framework
**Branch** : `004-fx-framework`
**Date** : 2026-05-01
**Input** : [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichier différent, pas de dépendance)
- `[USn]` = rattachement à User Story n

## Insistance minimalisme

À chaque tâche d'implémentation, **avant d'écrire la moindre ligne** : confirmer qu'elle ne peut pas être plus courte. Plafond cumulé strict 800 LOC, cible 600. Toute tâche qui dépasse son budget LOC indicatif → STOP, refactor, demander revue.

---

## Phase 1 — Setup et amendement constitution

- [ ] T001 Créer dossier `Sources/RoadieFXCore/` (target SPM `.dynamicLibrary`)
- [ ] T002 Créer dossier `Tests/RoadieFXCoreTests/`
- [ ] T003 Créer dossier `Tests/RoadieFXStub/` pour le module stub d'intégration
- [ ] T004 Créer dossier `osax/` (hors SPM, build manuel) pour la scripting addition
- [ ] T005 Créer dossier `scripts/` (`install-fx.sh` + `uninstall-fx.sh`)
- [ ] T010 Amender `.specify/memory/constitution-002.md` : article C' vers v1.3.0 (cf research.md décision 7) — ajout des 6 conditions d'autorisation modules SIP-off
- [ ] T011 [P] Créer `docs/decisions/ADR-004-sip-off-modules.md` — justifie l'amendement, trace les conditions de garde, liste les 6 SPECs cibles (005-010)
- [ ] T012 Mettre à jour `Package.swift` : ajouter target `RoadieFXCore` type `.dynamicLibrary`, target test `RoadieFXCoreTests`, target test `RoadieFXStub` type `.dynamicLibrary`
- [ ] T013 Mettre à jour `.gitignore` : ajouter `~/.local/lib/roadie/*.dylib` n'est pas tracké (lib runtime user-installed), `osax/build/` (artifacts compilation osax)

---

## Phase 2 — Foundational (avant toute User Story)

### Protocol FX (≤ 50 LOC)

- [ ] T020 Créer `Sources/RoadieCore/FXModule.swift` (~50 LOC) : protocol Swift `FXModule` + struct C ABI `FXModuleVTable` + `EventBus.subscribe(observer:)` public extension
- [ ] T021 [P] Créer `Sources/RoadieCore/FXEventBus.swift` (~30 LOC) : helper `FXEventBus.from(opaquePtr:)` pour les modules

### RoadieFXCore — moteur d'animation et bridge OSAX

- [ ] T030 Créer `Sources/RoadieFXCore/BezierEngine.swift` (~80 LOC) : struct `BezierCurve` avec table de lookup 256 samples (cf data-model.md), tests unitaires en T060
- [ ] T031 Créer `Sources/RoadieFXCore/AnimationLoop.swift` (~120 LOC) : actor wrapper `CVDisplayLink`, register/unregister, callback ticks
- [ ] T032 Créer `Sources/RoadieFXCore/OSAXBridge.swift` (~150 LOC) : actor client socket Unix, queue async max 1000, retry 2s, UID match, heartbeat 30s
- [ ] T033 [P] Créer `Sources/RoadieFXCore/FXConfig.swift` (~40 LOC) : parsing `[fx]` TOML
- [ ] T034 [P] Créer `Sources/RoadieFXCore/OSAXCommand.swift` (~50 LOC) : enum `OSAXCommand` + `OSAXResult` Codable

### Loader côté daemon

- [ ] T040 Créer `Sources/roadied/FXLoader.swift` (~80 LOC) : scan dylib_dir, dlopen, dlsym `module_init`, FXRegistry.register, gestion erreurs gracieuses
- [ ] T041 Étendre `Sources/roadied/main.swift` (+15 LOC) : appel `FXLoader.loadAll()` post-init, branch `EventBus` aux modules, gestion SIGTERM appelant `unloadAll()`

---

## Phase 3 — User Story 1 (Vanilla = comportement strict SPEC-003)

**Goal** : un utilisateur sans aucun module ni osax voit zéro changement.

**Independent Test** : SIP fully on, aucun dylib, aucune osax → daemon démarre, comportement = SPEC-003 strict, `roadie fx status` retourne `modules: []`.

### Implémentation

- [ ] T050 [US1] Étendre `Sources/roadied/CommandRouter.swift` (+25 LOC) : handler `fx.status` retourne `{sip, osax, modules}`. Aucune dépendance sur loader (fonctionne même si loader n'a rien chargé).
- [ ] T051 [US1] Étendre `Sources/roadie/main.swift` (+15 LOC) : verbe `fx` avec sous-commande `status` et `reload`
- [ ] T052 [US1] Vérification SC-007 : commande `make verify-no-cgs-write` qui exécute `nm` sur le binaire daemon et fail si > 0 lignes match

### Tests US1

- [ ] T055 [P] [US1] Créer `tests/integration/11-fx-vanilla.sh` : démarre daemon sans dylibs ni osax, exécute `roadie fx status`, vérifie `modules: []`, exécute toutes les assertions des tests SPEC-002 + SPEC-003 (régression complète)

**Checkpoint US1** : tous les tests passent à l'identique vs SPEC-003. Aucune régression. ✅

---

## Phase 4 — User Story 2 (Power utilisateur = modules + osax)

**Goal** : avec dylibs + osax installés, le daemon les charge et le bridge fonctionne.

**Independent Test** : `RoadieFXStub` chargé, ping `noop` round-trip < 100 ms.

### Implémentation osax

- [ ] T070 [US2] Créer `osax/main.mm` (~40 LOC) : entry point Cocoa scripting addition, démarre serveur socket dans thread dédié
- [ ] T071 [US2] Créer `osax/osax_socket.mm` (~80 LOC) : socket Unix server, accept loop, UID match, dispatch sur main queue
- [ ] T072 [US2] Créer `osax/osax_handlers.mm` (~80 LOC) : 8 handlers commandes (noop, set_alpha, set_shadow, set_blur, set_transform, set_level, move_window_to_space, set_sticky)
- [ ] T073 [US2] Créer `osax/cgs_private.h` (~30 LOC) : déclarations privées CGS d'écriture (jamais incluses par le daemon Swift)
- [ ] T074 [US2] Créer `osax/Info.plist` : bundle identifier `local.roadies.osax`, OSAScriptingAddition = true, signing ad-hoc
- [ ] T075 [US2] Créer `osax/build.sh` : compile bundle via `clang++ -bundle -framework Cocoa -framework SkyLight`, signe ad-hoc, dépose dans `osax/build/roadied.osax/`

### Module stub pour validation

- [ ] T080 [US2] Créer `Tests/RoadieFXStub/StubModule.swift` (~80 LOC) : module factice qui envoie `noop` toutes les 5s, log result, sert UNIQUEMENT pour valider end-to-end

### Scripts d'install/uninstall

- [ ] T085 [US2] Créer `scripts/install-fx.sh` (~30 LOC) : copie osax dans `/Library/ScriptingAdditions/`, force load Dock, copie dylibs dans `~/.local/lib/roadie/`
- [ ] T086 [US2] Créer `scripts/uninstall-fx.sh` (~30 LOC) : stop daemon, retire osax, force unload Dock, retire dylibs, restart daemon

### Tests US2

- [ ] T090 [P] [US2] Créer `Tests/RoadieFXCoreTests/BezierEngineTests.swift` (~60 LOC) : valide précision ≥ 0.005 sur courbes connues (snappy, smooth, easeOutBack), valide bornes [0, 1]
- [ ] T091 [P] [US2] Créer `Tests/RoadieFXCoreTests/AnimationLoopTests.swift` (~50 LOC) : mock CVDisplayLink, vérifie register/unregister thread-safe
- [ ] T092 [P] [US2] Créer `Tests/RoadieFXCoreTests/OSAXBridgeTests.swift` (~80 LOC) : mock socket, vérifie queue capping 1000, retry, heartbeat, UID match
- [ ] T095 [US2] Créer `tests/integration/12-fx-loaded.sh` : install osax + stub, démarre daemon, vérifie module loaded en log, vérifie `roadie fx status` retourne stub, vérifie noop round-trip < 100 ms (mesuré via timestamps log)

**Checkpoint US2** : end-to-end loader+osax+bridge fonctionne avec un module factice. Aucun visuel mais le pipeline est validé. ✅ → SPEC-005 peut commencer.

---

## Phase 5 — User Story 3 (Hybride = modules partiels)

**Goal** : sous-ensemble de modules chargé fonctionne sans nécessiter les autres.

### Implémentation

- [ ] T100 [US3] Vérifier dans `FXLoader` que le scan glob ne dépend d'aucun ordre alphabétique — chaque module est chargé indépendamment
- [ ] T101 [US3] Vérifier dans `OSAXBridge` qu'un module peut envoyer une commande même si d'autres modules sont absents

### Tests US3

- [ ] T105 [US3] Étendre `tests/integration/12-fx-loaded.sh` : test avec 2 stubs simultanés (renommés), vérifier que les deux apparaissent dans `fx status`

**Checkpoint US3** : les modules sont indépendants entre eux. ✅

---

## Phase 6 — User Story 4 (Désinstallation propre)

### Tests US4

- [ ] T110 [US4] Créer `tests/integration/13-fx-uninstall.sh` : install full, run uninstall script, vérifie zéro résidu fichier (`find` retourne vide), vérifie comportement vanilla strict (régression SPEC-003)

**Checkpoint US4** : reversibilité totale validée. ✅

---

## Phase 7 — Polish

- [ ] T120 [P] Mettre à jour `Makefile` : cibles `build-fx`, `install-fx`, `uninstall-fx`, `verify-no-cgs-write`
- [ ] T121 [P] Mettre à jour `README.md` : section "Modules SIP-off opt-in" pointant vers `quickstart.md`, doc utilisateur "as-is no warranty"
- [ ] T122 [P] Logs structurés cohérents : tous les events `fx_loader.*` / `osax_bridge.*` au format JSON-lines (continuité V1)
- [ ] T123 Mesurer LOC SPEC-004 final :
  ```bash
  find Sources/RoadieFXCore Sources/roadied/FXLoader.swift Sources/roadied/main.swift Sources/RoadieCore/FXModule.swift Sources/RoadieCore/FXEventBus.swift Sources/roadie/main.swift osax/ \
       -type f \( -name '*.swift' -o -name '*.mm' -o -name '*.h' \) \
       -exec grep -vE '^\s*$|^\s*//|^\s*/\*' {} + 2>/dev/null | wc -l
  # Doit afficher ≤ 800
  ```
- [ ] T124 Stress test 24h documenté : script `tests/integration/14-fx-soak.sh` lance daemon avec stub + osax pendant 24h, vérifie 0 crash, mesure latences moyennes
- [ ] T125 Test sécurité UID mismatch : `tests/integration/15-fx-uid-attack.sh` simule connexion socket d'un autre UID, vérifie refus + log critical
- [ ] T126 Mettre à jour `implementation.md` final avec REX (Phase 10 SpecKit) — bilan tâches, difficultés, vrai LOC vs cible, recommandations pour SPEC-005

---

## Dependencies

**Sequential phases** :
1. Phase 1 (Setup + amendement constitution) → bloque tout
2. Phase 2 (Foundational) → bloque toutes les user stories
3. Phase 3 (US1 vanilla) → libre (juste vérifier non-régression)
4. Phase 4 (US2 loader + osax + stub) → dépend de Phase 2 mais indépendante de Phase 3
5. Phase 5 (US3 hybride) → dépend de Phase 4
6. Phase 6 (US4 uninstall) → dépend de Phase 4
7. Phase 7 (Polish) → après tout

**Parallel opportunities** :
- T011 / T021 / T033 / T034 (Foundational) — fichiers indépendants
- T055 / T090 / T091 / T092 (tests) — fichiers test différents
- T120 / T121 / T122 (polish) — non bloquants

---

## Implementation Strategy

**MVP SPEC-004 = Phase 1 + Phase 2 + Phase 4 (US2) avec stub fonctionnel.**

C'est suffisant pour valider l'archi end-to-end et débloquer SPEC-005 (Shadowless). Les phases 3 (vanilla), 5 (hybride), 6 (uninstall), 7 (polish) suivent.

**Ordre recommandé** :
1. Phase 1 + amendement (T001-T013) — 9 tâches, 1 jour
2. Phase 2 Foundational (T020-T041) — 9 tâches, 2-3 jours
3. Phase 3 US1 vanilla + check SC-007 (T050-T055) — 4 tâches, 1 jour
4. Phase 4 US2 loader + osax + stub (T070-T095) — 14 tâches, 4-5 jours → **🎯 MVP livrable**
5. Phase 5 US3 (T100-T105) — 3 tâches, 0.5 jour
6. Phase 6 US4 (T110) — 1 tâche, 0.5 jour
7. Phase 7 Polish (T120-T126) — 7 tâches, 1-2 jours

**Total : 47 tâches**, dont ~12 parallélisables `[P]`. Estimation 8-12 jours homme.

---

## Format validation

✅ Toutes les tâches commencent par `- [ ] T<nnn>`
✅ Phases user stories incluent `[USk]`
✅ Setup / Foundational / Polish n'incluent pas `[USk]`
✅ Chemins fichiers explicites pour chaque tâche
✅ Plafond LOC strict mentionné dans T123 + check `make verify-no-cgs-write` au T052

## Garde-fou minimalisme (insistance utilisateur)

À chaque tâche, on se demande :
- ❓ « Est-ce qu'on peut faire ça en moins de lignes ? »
- ❓ « Est-ce que cette feature mérite vraiment d'exister ? »
- ❓ « Est-ce qu'un cas d'usage concret la justifie ? »

Si la réponse est non aux 3 → drop la feature, refactor, ou demander revue utilisateur.
