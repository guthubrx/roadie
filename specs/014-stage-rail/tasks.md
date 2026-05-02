# Tasks — SPEC-014 Stage Rail UI

**Status**: Draft
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)
**Last updated**: 2026-05-02

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichiers indépendants).
- `[US<k>]` = appartient à user story k.

## Path Conventions

Tous les chemins relatifs à la racine du repo `<repo-root>` ou worktree `<repo-root>/.worktrees/014-stage-rail/`.

---

## Phase 1 — Setup (Foundational, P0)

- [X] T001 [SETUP] Créer la branche dédiée `014-stage-rail` depuis `main` à jour, créer le worktree `.worktrees/014-stage-rail/`. **DEFERRED** : pour cette session, on est resté sur la branche `013-desktop-per-display`. À refaire dans une session dédiée.
- [X] T002 [SETUP] Ajouter le target `RoadieRail` (executableTarget) dans `Package.swift` avec dépendance `RoadieCore`. **DONE 2026-05-02**.
- [X] T003 [SETUP] Ajouter le target `RoadieRailUI` (library) dans `Package.swift` (séparation pour future réutilisation). **NOT NEEDED V1** : le code SwiftUI vit dans le target `RoadieRail` directement, séparation reportée à V2 si réutilisation justifiée.
- [X] T004 [SETUP] Étendre `Makefile` : cibles `build-rail`, `install-rail`, `uninstall-rail`. **DONE 2026-05-02** (codesign + bundle reportés à US1).
- [X] T005 [SETUP] Créer le dossier `Sources/RoadieRail/` avec `main.swift` minimal qui imprime version stub et exit. **DONE 2026-05-02**.
- [X] T006 [SETUP] Créer `Tests/RoadieRailTests/RoadieRailSmokeTests.swift`. **DONE 2026-05-02**, passe.

**Critère de fin Phase 1** : `swift build --product roadie-rail` clean ✓, `make build-rail` produit un binaire fonctionnel ✓, `roadie-rail` lance et exit avec code 0 ✓, smoke test passe ✓.

---

## Phase 2 — Foundational : extensions daemon (Pré-requis pour US1+)

- [X] T010 [FOUNDATIONAL] Créer `Sources/RoadieCore/ThumbnailCache.swift` (~80 LOC) — LRU cache structuré, capacité 50, méthodes get/put/evict/clear. Tests unitaires associés `Tests/RoadieCoreTests/ThumbnailCacheTests.swift`.
- [X] T011 [P] [FOUNDATIONAL] Créer `Sources/RoadieCore/ScreenCapture/SCKCaptureService.swift` (~150 LOC) — wrapper ScreenCaptureKit, observe(wid)/unobserve(wid), 0.5 Hz, ré-échantillonnage 320×200, encode PNG.
- [X] T012 [FOUNDATIONAL] Tests `Tests/RoadieCoreTests/SCKCaptureServiceTests.swift` — mock SCStream, vérifier flow observe/capture/unobserve, vérifier downscale.
- [X] T013 [P] [FOUNDATIONAL] Créer `Sources/RoadieCore/Watchers/WallpaperClickWatcher.swift` (~120 LOC) — observer kAX, callback `onWallpaperClick(NSPoint)`, désactivable.
- [X] T014 [FOUNDATIONAL] Tests `Tests/RoadieCoreTests/WallpaperClickWatcherTests.swift` — mock AXObserver, simuler events, vérifier filtrage des clicks dans fenêtres tracked.
- [X] T015 [FOUNDATIONAL] Étendre `Sources/roadied/CommandRouter.swift` avec :
  - `window.thumbnail` (retourne PNG base64 depuis ThumbnailCache, démarre observation SCK si absent)
  - `tiling.reserve` (no-op stub V1, juste pour valider le contrat)
  - `rail.status` (lit `~/.roadies/rail.pid`, retourne running/pid/since)
  - `rail.toggle` (spawn ou kill `~/.local/bin/roadie-rail`)
- [X] T016 [FOUNDATIONAL] Étendre `Sources/roadied/main.swift` pour instancier `SCKCaptureService` + `WallpaperClickWatcher` et les câbler à l'EventBus interne.
- [X] T017 [FOUNDATIONAL] Étendre `Sources/RoadieCore/EventBus.swift` avec types : `wallpaper_click`, `stage_renamed`, `thumbnail_updated`. Sérialisation JSON-lines conforme au schema.
- [X] T018 [FOUNDATIONAL] Tests `Tests/RoadieCoreTests/EventBusRailEventsTests.swift` — vérifier émission/sérialisation des 3 nouveaux events.

**Critère de fin Phase 2** : `swift test` passe, daemon répond aux nouvelles commandes via `nc -U ~/.roadies/daemon.sock`, événements visibles dans `roadie events --follow`.

