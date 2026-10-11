# Découverte - audit SPEC-017 (roadie, tiling réactif)

## Périmètre
- Mode diff : `git diff --name-only 27cb244..HEAD -- Sources Tests scripts` = 61 fichiers (36 sources Swift dont `MutableBSPLayoutStrategy.swift` supprimé, 22 fichiers de tests, 3 fichiers scripts/outil de mesure). Liste : `diff_files.txt`. Volume : +10 207 / -4 410 lignes.
- Dépôt : 162 fichiers Swift (Sources 36 065 lignes, Tests 23 380 lignes) -> mode LIGHT (S), pas d'échantillonnage, couverture visée 100 % du diff.
- Stack : Swift 6, macOS 14+, AppKit, AX, CoreGraphics, lecture privée SkyLight (ADR 010), TOMLKit ; tests swift-testing (`./scripts/test`) et unittest Python (`scripts/tests`).

## Hot paths
1. `LayoutMaintainer.tick(cause:)` (Sources/RoadieDaemon/LayoutMaintainer.swift:170) - passe unique.
2. `TickScheduler.fire()` (Sources/RoadieDaemon/TickScheduler.swift:139) et `LayoutMaintainer.nextDeadline(now:)` (:420) - échéances.
3. `SnapshotService.applyTreeScope` (Sources/RoadieDaemon/DaemonSnapshot.swift:1081) - chaque commande sur l'arbre.
4. Point commun d'écriture AX et budget (Sources/RoadieAX/SystemSnapshotProvider.swift:921, WrittenFrameRegistry.swift).
5. Observateur AX (Sources/RoadieAX/AXWindowEventObserver.swift) - échos absorbés.
6. Cache d'état (Sources/RoadieDaemon/JSONPersistence.swift).
7. Câblage (Sources/roadied/main.swift).

## Threat Model
### Assets
- Positions et visibilité des fenêtres ; fichiers d'état `~/.roadies` (et sauvegarde `stages.json.pre-017`) ; permission TCC Accessibility.
### Attaquants probables
- Externe anonyme : bas (aucun port réseau). Local même utilisateur : moyen (socket 0600). Supply chain : bas.
### Surface d'attaque
- 1 socket Unix local, config TOML rechargée à chaud, fichiers JSON multi-processus, lecture d'une API privée (`CGSCopyManagedDisplaySpaces`) avec repli public.
### Hot paths sensibles
1. boucle d'échéances -> passes répétées (fiabilité, CPU).
2. budget d'écriture -> fenêtre laissée à une mauvaise taille (fiabilité).
3. migration `mutableBsp` -> perte de stages (fiabilité, une fois au démarrage).

## SLOs
Définis par la spec : SC-001 (< 150 ms p90, 1 passe dans 95 % des épisodes), SC-002 (< 300 ms après la fin de l'animation de plein écran), SC-003 (0 placement au repos 60 s), SC-005 (au plus 2 écritures par fenêtre et par version), SC-007 (0 relecture de l'état par passe sans écriture externe).

## Contexte de revue antérieure
Contre-revue Codex en 3 rounds (plan x2, implémentation), convergence passes 1 et 2 (T201-T225, toutes cochées). Les constats corrigés ne sont pas réinventés ; ils sont vérifiés s'ils réapparaissent dans le code.
