# Implementation Log — 002-tiler-stage

**Branch** : `002-tiler-stage`
**Date** : 2026-05-01
**Mode** : pipeline autonome `/my.specify-all`-like (utilisateur absent)

---

## Resume executif

| Metrique | Valeur | Cible | Status |
|---|---|---|---|
| Phases SpecKit | 1-6 enchainees autonomement + 8 runtime fixes (Phase 8) + 13 runtime fixes (Phase 9) | 1-6 | ✅ |
| spec.md | 4 user stories, 23 FR, 10 SC, status In Progress | complet | ✅ |
| plan.md | architecture 4 modules + TilerRegistry + MouseRaiser + PeriodicScanner | complet | ✅ |
| research.md | 820 lignes, etude yabai+AeroSpace | complet | ✅ |
| tasks.md | 94 taches (73 prevues + 21 runtime), 86/94 cochees (91 %) | complet | ✅ |
| Code Swift effectif | **2 299 LOC** (vs 2 009 initial, +290 pour Phase 8 + 9) | < 4 000 plafond | ✅ |
| Tests unitaires | 39 tests (32 + 7 TilerRegistry), 0 echec | 100 % pass | ✅ |
| Build daemon | ~1.7 MB | < 5 MB | ✅ |
| Build CLI | ~1.4 MB | < 500 KB | ⚠️ TOMLKit transitif (V2) |
| Audit grade | B+ post-runtime, montee vers A en cours | A vise | ⚠️ A demande tests integration shell |
| Constitution | principe G/G' LOC + I' architecture pluggable validee | n/a | ✅ |

---

## Phases executees

### Phase 0 — Recherche (820 lignes)

Agent `researcher` lance en arriere-plan, lecture de `~/11.Repositories/yabai/src/` (~30 KLOC C) et `~/11.Repositories/aerospace/Sources/` (~15 KLOC Swift). Synthese ecrite dans `research.md`.

3 decisions architecturales cles ressorties :
1. AX par app sans SkyLight ni SIP (style AeroSpace)
2. Arbre N-aire avec adaptiveWeight (style AeroSpace)  
3. Masquage en coin avec `setNativeMinimized` optionnel (style AeroSpace + amelioration)

### Phase 1 — Specify

`spec.md` redige avec :
- 4 user stories prioritisees (US1 BSP MVP, US2 click-to-focus, US3 stage plugin, US4 Master-Stack)
- 23 FR groupes par module
- 10 SC mesurables
- 10 edge cases
- Out of Scope V1 strict (10 items)

Validation `requirements.md` 13/13 PASS premiere iteration.

### Phase 2 — Plan

`plan.md` avec :
- 4 modules definis (Core 700 LOC, Tiler 940, Stage 400, CLI 200) — total estime 2240
- Constitution-002 ecrite documentant les ajustements (multi-fichier accepte, TOMLKit accepte)
- 3 ADRs ecrits dans docs/decisions/

`data-model.md` : structures Swift completes (WindowState, TreeNode, Workspace, Stage, Command, Response).

`contracts/cli-protocol.md` + `contracts/tiler-protocol.md` : contrats normatifs.

`quickstart.md` : install + first run + Karabiner/BTT bindings + LaunchAgent.

### Phase 3 — Tasks

`tasks.md` : 73 taches groupees en 7 phases :
- Phase 1 Setup (T001-T007)
- Phase 2 Foundational (T008-T019)
- Phase 3 US1 BSP MVP (T020-T033)
- Phase 4 US2 Click-to-focus (T034-T043)
- Phase 5 US3 Stage plugin (T044-T054)
- Phase 6 US4 Master-Stack (T055-T060)
- Phase 7 Polish (T061-T073)

### Phase 4 — Implementation

24 fichiers Swift produits, 2009 LOC effectives :

**RoadieCore** (11 fichiers, 764 LOC)
- Types.swift — enums et WindowState
- PrivateAPI.swift — _AXUIElementGetWindow
- Logger.swift — JSON-lines structured logging
- Config.swift — TOML config + Codable
- WindowRegistry.swift — registry MainActor
- AXEventLoop.swift — observer par app + AXReader helpers
- GlobalObserver.swift — NSWorkspace + Activate
- FocusManager.swift — sync via kAXApplicationActivatedNotification (innovation)
- DisplayManager.swift — NSScreen + workArea
- Server.swift — NWListener Unix socket
- Protocol.swift — Request/Response/AnyCodable

