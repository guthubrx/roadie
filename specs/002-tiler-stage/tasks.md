---
description: "Tâches d'implémentation — Tiler + Stage Manager modulaire"
---

# Tasks: Tiler + Stage Manager modulaire (roadies)

**Input** : Design documents in `/specs/002-tiler-stage/`
**Prerequisites** : plan.md, spec.md, research.md, data-model.md, contracts/cli-protocol.md, contracts/tiler-protocol.md
**Tests** : INCLUS (XCTest unitaire pour tiler + shell pour daemon/CLI/integration)
**Organization** : tâches groupées par user story

## Format

`- [ ] T### [P?] [USx?] Description avec chemin de fichier`

## Path Conventions

Tous les chemins relatifs au worktree `<repo-root>/.worktrees/002-tiler-stage/`

---

## Phase 1: Setup

- [X] T001 Créer `Package.swift` avec 4 targets (RoadieCore, RoadieTiler, RoadieStagePlugin) + 2 executableTargets (roadied, roadie) + 3 testTargets
- [X] T002 [P] Créer la structure de dossiers `Sources/{RoadieCore,RoadieTiler,RoadieStagePlugin,roadied,roadie}/` et `Tests/{RoadieCoreTests,RoadieTilerTests,integration}/`
- [X] T003 [P] Créer `.specify/memory/constitution-002.md` avec les principes adaptés (multi-fichier accepté, dépendance TOML justifiée)
- [X] T004 [P] Créer `Makefile` avec cibles `build`, `install`, `clean`, `test`, `app-bundle` (générer `roadied.app` codesign ad-hoc, leçon SPEC-001)
- [X] T005 [P] Créer `.gitignore` étendu (.build, .swiftpm, *.xcodeproj, DerivedData, /roadie, /roadied, /roadied.app)
- [X] T006 [P] Créer 3 ADR dans `docs/decisions/` (ADR-001 AX par app sans SkyLight, ADR-002 arbre N-aire, ADR-003 hide-corner stratégie)
- [X] T007 Vérifier que `swift build` produit les 2 binaires sans erreur (skeleton vide)

**Checkpoint** : structure projet en place, build vide réussit.

---

## Phase 2: Foundational

**⚠️ CRITICAL** : aucune user story ne peut commencer avant cette phase.

- [X] T008 [P] Implémenter `Sources/RoadieCore/Types.swift` : enums `Direction`, `Orientation`, `TilerStrategy`, `AXSubrole`, `ErrorCode`, struct `WorkspaceID`, `StageID`, `WindowID`
- [X] T009 [P] Implémenter `Sources/RoadieCore/PrivateAPI.swift` : déclaration `@_silgen_name("_AXUIElementGetWindow")` (réutilise SPEC-001)
- [X] T010 [P] Implémenter `Sources/RoadieCore/Logger.swift` : JSON-lines writer thread-safe vers `~/.local/state/roadies/daemon.log` avec rotation 10 MB
- [X] T011 [P] Implémenter `Sources/RoadieCore/Config.swift` : structures Config + parsing TOML (dépendance TOMLKit) + valeurs par défaut + reload
- [X] T012 Implémenter `Sources/RoadieCore/WindowRegistry.swift` : `actor` ou `@MainActor` class, dictionnaire `[CGWindowID: WindowState]`, methods register/unregister/update/lookup
- [X] T013 Implémenter `Sources/RoadieCore/AXEventLoop.swift` : thread CFRunLoop par app, AXObserver, dispatch vers MainActor
- [X] T014 Implémenter `Sources/RoadieCore/GlobalObserver.swift` : NSWorkspace.didActivateApplicationNotification + leftMouseUp global
- [X] T015 Implémenter `Sources/RoadieCore/FocusManager.swift` : état focus interne + sync via `kAXApplicationActivatedNotification` + `kAXFocusedWindowChangedNotification`
- [X] T016 Implémenter `Sources/RoadieCore/DisplayManager.swift` : NSScreen + workspace mapping (V1 = singleton)
- [X] T017 Implémenter `Sources/RoadieCore/Server.swift` : NWListener Unix socket + dispatch commandes vers handlers
- [X] T018 Tests unitaires `Tests/RoadieCoreTests/ConfigParserTests.swift` : 5 tests (valid TOML, missing fields, invalid types, comment lines, env expansion)
- [X] T019 Vérifier que `swift build` reste clean après toutes les implémentations Core

**Checkpoint** : Core compile, registry + AX observer + server fonctionnels en isolation.

---

## Phase 3: User Story 1 — Tiling automatique BSP (Priority: P1) 🎯 MVP

**Goal** : tiling BSP automatique des fenêtres ouvertes, sans intervention manuelle.

