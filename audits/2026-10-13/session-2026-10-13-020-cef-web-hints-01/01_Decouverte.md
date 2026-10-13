# Découverte - session 020-cef-web-hints

- Mode XS : 3 fichiers, +216/-19 lignes contre le merge-base `1bdd65e` (état final, correction comprise).
- Langage : Swift 6, SwiftPM, Swift Testing. Démon macOS, API Accessibilité (AX).
- Hot path : double Commande -> `LiveAppTargetProvider.candidates` -> `scan()` (une à trois passes, budget `timeout_ms`) -> `focusableLeaves` / `leavesKeptUnderCandidates` -> `targets(from:)`.
- Surface d'attaque : arbre AX de l'application au premier plan (rôles, titres, cadres fournis par une application tierce). Pas de réseau, pas de nouvelle configuration, pas de dépendance.
- Données journalisées : `targets.app_scan` gagne `focusableAdded` et `rejectedRoles` (noms de rôles et compteurs, aucun texte).
- Référence tests : `./scripts/test` 833 tests, 90 suites, exit 0 avant toute correction.