**RoadieTiler** (5 fichiers, 455 LOC)
- TreeNode.swift — arbre N-aire avec normalize
- TilerProtocol.swift — protocole abstrait
- BSPTiler.swift — implementation BSP
- MasterStackTiler.swift — implementation Master-Stack
- LayoutEngine.swift — orchestration + apply via AX

**RoadieStagePlugin** (3 fichiers, 232 LOC)
- HideStrategy.swift — corner / minimize / hybrid
- Stage.swift — modele Codable
- StageManager.swift — assign / switch / persistance TOML

**roadied** (2 fichiers, 328 LOC)
- main.swift — bootstrap, AXEventDelegate, GlobalObserverDelegate, CommandHandler
- CommandRouter.swift — dispatch des commandes vers les modules

**roadie** (3 fichiers, 230 LOC)
- main.swift — parse args, dispatch
- SocketClient.swift — NWConnection vers daemon
- OutputFormatter.swift — affichage texte humain

### Phase 5 — Tests

4 fichiers de tests, 321 LOC, 32 tests :

- TreeNodeTests : 8 tests (init, append, remove, allLeaves, normalize collapse / empty, find)
- BSPTilerTests : 10 tests (layout empty/single/two/three, insert, idempotence, sub-container, remove normalize, focusNeighbor edge)
- MasterStackTilerTests : 6 tests (single, master+stack, stack split, remove promotes, focus master↔stack)
- TypesTests : 6 tests (direction orientation/sign, opposite, subrole, isTileable)
- StageTests : 2 tests (codable round-trip, SavedRect)

**Resultat** : 32 PASS / 0 echec en 0.005 s.

### Phase 6 — Audit

Score global : **B+**. Voir `audits/2026-05-01/session-2026-05-01-spec-002-01/scoring.md`.

6 findings (1 HIGH, 2 MEDIUM, 2 LOW, 1 INFO) — tous documentes, aucun bloquant.

---

## Resultats build & tests

```
$ PATH="/usr/bin:..." swift build -c release
Build complete! (10.36s)

$ PATH="/usr/bin:..." swift test
Executed 32 tests, with 0 failures (0 unexpected) in 0.005 (0.008) seconds

$ ls -la .build/release/roadie* | head
roadie   1.4 MB  ⚠️
roadied  1.6 MB  ✅

$ otool -L .build/release/roadied
✅ Toutes libs systeme : /usr/lib/, /System/Library/, Network.framework
```

---

## Findings audit (resume)

| ID | Sev | Description | Statut |
|---|---|---|---|
| F1 | HIGH | CLI 1.4 MB > 500 KB cible (TOMLKit transitif) | A refactorer V2 |
| F2 | MED | Tests integration shell non ecrits | Documente, a faire 1er run user |
| F3 | MED | Daemon non demarre, runtime non valide | Normal, attente user |
| F4 | LOW | 6 warnings cosmetiques `as String` | Cleanup ulterieur |
| F5 | LOW | BSPTiler.move algo simplifie multi-niveau | OK V1 |
| F6 | INFO | Polish T066/T067/T068 partiels | Documente tasks.md |

---

## Phase 8 — Runtime Fixes (post-livraison, imprévue)

Au premier run live, 6 bugs ont été découverts en moins de 30 minutes. Tous corrigés dans la même session, ajoutant ~50 LOC.

