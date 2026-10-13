# Découverte v14

Racine : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation

96 fichiers Swift de production, 105 de tests; 203 fichiers source comptés. Tous les fichiers de production sont affectés à une lecture. Tests et documentation sont lus selon le risque. Aucune mesure de couverture instrumentée.

## Chemins fréquents

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift : serve/respond
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift : run
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift : tick
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift : windows/focus
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift : SnapshotService
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift : refresh
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift : handle
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/JSONPersistence.swift : mutate

## Menaces

Application locale macOS : état JSON, focus, géométrie et captures à protéger. Surface : socket Unix, arguments CLI, fichiers TOML/JSON et API Accessibilité. Menaces : autre utilisateur local, processus du même compte, dépendance compromise. Pas de serveur Internet, SQL, paiement ou moteur LLM identifié.

## Changements fréquents (90 jours)

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift : 20 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift : 18 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift : 17 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift : 12 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift : 11 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift : 10 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowBookmarkCommands.swift : 9 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift : 9 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift : 9 commits
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/roadied/main.swift : 9 commits

## SLO

Pas de cible de service établie; proposer une mesure du délai des commandes et du placement sur un bureau représentatif avant de choisir les seuils.
