# Découverte - audit SPEC-016 (roadie)

## Périmètre
- Mode diff : `git diff --name-only 3560183..HEAD -- Sources Tests scripts Makefile` = 91 fichiers (62 sources Swift, 20 fichiers de tests, 9 scripts/Makefile). Liste : `diff_files.txt`.
- Dépôt : 153 fichiers Swift (Sources 34 023 lignes, Tests 19 613 lignes) -> mode LIGHT (S), pas d'échantillonnage, couverture visée 100 % du diff.
- Stack : Swift 6 (swift-tools 6.0), macOS 14+, AppKit, AX, CoreGraphics, ScreenCaptureKit, TOMLKit ; tests swift-testing (`./scripts/test`, HOME temporaire).
- Baseline : build OK, 620 tests / 69 suites verts sur HEAD 17c6a0a.

## Hot paths
1. `LayoutMaintainer.tick()` (Sources/RoadieDaemon/LayoutMaintainer.swift:103) - chaque tick du tiler.
2. `SnapshotService.snapshot()` / `sharedSnapshot()` (Sources/RoadieDaemon/DaemonSnapshot.swift:165-193) - chaque tick, commande, lecteur.
3. Énumération AX (Sources/RoadieAX/SystemSnapshotProvider.swift) - appels bloquants bornés à 0,5 s, registre de mise de côté.
4. `JSONPersistence.mutate` (Sources/RoadieDaemon/JSONPersistence.swift) - transaction sous flock entre processus.
5. Socket Unix (Sources/RoadieDaemon/CommandSocketServer.swift:62) -> `CLICommandRouter`.
6. Navrail (Sources/RoadieDaemon/RailController.swift:64) - timers de rebuild/fondu.
7. Cycle de vie (Sources/roadied/main.swift) - verrou d'instance, signaux, restauration.

## Threat Model
### Assets
- Visibilité/position des fenêtres (risque principal : fenêtre perdue hors écran).
- Fichiers d'état `~/.roadies/*.json`.
- Permissions TCC (Accessibility, Screen Recording) du binaire.
- Contenu capturé des fenêtres (vignettes).
### Attaquants probables
- Externe anonyme : bas (aucun port réseau).
- Local même utilisateur : moyen (socket 0600 et fichiers d'état sous son contrôle ; peut déjà piloter AX lui-même).
- Local autre utilisateur : bas (umask 0177 au bind).
- Supply chain : bas (TOMLKit seule dépendance).
### Surface d'attaque
- 1 socket Unix local, 1 fichier de config TOML rechargé à chaud, fichiers JSON multi-processus, scripts shell (launchctl, codesign).
### Hot paths sensibles
1. socket -> router -> AX : Tier moyen.
2. restauration à l'arrêt : Tier élevé (fiabilité).
3. transactions multi-processus : Tier élevé (fiabilité).

## SLOs
Définis par la spec : SC-003 (commande < 1 s avec une application gelée), SC-004 (0 écriture d'état au repos sur 60 s), SC-005 (0 snapshot au survol du rail).

## Contexte de revue antérieure
Relecture croisée T111, deux contre-revues Codex (plan et implémentation), trois passages Converge (dernier : CONVERGED). Les constats corrigés (T201-T227, T301-T302) ne sont pas réinventés ; ils sont vérifiés s'ils réapparaissent.