| Tâche | Bug | Fix | LOC ajoutées |
|---|---|---|---|
| T074 | Daemon désalloué après bootstrap → CLI répond `no handler` | `enum AppState { @MainActor static var daemon }` | ~5 |
| T075 | Segfault `roadie windows list` (`String(format: "%s")` UB Swift) | Réécriture OutputFormatter avec `pad()` Swift natif | ~10 |
| T076 | Nouvelles fenêtres pas auto-tilées (race condition `kAXWindowCreatedNotification`) | Retry 100 ms + fallback dans `axDidChangeFocusedWindow` | ~10 |
| T077 | Stale entries après destruction (`kAXUIElementDestroyedNotification` rate) | `pruneDeadWindows()` avant chaque commande (auto-GC SPEC-001) | ~20 |
| T078 | Doublons d'enregistrement via auto-scan `axDidActivateApplication` | Désactivation de l'auto-scan, fallback focus suffit | -10 |
| T079 | Nouvelle fenêtre va en col 3 au lieu de splitter la focused | MRU stack `previousFocusedWindowID` + `insertionTarget(for:)` | ~15 |
| T080 | Linker error `make` (anaconda ld) | `export PATH := /usr/bin...` dans Makefile | ~3 |
| T081 | Constitution amendée principe G/G' Mode Minimalisme LOC | Texte dans constitution.md + constitution-002.md | n/a |

**Net delta LOC Phase 8** : 2 009 → 2 061 (+52 effectives).

---

## Phase 9 — Runtime Fixes itération 2 (post-livraison, second round)

13 corrections suite à une seconde session de tests interactifs poussés. Concentrées sur les apps Electron (Cursor) et la robustesse architecturale.

