# Audit de Code - roadie, SPEC-016 (stabilisation)

**Date** : 2026-10-10
**Mode** : fix (1 cycle + cycle de scoring en lecture seule) | grid : pre-merge | scope_mode : diff (3560183..HEAD, 91 fichiers)
**Durée** : environ 37 min
**Score global** : A- (87,3/100, moyenne pondérée des domaines applicables)
**Coverage** : 100 % du périmètre diff (mode LIGHT, pas d'échantillonnage)
**Release bloquée** : non (0 CRITICAL, 0 HIGH)
**Corrections** : 7 appliquées dans l'arbre de travail, **non commitées** (consigne de l'orchestrateur appelant)

## Tendance (vs session précédente du même scope)

Première session pour ce scope (SPEC-016). Repère : la dernière session du dépôt (`audits/2026-05-25/session-2026-05-25-015-navrail-fullscreen-state-01`, SPEC-015) était notée A sur un périmètre bien plus petit.

| Domaine | Cycle-1 (avant corrections) | Cycle-scoring (après) | Delta findings |
|---------|-----------------------------|-----------------------|----------------|
| Global  | A- (86,1)                   | A- (87,3)             | -7 corrigés, +1 résiduel (REL-012, issu de la contre-revue) |
| Fiabilité | A- (86) | B+ (84) | REL-012 ajouté ; troncature recalculée (2 LOW réintégrés) |
| Tests | A- (87) | A (92) | TEST-001 et TEST-002 du cycle-1 corrigés |
| Complexité | A- (85) | A (91) | config du rail relue à chaque tick et O(n²) de `windowSnapshots` corrigés |
| Qualité | C (64) | C (63) | marqueur illisible corrigé ; 4 LOW réintégrés après troncature |
| Minimalisme | A (91) | A (94) | clés d'en-tête sans effet signalées, champs morts retirés |

## Résumé exécutif

| Domaine        | Note | CRIT | HIGH | MED | LOW |
|----------------|------|------|------|-----|-----|
| Fiabilité      | B+   | 0    | 0    | 2   | 10  |
| Observabilité  | A    | 0    | 0    | 2   | 1   |
| Tests          | A    | 0    | 0    | 1   | 5   |
| Complexité     | A    | 0    | 0    | 1   | 6   |
| Qualité        | C    | 0    | 0    | 10  | 7   |
| Architecture   | A    | 0    | 0    | 0   | 1   |
| Hygiène IA     | A    | 0    | 0    | 0   | 0   |
| Duplication    | A    | 0    | 0    | 2   | 0   |
| Minimalisme    | A    | 0    | 0    | 2   | 0   |
| Sécurité, supply chain, performance, UX | N/A | - | - | - | - |

Les modules 03 (sécurité) et 08 (performance) ne font pas partie de la grille pre-merge. Le socket local (`~/.roadies/roadied.sock`, 0600, umask 0177 au bind) est décrit dans le threat model de `01_Decouverte.md`, sans audit OWASP dédié.

**Aucun finding critique.** Les 5 points à traiter en premier (MEDIUM) :
1. OBS-001 - un fichier d'état illisible (écritures refusées, FR-015) n'apparaît ni dans `doctor` ni dans `daemon-status.json` (`Sources/RoadieDaemon/StageStore.swift:170`).
2. REL-002 - `mutate` sur un état illisible exécute la commande, n'écrit rien et répond « succès » (`Sources/RoadieDaemon/JSONPersistence.swift:85`).
3. OBS-002 - si le socket ne s'ouvre pas, le message client renvoie vers `roadie doctor`, qui ne teste pas le socket (`Sources/RoadieDaemon/CommandSocketServer.swift:224`).
4. REL-001 - une requête socket dont le client est parti (délai de 5 s dépassé) est quand même exécutée plus tard (`Sources/RoadieDaemon/CommandSocketServer.swift:134`).
5. QUAL-002 / QUAL-007 - `scripts/doctor` annonce « stale pidfile » pour le service installé dans `~/.local/bin`, et `scripts/install` démarre le daemon puis le relance aussitôt (`bootstrap` puis `kickstart -k`).

