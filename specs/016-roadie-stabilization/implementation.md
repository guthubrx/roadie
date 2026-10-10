# Journal d'Implémentation - Stabilisation de Roadie

## Métadonnées

- **Spec** : 016-roadie-stabilization
- **Branche** : `016-roadie-stabilization`
- **Démarré** : 2026-10-10
- **Terminé** : 2026-10-10 (toutes les tâches cochées ; validation manuelle sur bureau réel en attente)
- **Mode** : 10 agents en parallèle, propriété exclusive de fichiers par lot (voir plan.md) ; commits par lot après build et suite complète verts.
- **Volume** : 72 fichiers sous `Sources/` et `Tests/`, +10 724 / -5 818 lignes (dont le déplacement de ~1 650 lignes de `Sources/roadie/main.swift` vers `CLICommandRouter.swift` et le découpage de `RailController.swift`).

## Modèles utilisés

| Lot | Modèle | Raison |
|---|---|---|
| A, B, C, D, E, F, H, vague 2, Converge | Opus 5.5 | concurrence, AX, moteur de disposition, cycle de vie, IPC |
| G, I, relecture T111 | Sonnet 5.5 | développement courant, scripts, docs, relecture |
| J | Haiku 5.5 | nettoyage de tests simples |
| Contre-revues | Codex GPT-6.1-Sol | fournisseur différent |

## Progression par lot

### Setup (T001-T002)
- **Statut** : ✅ — **Commit** : `596c519`
- `LayoutTolerance` créé ; interfaces `StageStore.mutate` / `LayoutIntentStore.mutate`.