| Tâche | Type | Description | LOC |
|---|---|---|---|
| T082 | REFACTOR | TilerStrategy enum → struct + TilerRegistry dynamique (vraie architecture pluggable, ajout d'une stratégie sans modifier de fichier central) | +50 |
| T083 | BUGFIX | MRU stack inversée : `focusedWindowID` prioritaire sur `previousFocusedWindowID` (sinon split de la fenêtre obsolète) | ~3 |
| T084 | FEATURE | MouseRaiser : click-to-raise via NSEvent global monitor (différenciateur AeroSpace) | +50 |
| T085 | FEATURE | PeriodicScanner : timer 1 sec pour rattraper les apps Electron silencieuses (Cursor crée sa fenêtre sans aucune notif AX) | +30 |
| T086 | BUGFIX | Subscription `kAXMainWindowChangedNotification` ajoutée | ~5 |
| T087 | BUGFIX | Subscription destruction par-window (pas par-app) | +15 |
| T088 | BUGFIX | Dispatch destruction via AXUIElement + lookup CFEqual (l'élément peut être déjà détruit au moment du dispatch) | +20 |
| T089 | BUGFIX | didTerminateApp nettoie les fenêtres orphelines de l'app fermée | +15 |
| T090 | BUGFIX | Init focus au boot (refreshFromSystem en fin de bootstrap) — fix propre, pas de hack | +3 |
| T091 | INSTRUMENTATION | Logs INFO diagnostic à tous les points de décision | +10 |
| T092 | FEATURE | Commande CLI `roadie tiler list` (expose TilerRegistry.availableStrategies) | +10 |
| T093 | BUGFIX | Scan also via NSWorkspace activate path (pas uniquement AX path) | +5 |
| T094 | QUALITY | 7 tests unitaires TilerRegistry (auto-register, isolation, Codable round-trip) | +60 |

**Net delta LOC Phase 9** : 2 061 → 2 299 (+238 effectives, dont ~120 nets après refactor T082 et factorisation T093).

### Découvertes notables Phase 9

- **Cursor (Electron) reste 48 secondes silencieux côté AX** après lancement. Aucune notification ne fire. Le PeriodicScanner 1 sec est la seule réponse propre.
- **`kAXUIElementDestroyedNotification` doit être abonnée par-window**, pas par-app — comportement non documenté mais reproduit de l'observation AeroSpace.
- **Logique MRU subtile** : préférer `focused` sur `prev` est contre-intuitif mais correct. Le focus courant est l'intent immédiat ; le prev sert uniquement au cas focus race où la nouvelle fenêtre s'est déjà fait elle-même focused.
- **Architecture pluggable validée** : ajouter "papillon" tiler = créer un fichier + 1 ligne register() dans bootstrap. Aucun fichier central touché. Constitution principe I' respecté empiriquement.
- **`TilerStrategy` struct vs enum** : la perte de type-safety à la compilation (un `String` arbitraire est accepté) est compensée par la validation runtime via `TilerRegistry.make()` qui retourne `Optional` + erreur explicite.

### Découvertes notables du run live

- **TCC sur le bundle .app** (leçon SPEC-001) a fonctionné parfaitement, le code-sign ad-hoc accepte la première autorisation et la conserve à travers les rebuilds tant que le bundle ID reste stable.
- **`tiled_windows: 2`** affiché alors que 4 fenêtres étaient visibles → indicateur que le registry n'était pas synchro avec macOS. L'auto-GC corrige ça.
- **L'utilisateur s'attend à ce que la nouvelle fenêtre splitte la focalisée** (yabai-style), pas à ce qu'elle s'ajoute à droite. Confirmation que la MRU stack est essentielle pour respecter cette intuition.
- **iTerm peut avoir des fenêtres "fantômes"** que l'utilisateur ne voit pas mais qui existent côté AX. Le scan automatique d'app les remontait → doublons. Mieux vaut s'en tenir aux events explicites.

---

## REX — Retour d'Experience

**Date** : 2026-05-01
**Duree session** : ~2h cumulees (avec parallel researcher)
**Phases completees** : 6/6 SpecKit (specify, plan, tasks, analyze auto-skip, implement, audit)

### Ce qui a bien fonctionne

- **Researcher en parallele** : pendant que je preparais la branche + plan, l'agent lisait yabai/AeroSpace en arriere-plan. Gain de temps significatif. Sa synthese (820 lignes) a directement informe les decisions du plan.
- **Lessons SPEC-001 reutilisees** : codesign ad-hoc + bundle .app dans Makefile (TCC Sequoia/Tahoe), `_AXUIElementGetWindow` declare via `@_silgen_name`, structure projet eprouvee.
- **Architecture en couches stricte** : protocole Tiler avec 2 implementations qui se compilent sans toucher au Core, StagePlugin authentiquement opt-in (le daemon fonctionne sans elle si `config.stageManager.enabled == false`).
- **Build first, test first, polish later** : `swift build` reussi avec 2 erreurs corrigees (callback signature, MainActor isolation), tests unitaires 32 PASS du premier coup une fois le build clean. Bon ratio effort/resultat.
- **Constitution-002 anticipee** : ecrite avant l'implementation pour cadrer les ecarts avec SPEC-001 (multi-fichier, TOMLKit). Permet de ne pas justifier a posteriori.

### Difficultes rencontrees

- **Anaconda ld shadow** : connu via MEMORY.md mais m'a quand meme cause un faux negatif au premier `swift build`. Override `PATH=/usr/bin:/usr/local/bin:/bin` necessaire systematiquement.
- **AXObserverCallback vs AXObserverCallbackWithInfo** : 2 typedefs avec nombre d'args differents. AXObserverCreate veut le 4-args, AXObserverCreateWithInfoCallback veut le 5-args. Erreur typique premiere fois.
- **MainActor isolation au top-level** : Swift Concurrency strict refuse d'appeler une methode `@MainActor` depuis le top-level synchrone. Fix : wrapper dans `DispatchQueue.main.async { Task { @MainActor in ... } }` puis `RunLoop.main.run()`.
- **TOMLKit dans le CLI** : RoadieCore depend de TOMLKit, et RoadieCore est aussi linke par le CLI (qui a besoin de Request/Response/Logger). Le CLI herite donc de TOMLKit. **Refactor V2 necessaire** : extraire Config dans un module `RoadieConfig` independant que seul le daemon importe.

### Connaissances acquises

- AeroSpace est tres bien fait architecturalement, mais son point faible click-to-focus est resolvable avec un seul ajout (`kAXApplicationActivatedNotification`). C'est notre differenciateur explicite.
- yabai a 10 ans de patches anti-bug Apple — la dette de SIP est enorme. Notre approche AeroSpace-style en repart tabula rasa, paie en perdant les events SkyLight, mais c'est acceptable au scope V1.
- Le code Swift moderne (Concurrency, actors, MainActor isolation) impose une discipline sur les frontieres de threads. Une fois acquise, c'est plus simple que pthreads C.
- Un binaire daemon Swift Package Manager est tres rapide a builder (10s release universal). Pas de Xcode project necessaire.

### Recommandations pour les prochains passages

**Priorite 1 — premier run live** (essentiel pour valider) :
1. `make install-app` : produit le bundle.
2. Ajouter `~/Applications/roadied.app` dans Reglages > Accessibilite, cocher.
3. Lancer `roadied` en foreground (`./build/release/roadied` directement, pas via daemon).
4. Tester `roadie windows list` depuis un autre terminal.
5. Observer les fenetres et le tiling auto.

**Priorite 2 — refactor V2** :
1. Extraire `Config.swift` dans un nouveau target `RoadieConfig` que seul `roadied` importe.
2. Mesurer la nouvelle taille du CLI (cible < 500 KB).
3. Ecrire les tests d'integration shell T029/T041/T051/T054/T060.

**Priorite 3 — polish** :
1. Nettoyer les 6 warnings `as String` (cosmetique).
2. Implementer T066/T067/T068 (KnownBundleIds, snapshot order, subrole exclusion popups).
3. Etoffer BSPTiler.move pour le cas multi-niveau.

### A ne pas refaire

- **Ne pas oublier l'override PATH avant `swift build`** sur cette machine : ajouter dans le Makefile pour automatiser.
- **Ne pas mettre TOMLKit dans le module partage** : separer dependance tierce dans le module qui en a besoin uniquement.
- **Ne pas tenter de tester un daemon AX/TCC en mode autonome sans utilisateur** : impossible, accepter et documenter clairement.

---

## Prochaines etapes (utilisateur a son retour)

- [ ] Review du diff complet : `git diff main...002-tiler-stage`
- [ ] **`git commit`** — JAMAIS automatique. Tu choisis quand et avec quel message.
- [ ] Premier run live : `make install-app`, autoriser dans Accessibility, `roadied --daemon`
- [ ] Test du tiling auto avec 3 Terminal nouveaux
- [ ] Test click-to-focus sur VSCode/Cursor (le differenciateur)
- [ ] Validation des SC chiffres en runtime
- [ ] Refactor TOMLKit hors CLI si SC-004 important
- [ ] Bind hotkeys via Karabiner ou BTT
- [ ] Eventuellement merge `002-tiler-stage` vers main, fermer worktree

---

## Livrables

```
.worktrees/002-tiler-stage/
├── Package.swift                              # SPM 4 targets
├── Makefile                                   # build, install, app-bundle, install-app
├── .gitignore
├── CLAUDE.md                                  # auto
├── Sources/
│   ├── RoadieCore/         (11 fichiers, 764 LOC)
│   ├── RoadieTiler/         (5 fichiers, 455 LOC)
│   ├── RoadieStagePlugin/   (3 fichiers, 232 LOC)
│   ├── roadied/             (2 fichiers, 328 LOC)
│   └── roadie/              (3 fichiers, 230 LOC)
├── Tests/
│   ├── RoadieCoreTests/     (TypesTests)
│   ├── RoadieTilerTests/    (TreeNodeTests, BSPTilerTests, MasterStackTilerTests)
│   └── RoadieStagePluginTests/ (StageTests)
├── docs/decisions/
│   ├── ADR-001-ax-per-app-no-skylight.md
│   ├── ADR-002-tree-naire-vs-bsp-binary.md
│   └── ADR-003-hide-corner-vs-minimize.md
├── specs/002-tiler-stage/
│   ├── spec.md             (4 stories, 23 FR, 10 SC)
│   ├── plan.md             (architecture + technical context)
│   ├── research.md         (820 lignes, yabai+AeroSpace)
│   ├── data-model.md       (structures Swift)
│   ├── contracts/cli-protocol.md
│   ├── contracts/tiler-protocol.md
│   ├── quickstart.md       (install + premiers raccourcis)
│   ├── tasks.md            (73 taches)
│   ├── checklists/requirements.md (13/13 PASS)
│   └── implementation.md   (ce fichier)
├── audits/2026-05-01/session-2026-05-01-spec-002-01/
│   ├── scoring.md
│   ├── grade.json          (grade B+)
│   ├── cycle-1/aggregated-findings.json (6 findings)
│   └── cycle-scoring/aggregated-findings.json (0 — tout traite)
└── .specify/memory/constitution-002.md
```

Total : ~50 fichiers crees, 2009 LOC Swift productif + 321 LOC tests + ~5000 mots de documentation SpecKit.
