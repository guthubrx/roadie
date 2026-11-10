# Base de référence - 155

Mesures prises avant toute modification (tâche T001). Remplace chaque `À REMPLIR`.

- Date et heure : À REMPLIR
- Commit de départ (`git rev-parse HEAD`) : À REMPLIR
- `./scripts/test --no-parallel` : À REMPLIR tests / À REMPLIR suites, code de retour À REMPLIR
- `python3 -I -B -m unittest discover -s scripts/tests` : À REMPLIR tests, résultat À REMPLIR
- `wc -c AGENTS.md` : À REMPLIR octets
- `wc -l Sources/RoadieDaemon/LayoutMaintainer.swift` : À REMPLIR lignes

Valeurs attendues (relevées le 10 novembre 2026 sur le commit `0b7de36b`) : 2 523 tests /
383 suites, code 0 ; 28 tests de scripts, `OK` ; 39 858 octets ; 4 462 lignes.

`wc -c AGENTS.md` donne 39 858 sur le commit de départ. Dans ce worktree, la préparation a
déjà changé quatre lignes du bloc SpecKit : une différence de quelques octets est normale.
