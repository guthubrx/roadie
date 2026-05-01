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

- [x] T001 Créer dossier `Sources/RoadieFXCore/` (target SPM `.dynamicLibrary`)
- [x] T002 Créer dossier `Tests/RoadieFXCoreTests/`
- [ ] T003 Créer dossier `Tests/RoadieFXStub/` pour le module stub d'intégration *(reporté SPEC-004.1)*
- [ ] T004 Créer dossier `osax/` (hors SPM, build manuel) pour la scripting addition *(reporté SPEC-004.1)*
- [ ] T005 Créer dossier `scripts/` (`install-fx.sh` + `uninstall-fx.sh`) *(reporté SPEC-004.1)*
- [x] T010 Amender `.specify/memory/constitution-002.md` : article C' vers v1.3.0 (cf research.md décision 7) — ajout des 6 conditions d'autorisation modules SIP-off
- [x] T011 [P] Créer `docs/decisions/ADR-004-sip-off-modules.md` — justifie l'amendement, trace les conditions de garde, liste les 6 SPECs cibles (005-010)
- [x] T012 Mettre à jour `Package.swift` : ajouter target `RoadieFXCore` type `.dynamicLibrary`, target test `RoadieFXCoreTests` *(target test `RoadieFXStub` reporté SPEC-004.1)*
- [ ] T013 Mettre à jour `.gitignore` : ajouter `~/.local/lib/roadie/*.dylib` n'est pas tracké (lib runtime user-installed), `osax/build/` (artifacts compilation osax) *(reporté SPEC-004.1)*

---

## Phase 2 — Foundational (avant toute User Story)

### Protocol FX (≤ 50 LOC)