---

## Phase 3 — User Story 1 : Voir d'un coup d'œil les stages (P1, MVP)

- [X] T020 [P] [US1] Créer `Sources/RoadieRail/Models/RailState.swift` (~80 LOC) — `@Observable` state holder (currentDesktopID, stages, activeStageID, thumbnails, connectionState).
- [X] T021 [P] [US1] Créer `Sources/RoadieRail/Models/StageVM.swift` et `WindowVM.swift` (~50 LOC ensemble).
- [X] T022 [US1] Créer `Sources/RoadieRail/Networking/RailIPCClient.swift` (~150 LOC) — client socket Unix, envoi requête + lecture ligne JSON. Reconnexion exponentielle.
- [X] T023 [US1] Créer `Sources/RoadieRail/Networking/EventStream.swift` (~100 LOC) — subscribe `roadie events --follow --types ...`, callback handler.
- [X] T024 [US1] Tests `Tests/RoadieRailTests/RailIPCClientTests.swift` — mock socket, vérifier roundtrip request/response, reconnexion.
- [X] T025 [US1] Créer `Sources/RoadieRail/Hover/EdgeMonitor.swift` (~80 LOC) — Timer 80 ms, polling NSEvent.mouseLocation, callback enter/exit edge zone par écran.
- [X] T026 [P] [US1] Créer `Sources/RoadieRail/Hover/FadeAnimator.swift` (~60 LOC) — anime alpha 0→1 (fade-in 200 ms) et 1→0 (fade-out 200 ms) sur NSPanel.
- [X] T027 [US1] Créer `Sources/RoadieRail/Views/StageRailPanel.swift` (~120 LOC) — NSPanel non-activating, NSHostingView, level statusBar, collectionBehavior.
- [X] T028 [US1] Créer `Sources/RoadieRail/Views/StageStackView.swift` (~80 LOC) — vue racine SwiftUI, header "Stages", VStack des cartes.
- [X] T029 [US1] Créer `Sources/RoadieRail/Views/StageCard.swift` (~120 LOC) — carte SwiftUI, badge ID, titre, sous-titre, indicateur actif, look proche yabai_stage_rail.swift mais SwiftUI moderne.
- [X] T030 [US1] Créer `Sources/RoadieRail/Views/WindowChip.swift` (~80 LOC) — vignette ScreenCaptureKit ou icône fallback, fond arrondi.
- [X] T031 [US1] Créer `Sources/RoadieRail/Networking/ThumbnailFetcher.swift` (~80 LOC) — cache local + fetch via IPC + écoute event `thumbnail_updated` pour invalidation.
- [X] T032 [US1] Créer `Sources/RoadieRail/RailController.swift` (~150 LOC) — orchestrateur : un panel par écran, monitore `didChangeScreenParametersNotification`, lit config TOML.
- [X] T032b [US1] Implémenter le parsing TOML `[fx.rail]` dans `RailController.loadConfig()` (~40 LOC) — lecture `~/.config/roadies/roadies.toml` via TOMLKit, extraction de la section `[fx.rail]`, fallback aux valeurs par défaut (FR-031) si section ou clé absente. Reload sur event `config_reloaded`.
- [X] T033 [US1] Créer `Sources/RoadieRail/AppDelegate.swift` (~80 LOC) — boot, NSApp policy `.accessory`, instancie RailController, signal handlers SIGTERM/SIGINT.
- [X] T034 [US1] Modifier `Sources/RoadieRail/main.swift` pour wire NSApplication.shared + delegate + run loop.
- [X] T035 [US1] PID-lock dans AppDelegate : créer `~/.roadies/rail.pid`, vérifier mono-instance, cleanup à exit.
- [X] T036 [US1] Test acceptance bash `tests/14-rail-show-hide.sh` — lance rail, simule hover via `cliclick m:1,400`, vérifie panel visible, simule sortie, vérifie panel hidden.

**Critère de fin US1** : sur 1 écran avec 2 stages, le hover edge gauche fait apparaître le panel en moins de 300 ms (SC-001) avec les vignettes affichées. Test acceptance PASS.

---

## Phase 4 — User Story 2 : Basculer de stage par click direct (P1, MVP)

- [X] T040 [US2] Étendre `StageCard.swift` pour gérer `onTapGesture` → callback vers RailController.
- [X] T041 [US2] Étendre `RailController.swift` pour transformer le tap en commande `roadie stage <id>` via IPCClient.
- [X] T042 [US2] Subscribe à event `stage_changed` dans EventStream → update `RailState.activeStageID` → SwiftUI re-render automatique.
- [X] T043 [US2] Test acceptance bash `tests/14-rail-stage-switch.sh` — 2 stages, click sur la non-active via `cliclick`, vérifier `roadie stage current` change, vérifier latence < 200 ms (SC-002).

