# Journal d'Implémentation - Stabilisation de Roadie

## Métadonnées

- **Spec** : 016-roadie-stabilization
- **Branche** : `016-roadie-stabilization`
- **Démarré** : 2026-10-10
- **Terminé** : En cours (Converge, contre-revue d'implémentation et audit restants)
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

## Tests exécutés

- `./scripts/with-xcode swift build` : OK.
- `./scripts/test` : **590 tests, 67 suites, tous passent** (contre 518 avant la spec).
- `grep -rn "/Users/" Sources scripts` : vide. `CGWindowListCreateImage` et `activateIgnoringOtherApps` : absents de `Sources`.
- **Test manuel** : non fait (bureau réel requis) — voir `quickstart.md`.

## Non vérifié

- Comportement sur le bureau réel : AX avec application gelée, socket CLI réel, restauration à l'arrêt et après crash, ScreenCaptureKit, moniteur de saisie (Cmd-Tab), veille/réveil.
- Exécution réelle de `install`, `uninstall`, `start-modular`, `package-dmg`.
- Gain de performance mesuré (aucune mesure avant/après).

## Limites connues

- Les commits par lot ne compilent pas tous isolément (dépendances croisées entre lots parallèles) ; `HEAD` compile et passe la suite complète.
- Rotation des logs launchd seulement au démarrage.
- L'application du DMG n'a toujours pas de moyen de quitter (hors périmètre).
