# Découverte - session 020-cef-web-hints, 2e audit

- Mode XS : 3 fichiers, +290/-26 lignes contre le merge-base `1bdd65e` (avant correction). Session 01 : +216/-19.
- Changements depuis la session 01 (T012) : `CFIdentitySet` (hash puis `CFEqual`) dans le parcours et `copyChildren` ; cadre lu pour tout élément de zone web ; pas de descente sous 4 points (`isHintable`) ; marqueur « inconnu » seulement si caché (`hidesContent`) ; `duplicatesTarget` (≥ 80 %) remplace le comptage `leavesKeptUnderCandidates` ; feuilles ajoutées sous `max_targets`.
- Hot path : double Commande -> `LiveAppTargetProvider.candidates` -> `scan()` (une à trois passes, budget `timeout_ms`) -> `focusableLeaves` -> `targets(from:)`.
- Surface d'attaque : arbre AX de l'application au premier plan. Pas de réseau, pas de configuration, pas de dépendance.
- Référence tests : `./scripts/test` 836 tests, 90 suites, exit 0 avant toute correction.
