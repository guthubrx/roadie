# Réfutation déterministe des alertes historiques

18 alertes generic-api-key proviennent de cartes JSON d’empreintes déjà archivées.
Pour chacune : git show COMMIT:carte, lecture de la ligne signalée, puis git show COMMIT:fichier nommé et SHA256 des octets.
Les 18 valeurs sont exactement les empreintes de leur fichier source à ce commit. Ce ne sont pas des identifiants d’accès.
Aucun secret utilisé ni essai réseau. Aucun changement de règle, baseline ou allowlist.
Contre-vérification locale : même responsable, independent=false ; revue distante finale demandée séparément.

| Carte | Ligne | Fichier nommé | Commit | Résultat |
|---|---:|---|---|---|
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 87 | Sources/RoadieAX/WindowKeyFocus.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 88 | Sources/RoadieAX/WindowSwitcherWindowAccess.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 89 | Sources/RoadieAX/WindowTitleDragAccess.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 318 | Tests/RoadieAXTests/Spec098WindowKeyFocusTests.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 479 | Tests/RoadieDaemonTests/Spec075KeysTests.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json | 511 | Tests/RoadieDaemonTests/Spec100DeadKeyTests.swift | 90703f0962c66952d4beaee04bf7b0ed0be72f41 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 87 | Sources/RoadieAX/WindowKeyFocus.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 88 | Sources/RoadieAX/WindowSwitcherWindowAccess.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 89 | Sources/RoadieAX/WindowTitleDragAccess.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 318 | Tests/RoadieAXTests/Spec098WindowKeyFocusTests.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 479 | Tests/RoadieDaemonTests/Spec075KeysTests.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json | 511 | Tests/RoadieDaemonTests/Spec100DeadKeyTests.swift | edd99a41b228ad35f41079dddc5860401a6c1441 | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 90 | Sources/RoadieAX/WindowKeyFocus.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 91 | Sources/RoadieAX/WindowSwitcherWindowAccess.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 92 | Sources/RoadieAX/WindowTitleDragAccess.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 321 | Tests/RoadieAXTests/Spec098WindowKeyFocusTests.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 482 | Tests/RoadieDaemonTests/Spec075KeysTests.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
| audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json | 514 | Tests/RoadieDaemonTests/Spec100DeadKeyTests.swift | fe63993caa507b9a9e8f96b824a344850d485b4d | SHA-256 des octets source identique |