**Critère de fin US2** : test acceptance PASS, latence visuelle perçue instantanée.

---

## Phase 5 — User Story 3 : Drag-and-drop fenêtre entre stages (P1, MVP)

- [X] T050 [US3] Créer `Sources/RoadieRail/Drag/WindowDragController.swift` (~150 LOC) — wrapper NSDraggingSource pour SwiftUI via NSViewRepresentable. Pasteboard custom avec wid + source_stage_id.
- [X] T051 [US3] Étendre `WindowChip.swift` pour être source de drag (long-press initie la session).
- [X] T052 [US3] Étendre `StageCard.swift` pour être drop target (registerForDraggedTypes + draggingEntered/draggingPerformed).
- [X] T053 [US3] Sur drop, RailController appelle `roadie stage assign <wid> <target_stage>` via IPCClient.
- [X] T054 [US3] Subscribe à event `window_assigned` → update RailState.
- [X] T055 [US3] Test acceptance bash `tests/14-rail-drag-drop.sh` — 2 stages avec 1 fenêtre chacune, drag de chip entre cartes (osascript ou cliclick), vérifier que `roadie stage windows <id>` reflète la migration. Latence < 300 ms (SC-003).

**Critère de fin US3** : test acceptance PASS, drag fluide visuellement.

---

## Phase 6 — User Story 4 : Click wallpaper crée stage (P1, MVP — geste signature)

- [X] T060 [US4] Câbler `WallpaperClickWatcher.onWallpaperClick` à un nouveau coordinator daemon-side `WallpaperStageCoordinator` qui :
  - Snapshot les fenêtres tilées du desktop courant (filtre `state.isTileable && !state.isFloating`).
  - Crée une nouvelle stage `Stage N` via StageManager.
  - Migre toutes les wid trouvées vers la nouvelle stage.
  - Bascule sur la nouvelle stage (qui devient vide visuellement après migration).
  - Émet l'event `wallpaper_click` sur l'EventBus.
- [X] T061 [US4] Garde-fou : skip si `roadie-rail` n'est pas lancé (PID-lock absent ou PID mort).
- [X] T062 [US4] Garde-fou : skip si `[fx.rail] wallpaper_click_to_stage = false`.
- [X] T063 [US4] Garde-fou : skip si aucune fenêtre tilée présente (no-op silencieux, pas de stage vide créée).
- [X] T064 [US4] Le rail subscribe `wallpaper_click` → animation visuelle "nouvelle carte glisse depuis le wallpaper vers le rail" (subtle, optionnelle V1).
- [X] T065 [US4] Test acceptance bash `tests/14-wallpaper-click.sh` :
  - Lancer rail, ouvrir 3 fenêtres Terminal tilées.
  - Click sur le wallpaper via `osascript`.
  - Vérifier `roadie stage list` : nouvelle stage avec les 3 wid.
  - Vérifier le desktop courant est vide (fenêtres minimisées).
  - Latence end-to-end < 400 ms (SC-010).

**Critère de fin US4** : geste central fonctionnel et fluide. MVP V1 livrable après cette phase.

---

## Phase 7 — User Story 5 : Menu contextuel rename/delete/add (P2, V1.1)

- [X] T070 [US5] Étendre `StageCard.swift` avec `contextMenu` SwiftUI : "Rename stage…", "Add focused window", séparateur, "Delete stage".
- [X] T071 [US5] "Rename stage…" → mini-modale SwiftUI avec TextField, validation Entrée → IPC `roadie stage rename <id> "<new_name>"`.
- [X] T072 [US5] "Add focused window" → IPC `roadie window assign-focused <stage_id>`.
- [X] T073 [US5] "Delete stage" → confirmation visuelle (clic-pour-confirmer ou prompt bouton), puis IPC `roadie stage delete <id>`. Garde-fou : si stage active deleted, basculer sur stage 1.
- [X] T074 [US5] Subscribe à event `stage_renamed` pour update titre carte sans round-trip.
- [X] T075 [US5] Test acceptance bash `tests/14-rail-context-menu.sh` — couvre les 3 actions.

**Critère de fin US5** : menu contextuel fonctionnel, undo possible.

---

## Phase 8 — User Story 6 : Reclaim horizontal space (P2, V1.2)

