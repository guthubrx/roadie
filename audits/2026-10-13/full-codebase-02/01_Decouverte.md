# Découverte

{
  "audit_meta": {
    "version": "v14.0",
    "timestamp": "2026-10-13T13:29:21.438160+00:00",
    "scope": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation",
    "scope_mode": "full",
    "mode": "S / LIGHT",
    "grid": "all",
    "head": "4766213e1a00b7d96e1ba959d1b0b277863a4939",
    "parallelism_note": "Six lectures thématiques et une contre-lecture indépendante; mêmes règles de sévérité et de notation que le premier audit."
  },
  "repo": {
    "files_count": 194,
    "production_swift_count": 96,
    "test_swift_count": 96,
    "languages": [
      "Swift",
      "Python",
      "Shell"
    ],
    "frameworks": [
      "AppKit",
      "ApplicationServices",
      "Swift Testing",
      "TOMLKit"
    ],
    "type": "macOS desktop daemon + CLI",
    "has_ui": true,
    "has_llm_integration": false,
    "db_type": "JSON files",
    "ci_system": null,
    "container": false
  },
  "sampling": null,
  "hot_paths": [
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift",
      "entry": "serve/respond"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift",
      "entry": "run"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift",
      "entry": "tick"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift",
      "entry": "windows/focus"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift",
      "entry": "SnapshotService"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift",
      "entry": "refresh"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift",
      "entry": "handle"
    },
    {
      "file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/JSONPersistence.swift",
      "entry": "mutate"
    }
  ],
  "threat_model": {
    "assets": [
      "État persistant des fenêtres",
      "Focus et géométrie du bureau",
      "Titres de fenêtres et captures",
      "Configuration et journaux"
    ],
    "attackers": [
      "Processus local du même utilisateur",
      "Autre compte local",
      "Dépendance compromise"
    ],
    "surface": [
      "Socket Unix",
      "Commandes CLI",
      "Fichiers TOML/JSON",
      "Accessibilité macOS et événements clavier/souris"
    ],
    "internet_listener": false
  },
  "slos": {
    "defined": false,
    "proposed": {
      "note": "Mesurer latence des commandes et du placement sur bureau représentatif; aucune valeur inventée."
    }
  },
  "modules_actifs": [
    "00",
    "01",
    "02",
    "03",
    "04",
    "05",
    "06",
    "07",
    "08",
    "09",
    "10",
    "11",
    "12"
  ]
}

Couverture : 96/96 fichiers Swift de production lus intégralement. Tests, scripts et documentation lus par risque. Détails : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/read-inventory.json