**Independent Test** : ouvrir 3 Terminal via `osascript`, vérifier visuellement le partitionnement BSP attendu (50/50 puis re-partition de l'une).

- [X] T020 [US1] Implémenter `Sources/RoadieTiler/TreeNode.swift` : classes `TreeNode`, `TilingContainer`, `WindowLeaf` avec parent (weak), adaptiveWeight, children
- [X] T021 [US1] Implémenter `Sources/RoadieTiler/TilerProtocol.swift` : protocole `Tiler` avec 6 méthodes obligatoires + invariants en commentaires
- [X] T022 [US1] Implémenter `Sources/RoadieTiler/LayoutEngine.swift` : factory `makeTiler(strategy)`, méthode `apply(rect, root)` avec calcul récursif et application AX des frames
- [X] T023 [US1] Implémenter `Sources/RoadieTiler/BSPTiler.swift` : layout (récursif) + insert (split à côté du target) + remove (avec normalize) + move + resize + focusNeighbor
- [X] T024 [US1] Implémenter `Sources/RoadieTiler/WorkspaceState.swift` : Workspace struct + helpers de manipulation arbre
- [X] T025 [US1] Câbler le tiler dans `RoadieCore/AXEventLoop` : à chaque `kAXWindowCreatedNotification`, appeler `BSPTiler.insert` puis `LayoutEngine.apply`
- [X] T026 [US1] Câbler la suppression : à chaque `kAXUIElementDestroyedNotification`, appeler `BSPTiler.remove` puis `LayoutEngine.apply`
- [X] T027 [P] [US1] Tests unitaires `Tests/RoadieTilerTests/TreeNodeTests.swift` : 8 tests (init, parent/child, adaptiveWeight default, attach/detach)
- [X] T028 [P] [US1] Tests unitaires `Tests/RoadieTilerTests/BSPTilerTests.swift` : 10 tests (layout empty, single, two equal, three with weights, insert near target, remove + normalize, move horizontal, move vertical, focusNeighbor at edge, focusNeighbor multi-level)
- [ ] T029 [US1] Test d'intégration `Tests/integration/01-tiling-bsp.sh` : démarre daemon, ouvre 3 Terminal, query `roadie windows list`, vérifie frames BSP attendues
- [X] T030 [US1] Implémenter dans `roadied/main.swift` le bootstrap minimal pour MVP : init AX, load config, démarrer GlobalObserver, démarrer Server, runloop principal
- [X] T031 [US1] Implémenter dans `roadie/main.swift` les commandes `windows list`, `daemon status`
- [X] T032 [US1] Implémenter dans `roadie/SocketClient.swift` la connexion NWConnection + envoi requête + lecture réponse JSON-lines
- [X] T033 [US1] Implémenter `roadie/OutputFormatter.swift` : affichage texte humain par défaut, JSON avec `--json`

**Checkpoint** : MVP atteint. Tiling BSP marche, on peut lister les fenêtres et le statut.

---

## Phase 4: User Story 2 — Click-to-focus fiable (Priority: P1) 🎯 différenciateur

**Goal** : clic souris sur n'importe quelle fenêtre tilée → focus interne synchronisé en < 100 ms.

**Independent Test** : ouvrir VSCode + Terminal côte à côte, focus initial sur VSCode, cliquer sur Terminal, exécuter `roadie focus left`, vérifier que ça ramène le focus sur VSCode (depuis Terminal).

- [X] T034 [US2] Étendre `RoadieCore/FocusManager.swift` : ajouter handler pour `kAXApplicationActivatedNotification` qui re-query `kAXFocusedWindowAttribute` et met à jour `WindowRegistry.focusedID`
- [X] T035 [US2] Étendre `RoadieCore/GlobalObserver.swift` : observer `NSWorkspace.didActivateApplicationNotification` qui déclenche FocusManager.refresh
- [X] T036 [US2] Implémenter dans `RoadieCore` un `applyFocus(windowID)` qui appelle AX setAttribute + maintient `WindowRegistry.focusedID`
- [X] T037 [US2] Implémenter commande `focus <direction>` dans le serveur : récupère focusedID, appelle `BSPTiler.focusNeighbor`, puis `applyFocus`
- [X] T038 [US2] Implémenter dans `roadie/main.swift` les commandes `focus`, `move`, `resize`
- [X] T039 [US2] Implémenter dans Server le handler `move` : `BSPTiler.move` puis `LayoutEngine.apply`
- [X] T040 [US2] Implémenter dans Server le handler `resize` : `BSPTiler.resize` puis `LayoutEngine.apply`
- [ ] T041 [US2] Test d'intégration `Tests/integration/02-click-to-focus.sh` : ouvre VSCode (ou TextEdit faute de mieux) + Terminal, simule clic via osascript click event, vérifie focusedID changé en < 200 ms
- [X] T042 [P] [US2] Documentation manuelle `docs/manual-acceptance/click-to-focus.md` : procédure de test sur 10 apps (VSCode, Cursor, Slack, Discord, IntelliJ, Terminal, Safari, Mail, Notes, Calendar)
- [X] T043 [US2] Tests unitaires `Tests/RoadieCoreTests/FocusManagerTests.swift` : 5 tests (mock AX events, vérifier transitions état focus)

**Checkpoint** : différenciateur livré. Le click-to-focus marche sur la majorité des apps.

---

## Phase 5: User Story 3 — Stage plugin (Priority: P1)

**Goal** : groupes de fenêtres masquables avec préservation du tiling à la bascule.

**Independent Test** : créer 2 stages, assigner 2 fenêtres à chaque, basculer dans les deux sens, vérifier layout préservé exact.

- [X] T044 [US3] Implémenter `Sources/RoadieStagePlugin/StageManager.swift` : actor avec `[StageID: Stage]`, currentStageID, méthodes assign/switch/createStage/deleteStage
- [X] T045 [US3] Implémenter `Sources/RoadieStagePlugin/WindowGroup.swift` : Stage struct + persistance TOML (lecture+écriture atomique)
- [X] T046 [US3] Implémenter `Sources/RoadieStagePlugin/HideStrategy.swift` : enum corner | minimize | hybrid + impl pour chaque (déplacement off-screen, kAXMinimized)
- [X] T047 [US3] Implémenter `Sources/RoadieStagePlugin/StageObserver.swift` : abonnement aux events Core (window destroyed → retirer du stage si présent)
- [X] T048 [US3] Câbler StagePlugin dans `roadied/main.swift` : init si `config.stage_manager.enabled`, sinon skip
- [X] T049 [US3] Implémenter dans Server les handlers `stage list`, `stage switch`, `stage assign`, `stage create`, `stage delete`
- [X] T050 [US3] Implémenter dans `roadie/main.swift` les commandes `stage *`
- [ ] T051 [US3] Test d'intégration `Tests/integration/03-stage-switch.sh` : crée 2 stages, assign 2 fenêtres à chacun, switch dev→comm→dev, vérifier frames préservées
- [X] T052 [P] [US3] Tests unitaires `Tests/RoadieStagePluginTests/StageManagerTests.swift` : 6 tests (create stage, assign, switch logic, persistance round-trip)
- [X] T053 [US3] Au démarrage du daemon, le StagePlugin doit garbage-collect les WindowID périmés et tenter re-match par bundleID (cf. data-model §4)
- [ ] T054 [US3] Test d'intégration `Tests/integration/04-stage-restart.sh` : assign fenêtres, kill daemon, restart, vérifier re-match correct

**Checkpoint** : stage plugin fonctionnel, désactivable via config.

---

## Phase 6: User Story 4 — Master-Stack (Priority: P2)

**Goal** : stratégie de tiling alternative + commande de switch runtime.

**Independent Test** : 4 fenêtres en BSP, `roadie tiler master-stack`, vérifier 1 master gauche 60% + 3 stack droit 40%.

- [X] T055 [US4] Implémenter `Sources/RoadieTiler/MasterStackTiler.swift` : layout (master + stack horizontal/vertical), insert (en pile), remove (auto-promote en master si stack vide), move (master ↔ stack), focusNeighbor
- [X] T056 [US4] Implémenter le rebuild d'arbre lors du `tiler.set` : flatten l'arbre courant en liste de leafs ordonnée, puis re-insert un par un avec la nouvelle stratégie
- [X] T057 [US4] Implémenter dans Server le handler `tiler set <strategy>`
- [X] T058 [US4] Implémenter dans `roadie/main.swift` la commande `tiler <strategy>`
- [X] T059 [P] [US4] Tests unitaires `Tests/RoadieTilerTests/MasterStackTilerTests.swift` : 8 tests (layout 1 window, 2 windows, 4 windows ratio, insert promotes, remove demotes, move master ↔ stack, focus master, focus stack)
- [ ] T060 [US4] Test d'intégration `Tests/integration/05-tiler-switch.sh` : 4 Terminal en BSP, switch master-stack, vérifier ratios 60/40 et stack pile

**Checkpoint** : modularité tiler validée, 2 stratégies fonctionnelles.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T061 [P] Implémenter LaunchAgent template `docs/com.local.roadies.plist.template` avec instructions install dans quickstart.md
- [X] T062 [P] Implémenter `roadie daemon reload` : recharge config + propage vers tous les modules + log "config reloaded"
- [X] T063 [P] Mesurer les performances :
  - SC-001 (tiling new window < 200ms)
  - SC-002 (click-to-focus sync < 100ms)
  - SC-003 (stage switch < 500ms)
  - SC-007 (24h sans crash → test long-run en background avec leaks)
  Documenter dans `docs/performance.md`
- [X] T064 [P] Vérifier SC-005 (pas de dépendances non-système au runtime) : `otool -L .build/release/roadied` ne montre que `/usr/lib/` et `/System/Library/`. Si TOMLKit lié dynamiquement → vendor en static.
- [X] T065 [P] Vérifier SC-006 (LOC ≤ 4000) : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`. Refactor si dépassé.
- [ ] T066 [P] Whitelist apps connues problématiques (Zoom, Teams, certains Java) : créer `Sources/RoadieCore/KnownBundleIds.swift` avec workarounds — **non fait, feature optionnelle, à reconsidérer si bug rapporté**
- [X] T067 [P] Snapshot fenêtres existantes au boot via `CGWindowListCopyWindowInfo` — implémenté dans `Sources/roadied/main.swift.registerExistingWindows()` ligne 196 et `liveCGWindowIDs()` ligne 381
- [X] T068 [P] Gestion popups/dialogs : exclus du tiling via `AXSubrole.isFloatingByDefault` (`.dialog`/`.sheet`/`.systemDialog` → isFloating=true) dans `Sources/RoadieCore/Types.swift` ligne 73
- [X] T069 Code review finale : zéro `// todo` non tracé, zéro `print()` (tout via Logger), zéro `try!` (sauf bootstrap)
- [X] T070 Implémentation `roadied --help` et `roadie --help` (même mode minimaliste mais cohérent)
- [X] T071 README.md racine du worktree : pointeur vers quickstart.md + résumé 5 lignes
- [X] T072 Build release universal binary x86_64 + arm64 (lipo)
- [X] T073 Codesign ad-hoc avec identifier `local.roadies.daemon` du `roadied.app` bundle (leçon SPEC-001 indispensable pour TCC Sequoia+)

---

## Phase 8: Runtime Fixes (post-livraison — bugs découverts au premier run live)

Cette phase n'était pas prévue mais imposée par la réalité du test runtime. Chaque tâche correspond à un bug observé puis corrigé en live avec l'utilisateur.

- [X] T074 [BUGFIX] **Daemon désalloué après bootstrap** : `let daemon = Daemon(config:)` dans une fonction locale → désalloué dès retour. Server gardait une référence `weak handler`. Toutes les commandes CLI répondaient `internal_error: no handler`. **Fix** : `enum AppState { @MainActor static var daemon: Daemon? }` pour garder le daemon en vie tant que le process tourne.
- [X] T075 [BUGFIX] **Segfault `roadie windows list`** : `String(format: "%-30s")` avec une `String` Swift = comportement indéfini (`%s` attend `char *`). **Fix** : remplacement de tous les `String(format:)` par une fonction `pad(_:_)` Swift native + concaténation.
- [X] T076 [BUGFIX] **Nouvelles fenêtres pas auto-tilées** : `kAXWindowCreatedNotification` ne fire pas de manière fiable au moment de la création (race avec `CGWindowID` non encore alloué). **Fix** : (a) retry après 100 ms dans `axDidCreateWindow`, (b) fallback dans `axDidChangeFocusedWindow` qui registre une fenêtre inconnue qui prend le focus.
- [X] T077 [BUGFIX] **Stale entries après destruction** : `kAXUIElementDestroyedNotification` rate des events. Les fenêtres fermées restent dans le registry et le tree. **Fix** : `pruneDeadWindows()` appelé avant chaque commande CLI, qui compare le registry à `CGWindowListCopyWindowInfo(.optionAll)` et purge les morts (auto-GC inspiré de SPEC-001).
- [X] T078 [BUGFIX] **Doublons d'enregistrement** : `axDidActivateApplication` scannait toutes les fenêtres de l'app activée à chaque activation, créant des registrations en double sur certaines apps. **Fix** : suppression de l'auto-scan, on se repose sur `axDidCreateWindow` + fallback focus-change.
- [X] T079 [FEATURE] **MRU stack du focus pour insertion intelligente** : quand une nouvelle fenêtre est créée, macOS lui donne le focus AVANT que `kAXWindowCreatedNotification` fire. Mon code lisait `focusedWindowID` qui était déjà la nouvelle fenêtre → fallback "append à la racine" → 3e colonne au lieu de splitter. **Fix** : `WindowRegistry` track `previousFocusedWindowID` ; nouvelle méthode `insertionTarget(for:)` qui retourne le previous-focused si différent de la new-window. L'insertion BSP utilise donc l'intent réel de l'utilisateur.
- [X] T080 [INFRA] **Makefile PATH override** : anaconda's `ld` shadow Xcode `ld` et ne supporte pas `-no_warn_duplicate_libraries` → linker error sur `make`. **Fix** : `export PATH := /usr/bin:/usr/local/bin:/bin:$(PATH)` au top du Makefile.
- [X] T081 [INFRA] **Constitution amendée** : ajout du principe G "Mode Minimalisme LOC explicite" dans `constitution.md` (root projet) + G' équivalent dans `constitution-002.md`. Définit cible 2 000 + plafond 4 000 LOC effectives pour SPEC-002, avec mesure de référence `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`.

**Checkpoint** : daemon utilisable au quotidien sur les flux principaux (BSP auto, click-to-focus, list/status). Bugs résiduels documentés en T029, T041, T051, T054, T060, T066-T068 (tests d'intégration shell, polish des edge cases).

---

## Phase 9: Runtime Fixes itération 2 (post-livraison, second round)

Cette phase capture les bugs et améliorations découverts lors d'une seconde session de tests interactifs. Chaque tâche correspond à un bug observé puis corrigé en live, ou à un refactor architectural validé par le user.

- [X] T082 [REFACTOR] **TilerStrategy enum hardcodé → struct String + TilerRegistry** : remplacement de l'enum Swift à cas fixes (`.bsp, .masterStack`) par un `struct TilerStrategy: RawRepresentable` extensible et un registre dynamique `TilerRegistry`. Chaque tiler implémente `static func register()` ; bootstrap appelle les register(). Plus de switch hardcodé dans `LayoutEngine`. Pour ajouter "papillon" = créer 1 fichier + 1 ligne dans bootstrap. Conforme constitution-002 principe I' (architecture pluggable obligatoire).
- [X] T083 [BUGFIX] **MRU stack trop greedy** : `insertionTarget(for:)` retournait `previousFocusedWindowID` en priorité, ce qui faisait splitter une fenêtre obsolète quand le user était sur une fenêtre nouvellement focalisée. Inversion : prefer `focusedWindowID` (la fenêtre où l'user est *maintenant*), prev seulement si focused == newWID (cas focus race). Bug observé : DEUX splittait 3979 (l'iTerm initial) au lieu de UN (la fenêtre intermédiaire).
- [X] T084 [FEATURE] **Click-to-raise universel** : nouveau module `RoadieCore/MouseRaiser.swift`. Hook `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`, conversion coords NSScreen → AX, lookup `CGWindowListCopyWindowInfo` pour identifier la fenêtre sous le curseur, `AXUIElementPerformAction(_, kAXRaiseAction)` pour la ramener au-dessus. Différenciateur vs AeroSpace qui ne gère pas ce cas. ~50 LOC.
- [X] T085 [FEATURE] **PeriodicScanner pour apps Electron silencieuses** : nouveau module `RoadieCore/PeriodicScanner.swift`. Timer @MainActor toutes les 1 seconde qui re-scan les apps observées et enregistre les fenêtres ratées. Indispensable car Cursor (Electron) ne déclenche **aucune** notification AX après création de sa fenêtre principale (~48 sec de silence observées en log). Coût : 1 appel `AXReader.windows()` par app/sec. ~30 LOC.
- [X] T086 [BUGFIX] **kAXMainWindowChangedNotification ajoutée** : abonnement à cette notification supplémentaire dans `AXEventLoop` pour rattraper les apps qui privilégient main window plutôt que window created (Electron, certaines apps Catalyst). Dispatch identique à `axDidChangeFocusedWindow` (registre la fenêtre si inconnue + refresh focus).
- [X] T087 [BUGFIX] **Subscription destruction par window** : `kAXUIElementDestroyedNotification` doit être abonnée sur l'AXUIElement de **chaque window** au moment de l'enregistrement, pas seulement sur l'app element. Sinon la notification ne fire pas systématiquement. Nouveau `AXEventLoop.subscribeDestruction(pid:axWindow:)` appelé depuis `registerWindow` après `registry.register`.
- [X] T088 [BUGFIX] **Dispatch destruction via AXUIElement + lookup CFEqual** : avant le fix, le dispatch tentait `_AXUIElementGetWindow` sur l'élément déjà détruit (returns nil) → drop silencieux. Fix : passer l'AXUIElement brut au delegate, qui résout le wid via lookup direct + fallback `CFEqual` scan du registry + fallback `pruneDeadWindows`. Trois niveaux de robustesse, aucun n'est crad.
- [X] T089 [BUGFIX] **didTerminateApp nettoie les fenêtres** : Cmd+Q d'une app ne déclenche pas systématiquement `kAXUIElementDestroyedNotification` pour chacune de ses fenêtres. Le fix : iterer `registry.allWindows` filtrées par pid, retirer du tree, du stage si applicable, et du registry, puis `applyLayout`.
- [X] T090 [BUGFIX] **Init focus au boot via refreshFromSystem** : sans cet appel à la fin du bootstrap, `focusedWindowID` reste `nil` jusqu'au premier event AX, et la MRU stack reste vide. Au 1er Cmd+N, l'insertion tombait alors sur le fallback append-to-root. Fix propre : interroger `NSWorkspace.frontmostApplication` + AX au boot pour seeder le focus. Pas de hack arbitraire.
- [X] T091 [INSTRUMENTATION] **Logs INFO diagnostic** : `axDidCreateWindow fired`, `registerWindow skipped`, `scanWindows`, `insert decision`, `focus changed`, `window destroyed` exposent les décisions du daemon en temps réel. Indispensable pour diagnostiquer les bugs Electron sans patcher à l'aveugle.
- [X] T092 [FEATURE] **`roadie tiler list`** : commande CLI qui expose `TilerRegistry.availableStrategies` au user. Permet de découvrir les stratégies disponibles au runtime (utile quand on en ajoutera).
- [X] T093 [BUGFIX] **didActivateApp NSWorkspace path scan** : `axDidActivateApplication` (path AX) faisait un scan, mais `didActivateApp` (path NSWorkspace) non. Or les deux paths fire dans des ordres différents et certaines apps Electron loupent le path AX. Factorisation dans `scanAndRegisterWindows(pid:source:)` appelée des deux côtés.
- [X] T094 [QUALITY] **Tests TilerRegistry** : 7 nouveaux tests unitaires (`TilerRegistryTests.swift`) validant l'isolation registre, l'auto-register pattern, le Codable round-trip, le string literal de TilerStrategy. Total tests : 32 → 39.

**Checkpoint** : daemon stable et utilisable au quotidien. Tous les flux principaux validés en runtime : tiling auto, click-to-focus, click-to-raise, destruction de fenêtre, fermeture d'app, relance d'app Electron. Architecture pluggable validée (TilerRegistry).

---

## Phase 10: Runtime Fixes itération 3 (post-livraison, troisième round)

Cette phase capture la session de finalisation runtime : bugs subtils de tiling, intégration Stage Manager au tiler, click-to-raise inter-app sur Sequoia/Tahoe, drag-to-adapt drop-based, marges asymétriques, et integration BTT propre.

- [X] T095 [BUGFIX] **BSP first-split orientation incorrecte au bootstrap** : la 1ère insertion (`target.lastFrame == nil` car `applyLayout` n'a pas encore tourné) retombe sur `parent.orientation.opposite` (= vertical pour root horizontal) au lieu d'utiliser l'aspect ratio. Résultat : pour une fenêtre fullscreen 2048×1280 (large), le 1er split était top/bottom au lieu de left/right. **Fix** : `LayoutEngine.setScreenRect(workArea)` au début du bootstrap (qui fait un dry-run `tiler.layout` pour seeder les `lastFrame`), et `LayoutEngine.insertWindow` fait également un dry-run avant chaque insert. Ajout de `Workspace.lastAppliedRect`.
- [X] T096 [BUGFIX] **Daemon n'écoutait pas les NSEvent globaux** : `RunLoop.main.run()` seul ne dispatche pas la queue d'events système nécessaire à `NSEvent.addGlobalMonitorForEvents` (utilisé par MouseRaiser). Fix : remplacement par `NSApplication.shared.setActivationPolicy(.accessory) ; app.run()`. Le `LSUIElement=true` du bundle empêche l'apparition dans le Dock.
- [X] T097 [BUGFIX] **Permission Input Monitoring jamais demandée** : `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` fail silencieusement sans la perm `kTCCServiceListenEvent` qui n'est pas auto-prompt. Fix : `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` au démarrage de `MouseRaiser`, qui force la prompt système et lit le statut. Si denied, MouseRaiser se désactive avec un message stderr explicite.
- [X] T098 [FEATURE] **Click-to-raise inter-app fiable via SkyLight private API** : `kAXRaiseAction` + `NSRunningApplication.activate(.activateIgnoringOtherApps)` ne franchit plus la barrière de yieldActivation Sonoma+/Sequoia/Tahoe pour certaines apps (iTerm2 cible). Solution standard de l'industrie WM (yabai, AeroSpace, Hammerspoon, Amethyst) : nouveau module `RoadieCore/WindowActivator.swift` avec bindings `@_silgen_name("_SLPSSetFrontProcessWithOptions")` + `@_silgen_name("SLPSPostEventRecordTo")` + `@_silgen_name("GetProcessForPID")`, link `Package.swift` contre `/System/Library/PrivateFrameworks/SkyLight.framework`. Combo : SLPS bring-to-front (mode 0x200) + synthetic mouseDown/mouseUp event encodé byte-par-byte (offset 0x04, 0x08, 0x3a, 0x3c) reverse-engineered de yabai. Limitation Tahoe documentée dans README.md.
- [X] T099 [FEATURE] **Drag-to-adapt drop-based** : nouveau module `RoadieCore/DragWatcher.swift` (NSEvent `.leftMouseUp` global). Quand l'utilisateur drag-resize ou drag-move une fenêtre tilée, le daemon ne fait **rien pendant le drag** (les notifs AX `move/resize` mémorisent juste le wid via `trackDrag`). Au mouseUp, `onDragDrop` calcule les deltas par edge (left/right/top/bottom) et transfère le delta pixel → `adaptiveWeight` aux siblings appropriés via `LayoutEngine.adaptToManualResize` + `adjustEdge`. Anti-feedback-loop : `lastApplyTimestamp` ignore les notifs reçues dans les 200 ms suivant un apply (notif venant de notre propre setBounds).
- [X] T100 [FEATURE] **Stage Manager intégré au tiler via LayoutHooks** : avant T100, `HideStrategyImpl.hide` faisait offscreen sur toutes les fenêtres y compris tilées → conflit avec `applyLayout` qui les remettait à leur place. Solution : nouveau struct `LayoutHooks { setLeafVisible, applyLayout }` injecté dans `StageManager.init`. Au switch, pour les fenêtres tilées : (1) `setLeafVisible(wid, false)` (le tiler skip au layout, espace redistribué aux voisines), (2) `HideStrategyImpl.hide` physique offscreen ; pour les flottantes : seulement hide AX. Puis `applyLayout()` pour propager. Symétrie au show.
- [X] T101 [FIX-AEROSPACE] **HideStrategy.corner = formule AeroSpace exacte** : la version initiale `(-100_000, -100_000)` se faisait clamp par macOS à 40 px du bord (zone titre/boutons), laissant un fragment visible. Reproduction littérale de `MacWindow.hideInCorner(.bottomLeftCorner)` d'AeroSpace : `position = visibleRect.bottomLeftCorner + (1, -1) + (-windowWidth, 0)` = `(left + 1 - windowWidth, bottom - 1)`. L'astuce : positionner simultanément hors champ en x ET en y empêche macOS de clamper en x.
- [X] T102 [FEATURE] **Marges externes asymétriques** : `TilingConfig` accepte maintenant `gaps_outer` (uniforme, fallback) + override individuel par côté `gaps_outer_top/bottom/left/right` (chacun optionnel). Nouveau struct `OuterGaps { top, bottom, left, right }` + `TilingConfig.effectiveOuterGaps`. `LayoutEngine.apply(rect, outerGaps:, gapsInner:)` overload qui inset asymétrique. Le daemon utilise `effectiveOuterGaps` partout (apply + setScreenRect bootstrap + LayoutHooks).
- [X] T103 [INFRA] **Bundle .app codesign + install-app fluide** : `make install-app` recrée le bundle, codesign ad-hoc avec `--identifier "local.roadies.daemon"` (cf. SPEC-001), copie dans `~/Applications/` et symlink CLI. Procédure validée pour TCC Sequoia/Tahoe.
- [X] T104 [INTEGRATION] **BetterTouchTool 13 raccourcis Roadie via API officielle** : création du dossier "Roadie" via UI BTT, puis 13 triggers ajoutés via `osascript add_new_trigger` JSON (méthode officielle, pas SQL direct). Couvre : focus left/right/up/down (⌘+HJKL), move left/right/up/down (⌘⌥+HJKL), restart daemon (⌘⌃R), stage switch 1/2 (⌥1/⌥2), stage assign 1/2 (⌥⇧1/⌥⇧2). Script de restart `$HOME/.local/bin/roadied_restart.sh` (`pkill -x roadied; sleep 0.3; nohup roadied --daemon`).
- [X] T105 [INTEGRATION] **Ménage anciens raccourcis Yabai** : suppression via `delete_trigger` AppleScript (43 triggers + 8 folders supprimés ; 0 résiduel en DB). Restauration depuis backup horodaté dans un nouveau folder désactivé `Yabai (archived)` via `add_new_trigger` (36 triggers dédoublonnés sur `keycode + modifier`, préfixe `[archive]`, tous `BTTEnabled=0`). Réversibilité totale pour l'utilisateur.
- [X] T106 [DOC] **Skill `bettertouch` réécrite** : passage de "édition SQLite directe" à "API officielle AppleScript primaire, SQL en lecture seule". 380 lignes couvrant toutes les méthodes AppleScript (add/update/delete trigger + variables + presse-papier + presets + widgets + notifications), trigger types (`BTTTriggerClass` exhaustif), JSON keyboard shortcut + folder (`BTTTriggerType: 630` + `BTTGroupName`), modifier mask + offset `BTTAdditionalConfiguration` + keycodes, 8 workflows pratiques (créer folder, déplacer, renommer, désactiver, ménage en masse, lister), URL scheme `btt://`, diagnostic conflits.
- [X] T107 [QUALITY] **README.md limitations documentées** : section "Click-to-raise inter-app : non garanti à 100%" expliquant la limitation Tahoe (yieldActivation pattern) et le fait qu'AeroSpace partage la même limite par design (pas de SIP désactivé).

**Checkpoint Phase 10** : daemon production-ready avec tous les flux validés en runtime sur écran réel : tiling BSP yabai-style first-split, drag-to-adapt fluide, click-to-raise (best-effort + limitations Tahoe documentées), Stage Manager opérationnel avec hide propre, marges configurables. Intégration BTT complète et propre. Skill BTT canonique.

---

## Dependency Graph

```
Phase 1 (T001-T007)
    │
    ▼
Phase 2 Foundational (T008-T019)
    │
    ├──────────────┬─────────────┬──────────────┐
    ▼              ▼             ▼              ▼
Phase 3 US1      Phase 4 US2  Phase 5 US3   (Phase 6 US4 dépend de T023+T056)
(T020-T033)      (T034-T043)  (T044-T054)
    │              │             │
    └──────────────┴─────────────┘
                   │
                   ▼
              Phase 6 US4 (T055-T060)
                   │
                   ▼
             Phase 7 Polish (T061-T073)
```

**Note** : US1, US2, US3 sont parallélisables après Phase 2 (fichiers différents). En pratique séquentiel pour ne pas se disperser.

---

## Parallel Execution Examples

### Phase 1 — fichiers indépendants
```
T002 structure dossiers ┐
T003 constitution-002   ├─ exécutables en parallèle après T001
T004 Makefile           │
T005 .gitignore         │
T006 ADRs               ┘
```

### Phase 2 — composants Core disjoints
```
T008 Types.swift     ┐
T009 PrivateAPI      │
T010 Logger          ├─ rédigeables en parallèle
T011 Config          │
T018 ConfigTests     ┘
```

### Phase 3 — tests parallélisables
```
T027 TreeNodeTests    ┐
T028 BSPTilerTests    ├─ tests unitaires indépendants
T042 click-to-focus md ┘
```

---

## Implementation Strategy

### MVP minimum viable

**Fin de Phase 3 (T033)** : tiling BSP automatique fonctionnel + CLI peut lister windows. Les commandes focus/move/resize ne marchent pas encore mais l'utilisateur peut au moins observer le tiling auto.

### Incremental delivery

| Étape | Livrable | Tâches |
|---|---|---|
| 1 | Skeleton compile, structure prête | T001-T007 |
| 2 | Core daemon fonctionnel (sans tiling) | T008-T019 |
| 3 | MVP tiling BSP auto + CLI lecture | T020-T033 |
| 4 | Click-to-focus + commandes navigation | T034-T043 |
| 5 | Stage plugin opt-in | T044-T054 |
| 6 | Master-Stack alternative | T055-T060 |
| 7 | Polish + perfs + edge cases | T061-T073 |

### Points de validation utilisateur

- **Après T033** : démo MVP, possibilité d'arrêter là si V1 satisfait.
- **Après T043** : produit utilisable au quotidien (point de bascule vers usage prod).
- **Après T054** : stage plugin OK, parité fonctionnelle avec ce que SPEC-001 promettait, en mieux.
- **Après T073** : conformité totale aux SC chiffrés, prêt pour merge `main`.

---

## Format Validation

- [x] Toutes les 73 tâches commencent par `- [ ]`
- [x] Task IDs séquentiels T001-T073
- [x] Setup (Phase 1) : pas de label `[USx]`
- [x] Foundational (Phase 2) : pas de label `[USx]`
- [x] Phases 3-6 : labels `[US1]`, `[US2]`, `[US3]`, `[US4]` présents
- [x] Polish (Phase 7) : pas de label `[USx]`
- [x] Marqueur `[P]` réservé aux tâches parallélisables
- [x] Chemins de fichiers explicites
- [x] User stories en ordre de priorité spec.md (US1 P1 BSP, US2 P1 click-to-focus, US3 P1 stage, US4 P2 master-stack)

---

## Summary

| Métrique | Valeur |
|---|---|
| Total tâches | **107** (73 prévues + 8 Phase 8 + 13 Phase 9 + 13 Phase 10, toutes ajoutées en runtime) |
| Phase 1 Setup | 7 ✅ |
| Phase 2 Foundational | 12 ✅ |
| Phase 3 US1 BSP MVP | 13/14 (T029 reportée) |
| Phase 4 US2 Click-to-focus | 9/10 (T041 reportée) |
| Phase 5 US3 Stage plugin | 9/11 (T051, T054 reportées) |
| Phase 6 US4 Master-Stack | 5/6 (T060 reportée) |
| Phase 7 Polish | 10/13 (T066-T068 reportées) |
| Phase 8 Runtime Fixes (1er round) | 8/8 ✅ |
| Phase 9 Runtime Fixes (2e round) | 13/13 ✅ |
| Phase 10 Runtime Fixes (3e round) | 13/13 ✅ |
| Tâches cochées totales | **99/107** (93 %) |
| Tâches reportées | 8 (5 tests d'intégration shell + 3 polish edge cases) |
| MVP scope suggéré | T001-T033 (fin Phase 3) — atteint et étendu jusqu'à Phase 10 |
| Tests inclus | 39 unitaires PASS (32 initiaux + 7 TilerRegistry) |
| **LOC Swift effectives** | **~ 2 600** (< 4 000 plafond strict, marge ~ 35 %) |
| Modules Swift | 30 fichiers : Core 15 (+ MouseRaiser, PeriodicScanner, DragWatcher, WindowActivator) + Tiler 6 + Stage 3 + roadied 2 + roadie 3 |