### Lot A - Persistance (T010-T018)
- **Statut** : ✅ — **Commit** : `b39dca4`
- `JSONPersistence.mutate` (verrou unique, écriture « verrou tenu » séparée, pas d'écriture si octets identiques) ; fichier illisible conservé (`.corrupt-<date>`) et jamais écrasé ; `PersistentStageMember.pid` et réconciliation d'identité refusée pour un pid vivant ; grâce 45 s des épinglages ; dates de présence non réécrites au repos ; `LayoutIntent.zoomedWindowID` et grâce 10 min des displays absents ; `EventLog` en `O_APPEND` avec rotation sous flock ; `LayoutCommandActivity` sans `@unchecked Sendable`.
- **Tests** : `StatePersistenceTests` (14 tests, dont 100 mutations concurrentes).

### Lot B - Accessibility (T020-T027)
- **Statut** : ✅ — **Commit** : `b1c8ceb`
- Délai AX 0,5 s (système + applications) ; registre `AXUnresponsiveApps` (5 s) consulté par tous les chemins ; cache limité aux attributs stables ; `apply` regroupé par pid (O(n²) supprimé, `Thread.sleep` retirés) ; activation sans option dépréciée ; observer AX avec réessai et destruction par fenêtre ; preflight Screen Recording.
- **Tests** : nouvelle cible `RoadieAXTests` (10 tests). Pire cas théorique : ~0,5 s par application gelée et par fenêtre de 5 s.

### Lot C - Moteur de disposition (T030-T039)
- **Statut** : ✅ — **Commit** : `9132743`
- Plein écran = AX natif ou `zoomedWindowID` (taille seule supprimée) ; gardes par scope (plus de `return` global) ; focus caché rendu visible ; faisabilité par surfaces minimales puis disposition aux tailles minimales, masquage en dernier recours ; refus expirant après 30 s ; pas d'application de plan bouton de souris enfoncé ; bloc d'application unique.
- **Tests** : 6 nouveaux tests ; 9 tests existants adaptés (ils validaient le comportement défectueux).

### Lot D - Commandes et tiler (T040-T046)
- **Statut** : ✅ — **Commit** : `18d7957`
- `toggleFullscreen` pose `zoomedWindowID` ; changement de stage sans détection par taille ; stage vide atteignable ; BSP : focus étranger traité comme nil, doublons évités ; tolérance de gap dérivée de `gapsInner`. T045 (transactions dans les commandes, faisabilité unique) fait en vague 2.

### Lot E - Snapshot et composants (T050-T059)
- **Statut** : ✅ — **Commit** : `bb619d1`
- `ConfigReloadService.shared.currentConfig()` (rechargement à chaud, dernière config valide) ; réconciliation sous `mutate` avec énumération AX hors verrou ; `sharedSnapshot()` (150 ms, invalidation) ; suivi du focus seulement après saisie utilisateur (< 1 s) ; hystérésis du classement ; focus-souris sur mouvement réel ; bordure sans redessin inutile ; display actif déterministe.

### Lot F - Cycle de vie (T060-T068)
- **Statut** : ✅ — **Commit** : `0ba7748`
- Verrou d'instance `flock` ; registre d'arrêt unique (TERM/INT/HUP) qui restaure les fenêtres masquées puis marque l'arrêt propre ; récupération d'un arrêt incomplet au démarrage ; restauration depuis l'union snapshot + membres ; `restore-watch` en session propre ; veille/réveil ; `daemon-status.json` ; `roadied --help`/`--version`.

### Lot G - Navrail (T070-T080)
- **Statut** : ✅ — **Commit** : `1152b7f`
- Watchers sans double fermeture ; `maximized` exclu pour une fenêtre seule ; rétention 15 s ; réglage `hide_on_maximized` ; survol sans snapshot, rebuild sur signature, vignettes réduites via ScreenCaptureKit ; snapshot figé pendant le drag ; interactions corrigées ; event taps réactivés ; `RailController.swift` 3 267 → ~1 290 lignes (5 fichiers extraits).

### Lot H - CLI (T090-T095)
- **Statut** : ✅ — **Commit** : `d814cb4`
- `CLICommandRouter` + `CommandSocketServer` (liste explicite de commandes finies, E/S hors fil principal, repli local seulement si le verrou d'instance est libre) ; `daemon restart` via `launchctl kickstart` ; aide générée, codes de retour cohérents, `--version` ; `doctor` lit `daemon-status.json`.

### Lot I - Config et exploitation (T100-T106)
- **Statut** : ✅ — **Commit** : `6b6b1fa`
- Validation avec suggestions et erreurs lisibles ; décodage tolérant des tables partielles (défaut découvert : `[fx.rail]` sans `[fx.borders]` était rejeté) ; `with-xcode` sans Xcode.app ; `install` hors du dépôt, signature optionnelle stable ; `make restart`/`dev-start`/`uninstall` ; exemples ; docs EN/FR ; ADR 007 et 008.

### Vague 2 - Intégration
- **Statut** : ✅ — commits répartis dans `18d7957`, `bb619d1`, `0ba7748`, `1152b7f`
- Transactions dans `StageCommands`/`WindowCommands` ; lecteurs du rail sur `sharedSnapshot()` ; config à chaud partout ; duplication `RuleMatch.description` supprimée ; socket branché dans `run` et `tiler` ; `zoomParent` pose `zoomedWindowID`.

### Lot J - Tests (T110)
- **Statut** : ✅ — commits `0ba7748` (tests décoratifs supprimés), `d31ae57` (test `setenv` remplacé par une fonction pure)

### T111 - Relecture croisée (Sonnet)
- **Statut** : ✅ (rapport ci-dessous ; corrections réparties en T202, T213-T219 puis T220-T227)
- **Axe transactions** : 53 blocs `mutate` extraits automatiquement ; aucun n'appelle `save`/`mutate`/`snapshot()`/AX ni n'émet d'événement (pas de blocage par verrou non réentrant).
- **Hautes** : 7 écritures hors transaction (→ T202) ; E/S sous le verrou des stages (→ T213).
- **Moyennes** : AX sous verrou de reprise (→ T214) ; `restore.json` illisible écrasé (→ T214) ; `try?` sur écritures d'état (→ T215) ; littéraux de tolérance (→ T205, T216) ; sonde flock contradictoire (→ T217) ; verrou de config pendant les E/S (→ T213) ; `@unchecked Sendable` (→ T218) ; vivacité de pid ×6 (→ T219, T220) ; détection « en test » dupliquée (→ T222).
- **Minimalisme (Article XIX)** : potentiel estimé à ~200 lignes suppressibles à comportement constant, dont ~110 de code mort antérieur (→ T221-T224, T227).
- **Vertus LLM (Article XX)** : charge cognitive globalement en baisse (tolérances centralisées, transactions uniformes, CLI testable) ; points de hausse traités en passage 1 et 2.

### Incident de commit
- `4dd023a` (docs) a été créé avec `git commit -a` et a embarqué une partie des changements AX en cours du lot K4 ; complété par `5226feb`. Aucune perte ; message de `4dd023a` incomplet. Depuis, chaque commit nomme ses fichiers.

### Audit v14 pre-merge (mode fix, 1 cycle + scoring)
- **Statut** : ✅ corrections appliquées, **non commitées** (l'orchestrateur appelant commite) ; rapport : `audits/2026-10-10/session-2026-10-10-016-roadie-stabilization-01/` (`fix-report.md`, `scoring.md`).
- **Constats** : 0 CRITICAL, 0 HIGH ; 7 MEDIUM/LOW corrigés : PERF-001 (FR-023 : `RailSettings.load(path:)` relu seulement si le fichier change), PERF-003 (O(n²) de `AutomationSnapshotService.windowSnapshots`), QUAL-008 (FR-015/FR-037 : marqueur de reprise illisible copié et traité comme arrêt non propre), MIN-002 (FR-034 : `fx.rail.header.height/width` signalées sans effet), AI-001 (`window close` non implémenté sort en 1), TEST-001 (règle d'ambiguïté du rattachement), TEST-002 (expiration des refus de taille).
- **Fichiers** : `Sources/RoadieDaemon/RailSettings.swift`, `AutomationSnapshotService.swift`, `WindowPresentationStateResolver.swift`, `RestoreSafetyService.swift`, `CLICommandRouter.swift`, `Sources/RoadieCore/Config.swift` ; tests `ConfigTests`, `RestoreSafetyServiceTests`, `CLICommandRouterTests`, `PersistentStageStateTests`, `LayoutMaintainerTests`.
- **Tests** : build OK ; `./scripts/test` 626 tests / 69 suites verts ; contrôles rouges ou mutations confirmant chaque nouveau test.

## Tests exécutés

- `./scripts/with-xcode swift build` : OK.
- `./scripts/test` : **626 tests, 69 suites, tous passent** (518 avant la spec ; 590 après la vague 1, 616 après la convergence 1, 620 après la convergence 3, 626 après l'audit).
- `grep -rn "/Users/" Sources scripts` : vide. `CGWindowListCreateImage` et `activateIgnoringOtherApps` : absents de `Sources`.
- **Test manuel** : non fait (bureau réel requis) — voir `quickstart.md`.

## Convergence et audit

| Étape | Issue |
|---|---|
| Converge passage 1 | 6 manques (T201-T206) + 7 défauts contre-revue Codex (T207-T212) + relecture T111 (T213-T219) → corrigés |
| Converge passage 2 | 2 manques (T301-T302) ; nettoyage T220-T227 (-387 / +194 lignes) |
| Converge passage 3 | **CONVERGED** |
| Audit v14 (fix, grille pre-merge) | **A- (87,3/100)**, 0 critique / 0 élevé, 20 moyens, 30 faibles ; 7 corrections (`d3c0903`) ; validateur : 0 erreur |

Session d'audit : `audits/2026-10-10/session-2026-10-10-016-roadie-stabilization-01/`.

## Suites recommandées (hors périmètre de cette spec)

- Modes dégradés peu visibles : état illisible absent de `doctor` (OBS-001), échec d'ouverture du socket (OBS-002), commande « succès » sans état enregistré (REL-002), commande exécutée après départ du client (REL-001).
- Scripts : `scripts/doctor` (binaire installé), `scripts/install` (double démarrage), `cleanup --apply` sur un log ouvert.
- Découpage de `tick` (352 lignes), `switchDisplay` (315), `dispatch` (378).

## Non vérifié

- Comportement sur le bureau réel : AX avec application gelée, socket CLI réel, restauration à l'arrêt et après crash, ScreenCaptureKit, moniteur de saisie (Cmd-Tab), veille/réveil.
- Exécution réelle de `install`, `uninstall`, `start-modular`, `package-dmg`.
- Gain de performance mesuré (aucune mesure avant/après).

## Limites connues

- Les commits par lot ne compilent pas tous isolément (dépendances croisées entre lots parallèles) ; `HEAD` compile et passe la suite complète.
- Rotation des logs launchd seulement au démarrage.
- L'application du DMG n'a toujours pas de moyen de quitter (hors périmètre).