**Dette technique** : modérée, concentrée dans 3 fonctions longues (`LayoutMaintainer.tick` 352 lignes, `StageCommands.switchDisplay` 315 lignes copiée 3 fois, `CLICommandRouter.dispatch` 378 lignes).
**Hotspots** (taille x churn du diff) :
1. `Sources/RoadieDaemon/LayoutMaintainer.swift` (3 103 lignes, +913/-551 dans le diff)
2. `Sources/RoadieDaemon/CLICommandRouter.swift` (1 784 lignes, nouveau)
3. `Sources/RoadieDaemon/StageCommands.swift` (1 507 lignes, +328/-291)

## Findings par sévérité (cycle-scoring)

### CRITICAL (0) / HIGH (0)
Aucun. Phase 2bis : aucun contre-audit obligatoire. Contre-audit volontaire de 1 finding : AI-003 (cycle-1) **réfuté** (`TestEnvironment.swift:7` utilise toujours `processName.contains("test")`), supprimé.

### MEDIUM (20)
- OBS-001, OBS-002 - modes dégradés invisibles (état illisible, socket absent).
- REL-001, REL-002 - requête socket périmée exécutée ; `mutate` refusé affiché comme succès.
- QUAL-001 - code de sortie déduit de mots du message (`CLICommandRouter.swift:254`).
- QUAL-002, QUAL-006, QUAL-007 - scripts et cycle de vie des logs (`scripts/doctor:26`, `FileAdministration.swift:143`, `scripts/install:108`).
- QUAL-003, QUAL-004, QUAL-008, QUAL-009 - fonctions très longues (`switchDisplay`, `tick`, `dispatch`, `unhideAll`).
- QUAL-005, QUAL-010 - tolérances littérales hors `LayoutTolerance` (FR-041) dans `WindowCommands.swift:1163` et `SystemSnapshotProvider.swift:801`.
- PERF-001 - bascule de stage : un `setFrame` (énumération AX de l'application) par fenêtre (`StageCommands.swift:1022`).
- TEST-001 - le test T211 vérifie son propre double, pas la fabrique de production (`CLICommandRouterTests.swift:146`).
- DUP-001, DUP-002, MIN-002 - petits helpers recopiés (`isClose` x8, centrage borné x4, `isCustomStageName` x4).
- MIN-001 - `ParkingSessionState`/`ParkingSessionStatus` sans usage (préexistant au diff).

### LOW (30)
Voir `cycle-scoring/aggregated-findings.json` (dont REL-012, résiduel de la contre-revue des corrections). 24 LOW supplémentaires sont tronqués (règle d'or 19, liste dans `execution_metrics.warnings`).

## Détail des findings

Détail complet (extrait, remédiation, vérification, empreinte) : `cycle-scoring/aggregated-findings.json`. État avant corrections et statuts `fixed` : `cycle-1/aggregated-findings.json`. Journal : `cycles.log`, `fix-report.md`.

## Corrections appliquées (cycle-1, non commitées)

| Finding cycle-1 | Correction | Fichiers | Preuve |
|---|---|---|---|
| PERF-001 | `RailSettings.load(path:)` relu seulement si le fichier change ; lecture échouée jamais mise en cache (FR-023) | `Sources/RoadieDaemon/RailSettings.swift` | test `railSettingsFileIsReparsedOnlyWhenItChanges`, rouge sans correction |
| PERF-003 | `windowSnapshots` en un passage ; `state(for:in:)` sans appelant retiré | `Sources/RoadieDaemon/AutomationSnapshotService.swift`, `WindowPresentationStateResolver.swift` | 19 tests AutomationSnapshot/résolveur |
| QUAL-008 | marqueur de reprise illisible copié en `.corrupt-<date>` et traité comme arrêt non propre (FR-015, FR-037) | `Sources/RoadieDaemon/RestoreSafetyService.swift` | test `startRunRecoversWhenRunMarkerIsUnreadable`, rouge sans correction |
| MIN-002 | `fx.rail.header.height/width` signalées « sans effet » ; champs morts retirés (FR-034) | `Sources/RoadieCore/Config.swift`, `Sources/RoadieDaemon/RailSettings.swift` | test `validationFlagsKeysThatHaveNoEffect` étendu |
| AI-001 | `window close` non implémenté sort en 1 | `Sources/RoadieDaemon/CLICommandRouter.swift` | test `unimplementedCommandsExitOne` |
| TEST-001 | règle d'ambiguïté du rattachement testée (FR-006) | `Tests/RoadieDaemonTests/PersistentStageStateTests.swift` | mutation de la règle -> rouge |
| TEST-002 | expiration des refus de taille testée (FR-004) | `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift` | mutation de l'expiration -> rouge |

Batterie : `./scripts/with-xcode swift build` OK ; `./scripts/test` **626 tests / 69 suites verts** (620 avant). Contre-revue indépendante des corrections : 7/7 confirmées, 2 réserves corrigées, 1 retenue (REL-012), 1 réfutée.

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|----|-------------|--------|--------|---------|
| MIN-001 | Supprimer `ParkingSessionState`/`ParkingSessionStatus` (aucun usage) | XS | MEDIUM | `Sources/RoadieDaemon/StageStore.swift:113` |
| QUAL-002 | `scripts/doctor` : reconnaître le binaire installé (`~/.local/bin/roadied`) | S | MEDIUM | `scripts/doctor:26` |
| QUAL-007 | `install` : rotation avant `bootstrap`, pas de `kickstart -k` après un bootstrap réussi | S | MEDIUM | `scripts/install:108` |
| TEST-001 | Tester `CLICommandRouter.defaultService(readOnly:)` réel | S | MEDIUM | `Tests/RoadieDaemonTests/CLICommandRouterTests.swift:146` |
| OBS-001 | Contrôle « state-file » dans `DaemonHealthService.run()` fondé sur `loadFailure` | S | MEDIUM | `Sources/RoadieDaemon/StageStore.swift:170` |

## Dépendances vulnérables

Non évalué (module 03 hors grille). Une seule dépendance tierce : TOMLKit.

## Complexité algorithmique (Article XVIII)

Périmètre vérifié par le module 04 sur tous les fichiers Sources du diff. Aucun anti-pattern HIGH ou CRITICAL. Le O(n²) de `AutomationSnapshotService.windowSnapshots` et la relecture de `roadies.toml` à chaque calcul de marges ont été corrigés. Restent 7 constats (1 MEDIUM : `setFrame` unitaire à la bascule de stage ; 6 LOW à n borné, inférieur à 100 fenêtres, dont une annotation O() inexacte dans `DaemonSnapshot.swift:307`).

## Minimalisme & Frugalité (axe OBLIGATOIRE - Article XIX constitution)

Checklists du module 12 exécutées sur tout le diff. T220-T224 sont bien appliqués : un seul `ProcessLiveness.isAlive`, un seul `TestEnvironment.isRunningTests`, une seule conversion `NSColor(hex:)`, les 39 constantes de `LayoutTolerance` ont toutes un lecteur. Résidus : code mort préexistant (`ParkingSession*`, MIN-001), petits helpers recopiés (MIN-002, DUP-001, DUP-002), wrappers `beginLayoutCommand`/`finishLayoutCommand` (tronqué), parseurs d'arguments dupliqués dans `CLICommandRouter` (tronqué), `DesktopsConfig` décodée sans lecteur (tronqué). Corrigé pendant ce cycle : champs morts `LegacyHeader.height/width` et méthode `state(for:in:)` sans appelant (environ 15 lignes retirées).

Potentiel minimalisme : ~235 lignes suppressibles à comportement constant (estimation du module 12, ~250 lignes, moins ~15 lignes retirées pendant ce cycle ; environ 2,4 % des 9 649 lignes ajoutées dans Sources).

## Vertus LLM & Responsabilité Future (axe OBLIGATOIRE - Article XX constitution)

- **Charge cognitive future** : en baisse nette. Les fichiers de plus de 3 000 lignes sont découpés (`RailController` 3 267 -> 1 305 lignes + 5 fichiers), les seuils sont centralisés, les verrous sont documentés avec leur raison. La hausse résiduelle vient de `LayoutMaintainer.swift` (plus de 3 000 lignes, `tick` à 352 lignes) et de la table `knownKeys` de `Config.swift`, recopiée à la main.
- **Volume justifié** : oui. Environ 3 400 lignes nettes de production et 3 070 lignes de tests pour 43 exigences ; le résidu injustifié est estimé à ~235 lignes.
- **Abstractions** : utiles. `ProcessLiveness` (10 sites), `TestEnvironment` (7), `LayoutTolerance` (~110 lecteurs), `CLICommandSpec` (aide unique). Réserves : wrappers passthrough `beginLayoutCommand`/`finishLayoutCommand`, `CommandSocketResponse` qui recopie `CLIResponse`.
- **Code assumable** : oui pour les zones nouvelles (intentions commentées, complexité annotée, sections « Non vérifié » tenues). À relire : `CLICommandRouter` (code déplacé non nettoyé) et le code de sortie déduit du texte (QUAL-001).
- **Patterns LLM détectés** : code mort laissé (`StageStore.swift:113`), options sans effet déclarées valides (`Config.swift:1204`, corrigé pour `fx.rail.header` ; `Config.swift:241` `DesktopsConfig`), petites copies non factorisées (`StageCommands.swift:1392`), test décoratif (`FileLockTests.swift:34` `#expect(true)`). Pas de couches empilées sans règle, pas de régénération opaque, pas de tests qui ne vérifient que des mocks.
- **Corrections de cet audit** : ciblées (226 lignes ajoutées, 30 retirées sur 12 fichiers, dont 155 lignes de tests), chacune prouvée par un test rouge sans la correction ou par une mutation, et relue par un agent indépendant.

## Findings supprimés par la baseline

Aucun : `audits/baseline.json` absent (baseline vide).

## Points positifs

- `Sources/RoadieDaemon/JSONPersistence.swift` : transaction `mutate` sous verrou exclusif, fichier illisible conservé en `.corrupt-<date>`, signalement après libération du verrou, pas de réécriture si octets identiques.
- `Sources/roadied/main.swift` : SIGTERM/SIGINT/SIGHUP traités par `DispatchSource` sur la file principale (pas de travail dans un handler de signal), verrou d'instance libéré en dernier.
- `Sources/RoadieAX/SystemSnapshotProvider.swift` : énumération AX une fois par application, index par CGWindowID, `setFrames` groupé par pid, complexités annotées.
- `Sources/RoadieDaemon/CommandSocketServer.swift` : E/S bornées par `poll`, taille de requête limitée, socket créé en 0600, refus de repli local si le daemon tient le verrou mais ne répond pas.
- Tests : horloges injectées pour toutes les expirations, aucun `sleep` ni `setenv`, chemins par défaut redirigés en test ; duplication globale faible (0,78 % sur les Sources du diff).

## Roadmap de remédiation

1. **Immédiat (< 1 sem)** : aucun bloquant.
2. **Court terme (< 1 mois)** : lot « mode dégradé visible » OBS-001, OBS-002, REL-002, REL-001 ; scripts QUAL-002, QUAL-006, QUAL-007 ; test TEST-001.
3. **Moyen terme (< 3 mois)** : QUAL-001 (issue typée des commandes), FR-041 résiduel QUAL-005/QUAL-010, PERF-001 (bascule de stage groupée par pid), DUP-001, DUP-002, MIN-002.
4. **Long terme** : découpage de `tick` (QUAL-004), `switchDisplay` (QUAL-003), `dispatch` (QUAL-008), `unhideAll` (QUAL-009) ; MIN-001.

## Non vérifié (mémoire négative)

- Comportement sur le bureau réel (AX, socket réel, ScreenCaptureKit, veille), exécution réelle des scripts `install`/`uninstall`/`doctor` : non lancés (consigne).
- Module 03 (sécurité) et 08 (performance) : hors grille.
- `LayoutMaintainer.swift` et `DaemonSnapshot.swift` : lus par fonctions ciblées et recensement de symboles, pas en intégralité ligne à ligne.