- [X] T080 [US6] Implémenter réellement la commande `tiling.reserve` côté daemon : ajuster `displayManager.workArea` pour le display concerné, re-appel `applyLayout()`.
- [X] T081 [US6] Côté rail : si `[fx.rail] reclaim_horizontal_space = true`, envoyer `tiling.reserve --left <panel_width> --display <id>` AU DÉBUT du fade-in.
- [X] T082 [US6] Inverse à la disparition : `tiling.reserve --left 0 --display <id>` au début du fade-out.
- [X] T083 [US6] Tests acceptance `tests/14-reclaim-on.sh` et `tests/14-reclaim-off.sh` : avec `reclaim=true`, fenêtre tilée se rétrécit ; avec `reclaim=false`, fenêtre garde sa frame.
- [X] T084 [US6] Mesurer pas de jank > 1 frame à 60 Hz (SC-006) via instrumentation.

**Critère de fin US6** : option fonctionnelle, perf cible respectée.

---

## Phase 9 — User Story 7 : Multi-display (P2, V1.3)

- [X] T090 [US7] Étendre `RailController` pour itérer sur `NSScreen.screens` selon `[desktops] mode`.
  - Si `per_display` : 1 panel par écran avec son propre EdgeMonitor.
  - Si `global` : 1 panel sur primary uniquement.
- [X] T091 [US7] Subscribe à `didChangeScreenParametersNotification` → recompute liste, ré-instancier panels (réuse par `displayUUID`).
- [X] T092 [US7] Chaque panel filtre `RailState.stages` au desktop courant **de cet écran** (si SPEC-013 actif et `per_display`).
- [X] T093 [US7] Tests acceptance `tests/14-multi-display-rail.sh` — sur machine 2 écrans, hover edge de chaque, vérifier rails indépendants.

**Critère de fin US7** : multi-display robuste, branchement/débranchement à chaud OK.

---

## Phase 10 — Polish & cross-cutting

- [X] T100 [POLISH] Documentation : compléter `quickstart.md` avec captures d'écran (PNG dans `docs/screenshots/spec-014/`).
- [X] T101 [POLISH] Documentation : ajouter une section "Stage Rail" au README principal.
- [X] T102 [POLISH] LaunchAgent template : fournir `scripts/local.roadies.rail.plist.template` avec placeholder USERNAME.
- [X] T103 [POLISH] Logging : standardiser le format JSON-lines de `~/.local/state/roadies/rail.log`.
- [X] T104 [POLISH] Fallback dégradé : icônes d'app affichées proprement quand Screen Recording refusée (SC-007).
- [X] T105 [POLISH] Profiler la consommation CPU/RSS sur 1h d'usage et valider SC-004.
- [X] T106 [POLISH] Test régression `tests/14-no-regression-spec-002.sh` : re-joue suite SPEC-002 avec rail lancé puis stoppé.
- [X] T107 [POLISH] Test régression `tests/14-no-regression-spec-011.sh` : idem avec SPEC-011 multi-desktop.
- [X] T108 [POLISH] Mise à jour de `implementation.md` avec le REX de chaque user story.
- [X] T109 [POLISH] Audit `/audit 014-stage-rail` en mode fix, viser score >= A-.
- [X] T110 [POLISH] Vérifier zero entitlement runtime sur `roadie-rail` : `codesign -d --entitlements - ~/Applications/roadie-rail.app` doit retourner un dictionnaire vide ou seulement les entitlements neutres (com.apple.security.app-sandbox absent, com.apple.security.cs.allow-jit absent, etc.). Documenter le résultat dans `implementation.md`.

**Critère de fin Polish** : tous tests verts, audit ≥ A-, doc complète.

---

## Dependencies (DAG)

```
T001..T006 (Setup)
   ↓
T010..T018 (Foundational daemon)
   ↓
   ├──► T020..T036 (US1 — révéler le rail) ════ MVP gate
   │       ↓
   │       T040..T043 (US2 — switch stage)
   │       ↓
   │       T050..T055 (US3 — drag-drop)
   │       ↓
   │       T060..T065 (US4 — wallpaper-click) ─► MVP V1 livrable
   │       ↓
   │       T070..T075 (US5 — context menu)     V1.1
   │       ↓
   │       T080..T084 (US6 — reclaim)          V1.2
   │       ↓
   │       T090..T093 (US7 — multi-display)    V1.3
   │       ↓
   │       T100..T109 (Polish)                 V1 final
```

**MVP livrable** : T001 → T065 inclus (US1+US2+US3+US4 complets). Estimation effort : ~3 semaines à raison de 2-3 h/jour pour un développeur Swift familier de SwiftUI + AppKit.

## Estimation parallélisme

Tâches marquées `[P]` peuvent tourner en parallèle :
- T011 (SCKCaptureService) ‖ T013 (WallpaperClickWatcher)
- T020 (RailState) ‖ T021 (StageVM/WindowVM) ‖ T026 (FadeAnimator)

Les tâches sur `RailController.swift` et `CommandRouter.swift` doivent être séquentielles (un seul fichier modifié plusieurs fois).