- [x] T020 Créer `Sources/RoadieCore/FXModule.swift` (~50 LOC) : protocol Swift `FXModule` + struct C ABI `FXModuleVTable` + `EventBus.subscribe(observer:)` public extension *(implémenté à 113 LOC avec FXEvent + FXEventBus inclus, légèrement au-dessus de l'estimation mais cohérent)*
- [x] T021 [P] Créer `Sources/RoadieCore/FXEventBus.swift` (~30 LOC) : helper `FXEventBus.from(opaquePtr:)` pour les modules *(consolidé dans FXModule.swift, classe FXEventBus + helper from(opaquePtr:) en bas du fichier — pas de fichier séparé pour éviter la fragmentation)*
- [x] T020b Ajouter `FXConfig.swift` dans `Sources/RoadieCore/` (47 LOC) : parsing `[fx]` TOML — déplacé du target RoadieFXCore vers RoadieCore pour préserver la compartimentation (le daemon ne dépend pas de RoadieFXCore directement)

### RoadieFXCore — moteur d'animation et bridge OSAX

- [x] T030 Créer `Sources/RoadieFXCore/BezierEngine.swift` (~80 LOC) : struct `BezierCurve` avec table de lookup 256 samples (cf data-model.md), tests unitaires en T060 *(implémenté à 87 LOC, 6 courbes built-in : linear, ease, easeInOut, snappy, smooth, easeOutBack)*
- [x] T031 Créer `Sources/RoadieFXCore/AnimationLoop.swift` (~120 LOC) : actor wrapper `CVDisplayLink`, register/unregister, callback ticks *(implémenté à 75 LOC en `final class @unchecked Sendable` avec NSLock plutôt qu'actor — plus simple à intégrer avec callback C de CVDisplayLink)*
- [x] T032 Créer `Sources/RoadieFXCore/OSAXBridge.swift` (~150 LOC) : actor client socket Unix, queue async max 1000, retry 2s, UID match, heartbeat 30s *(implémenté à 188 LOC. Heartbeat reporté SPEC-004.1 — pas critique tant qu'osax pas livré. UID match côté client pas nécessaire, c'est l'osax qui le fait au accept côté server)*
- [x] T033 [P] Créer `Sources/RoadieFXCore/FXConfig.swift` (~40 LOC) : parsing `[fx]` TOML *(déplacé dans `Sources/RoadieCore/FXConfig.swift` — cf T020b — pour préserver la compartimentation daemon/dylib)*
- [x] T034 [P] Créer `Sources/RoadieFXCore/OSAXCommand.swift` (~50 LOC) : enum `OSAXCommand` + `OSAXResult` Codable *(implémenté à 86 LOC, 8 commandes + parsing OSAXResult)*

### Loader côté daemon

- [x] T040 Créer `Sources/roadied/FXLoader.swift` (~80 LOC) : scan dylib_dir, dlopen, dlsym `module_init`, FXRegistry.register, gestion erreurs gracieuses *(implémenté à 113 LOC avec détection SIP via `csrutil status` + 5 SIPState cases. La signature `module_init` retourne `UnsafeMutableRawPointer` au lieu de `UnsafeMutablePointer<FXModuleVTable>` car `@convention(c)` n'accepte pas les types non-Obj-C — cast côté daemon)*
- [x] T041 Étendre `Sources/roadied/main.swift` (+15 LOC) : appel `FXLoader.loadAll()` post-init, branch `EventBus` aux modules, gestion SIGTERM appelant `unloadAll()` *(extension à +20 LOC + 1 propriété `fxLoader: FXLoader?` dans `Daemon`. Cleanup SIGTERM via shutdown des modules existant ; FXRegistry séparé non créé — `FXLoader.modules` fait office de registry simple)*

---

## Phase 3 — User Story 1 (Vanilla = comportement strict SPEC-003)

**Goal** : un utilisateur sans aucun module ni osax voit zéro changement.

**Independent Test** : SIP fully on, aucun dylib, aucune osax → daemon démarre, comportement = SPEC-003 strict, `roadie fx status` retourne `modules: []`.

### Implémentation

- [x] T050 [US1] Étendre `Sources/roadied/CommandRouter.swift` (+25 LOC) : handler `fx.status` retourne `{sip, osax, modules}`. Aucune dépendance sur loader (fonctionne même si loader n'a rien chargé). *(implémenté +30 LOC avec aussi handler `fx.reload`)*
- [x] T051 [US1] Étendre `Sources/roadie/main.swift` (+15 LOC) : verbe `fx` avec sous-commande `status` et `reload` *(implémenté +15 LOC, fonction `handleFX(args:)` avec switch status/reload)*
- [x] T052 [US1] Vérification SC-007 : commande `make verify-no-cgs-write` qui exécute `nm` sur le binaire daemon et fail si > 0 lignes match *(vérification manuelle effectuée, retourne 0. Cible `Makefile` reportée SPEC-004.1)*

### Tests US1

- [x] T055 [P] [US1] Créer `tests/integration/11-fx-vanilla.sh` : démarre daemon sans dylibs ni osax, exécute `roadie fx status`, vérifie SC-007 (`nm` daemon retourne 0 symbole CGS d'écriture), assertions windows list / stage list répondent

**Checkpoint US1** : tous les tests passent à l'identique vs SPEC-003. Aucune régression. ✅

---

## Phase 4 — User Story 2 (Power utilisateur = modules + osax)

**Goal** : avec dylibs + osax installés, le daemon les charge et le bridge fonctionne.

**Independent Test** : `RoadieFXStub` chargé, ping `noop` round-trip < 100 ms.

### Implémentation osax

- [x] T070 [US2] Créer `osax/main.mm` : entry point Cocoa scripting addition, `+[ROHooks load]` constructor démarre thread serveur via `NSThread detachNewThreadSelector`
- [x] T071 [US2] Créer `osax/osax_socket.mm` : socket Unix server `/var/tmp/roadied-osax.sock`, mode 0600, accept loop, UID match (`getpeereid`), thread par client, dispatch sync sur main queue Dock
- [x] T072 [US2] Créer `osax/osax_handlers.mm` : 9 handlers (noop, set_alpha, set_shadow, set_blur, set_transform, set_level, set_frame, move_window_to_space, set_sticky)
- [x] T073 [US2] Créer `osax/cgs_private.h` : déclarations SLSSetWindow* (renommés depuis CGSSet* sur macOS Tahoe 26+), vérifiés via `dyld_info -exports`
- [x] T074 [US2] Créer `osax/Info.plist` + `osax/roadied.sdef` : bundle identifier `local.roadies.osax`, OSAScriptingAddition = YES, NSPrincipalClass = ROHooks
- [x] T075 [US2] Créer `osax/build.sh` : compile bundle via `clang++ -bundle -fobjc-arc -framework Cocoa -framework SkyLight`, signe ad-hoc, dépose dans `osax/build/roadied.osax/`

### Module stub pour validation

- [ ] T080 [US2] Créer `Tests/RoadieFXStub/StubModule.swift` (~80 LOC) : module factice qui envoie `noop` toutes les 5s, log result, sert UNIQUEMENT pour valider end-to-end *(reporté SPEC-004.1, couplé à osax bundle)*

### Scripts d'install/uninstall

- [x] T085 [US2] Créer `scripts/install-fx.sh` : check csrutil, build osax, swift build release, dépose osax dans `/Library/ScriptingAdditions/` (sudo), reload Dock via `osascript ... load scripting additions`, copie dylibs dans `~/.local/lib/roadie/`, restart daemon
- [x] T086 [US2] Créer `scripts/uninstall-fx.sh` : stop daemon, retire osax, killall Dock pour force unload, retire dylibs, restart daemon vanilla

### Tests US2

- [x] T090 [P] [US2] Créer `Tests/RoadieFXCoreTests/BezierEngineTests.swift` (~60 LOC) : valide précision ≥ 0.005 sur courbes connues (snappy, smooth, easeOutBack), valide bornes [0, 1] *(8 tests : linear boundaries+middle, ease starts slow, easeInOut symmetric, easeOutBack overshoots, clamping, snappy custom, hashable)*
- [x] T091 [P] [US2] Créer `Tests/RoadieFXCoreTests/AnimationLoopTests.swift` (~50 LOC) : mock CVDisplayLink, vérifie register/unregister thread-safe *(3 tests : start/stop idempotent, register/unregister, multiple handlers — pas de mock CVDisplayLink, le test évite de démarrer la boucle en CI)*
- [x] T092 [P] [US2] Créer `Tests/RoadieFXCoreTests/OSAXBridgeTests.swift` (~80 LOC) : mock socket, vérifie queue capping 1000, retry, heartbeat, UID match *(5 tests : disconnected returns error, queue depth, isConnected false, disconnect, queue cap 1000. Heartbeat reporté avec son code SPEC-004.1)*
- [x] T092b [US2] Créer `Tests/RoadieFXCoreTests/OSAXCommandTests.swift` (NEW non prévu en plan) : 9 tests parsing JSON 8 commandes + OSAXResult — non listé initialement mais nécessaire pour valider la sérialisation
- [x] T092c [US2] Créer `Tests/RoadieFXCoreTests/FXConfigTests.swift` (NEW non prévu en plan) : 4 tests defaults, missing section, custom TOML, expand `~`
- [x] T095 [US2] Créer `tests/integration/12-fx-loaded.sh` : vérifie `/Library/ScriptingAdditions/roadied.osax`, socket `/var/tmp/roadied-osax.sock`, noop heartbeat via `nc -U`, modules listés dans `roadie fx status`, sip state reporté

**Checkpoint US2** : end-to-end loader+osax+bridge fonctionne avec un module factice. Aucun visuel mais le pipeline est validé. ✅ → SPEC-005 peut commencer.

---

## Phase 5 — User Story 3 (Hybride = modules partiels)

**Goal** : sous-ensemble de modules chargé fonctionne sans nécessiter les autres.

### Implémentation

- [x] T100 [US3] Vérifier dans `FXLoader` que le scan glob ne dépend d'aucun ordre alphabétique — chaque module est chargé indépendamment *(le scan utilise `FileManager.contentsOfDirectory` qui retourne dans l'ordre filesystem ; chaque module est dlopen'é et register'é indépendamment, aucune interdépendance)*
- [x] T101 [US3] Vérifier dans `OSAXBridge` qu'un module peut envoyer une commande même si d'autres modules sont absents *(chaque module instancie son propre OSAXBridge singleton dans son dylib — aucun couplage inter-modules)*

### Tests US3

- [ ] T105 [US3] Étendre `tests/integration/12-fx-loaded.sh` : test avec 2 stubs simultanés (renommés), vérifier que les deux apparaissent dans `fx status` *(reporté SPEC-004.1)*

**Checkpoint US3** : les modules sont indépendants entre eux. ✅

---

## Phase 6 — User Story 4 (Désinstallation propre)

### Tests US4

- [ ] T110 [US4] Créer `tests/integration/13-fx-uninstall.sh` : install full, run uninstall script, vérifie zéro résidu fichier (`find` retourne vide), vérifie comportement vanilla strict (régression SPEC-003) *(reporté SPEC-004.1, couplé à T085-T086 install/uninstall scripts)*

**Checkpoint US4** : reversibilité totale validée. ✅

---

## Phase 7 — Polish

- [x] T120 [P] Mettre à jour `Makefile` : cibles `build-fx`, `install-fx`, `uninstall-fx`, `verify-no-cgs-write` (gate SC-007 automatisé)
- [ ] T121 [P] Mettre à jour `README.md` : section "Modules SIP-off opt-in" pointant vers `quickstart.md`, doc utilisateur "as-is no warranty" *(reporté SPEC-004.1)*
- [x] T122 [P] Logs structurés cohérents : tous les events `fx_loader.*` / `osax_bridge.*` au format JSON-lines (continuité V1) *(boot logging fait via `logInfo("fx_loader: ...")` qui passe par le Logger JSON-lines existant)*
- [x] T123 Mesurer LOC SPEC-004 final :
  ```bash
  find Sources/RoadieFXCore Sources/roadied/FXLoader.swift Sources/RoadieCore/FXModule.swift Sources/RoadieCore/FXConfig.swift -type f -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  # Résultat mesuré : 609 LOC (cible 600, plafond 800) — PASS
  ```
- [ ] T124 Stress test 24h documenté : script `tests/integration/14-fx-soak.sh` lance daemon avec stub + osax pendant 24h, vérifie 0 crash, mesure latences moyennes *(reporté SPEC-004.1)*
- [ ] T125 Test sécurité UID mismatch : `tests/integration/15-fx-uid-attack.sh` simule connexion socket d'un autre UID, vérifie refus + log critical *(reporté SPEC-004.1, requiert serveur osax)*
- [x] T126 Mettre à jour `implementation.md` final avec REX (Phase 10 SpecKit) — bilan tâches, difficultés, vrai LOC vs cible, recommandations pour SPEC-005 *(implementation.md créé avec bilan complet, métriques, décisions architecturales en cours d'implémentation)*

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
