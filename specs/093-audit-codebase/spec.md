# Session 093 — Audit et corrections de la base de code

## Demande

Auditer l'ensemble du dépôt Roadie et corriger les défauts confirmés. Réaliser cinq cycles au maximum, puis une revue finale en lecture seule, selon le protocole Audit Code V15.

## Périmètre et limites

- Sources, tests, scripts, dépendances, configuration, documentation et contrats présents dans le dépôt.
- Historique Git examiné selon la borne autorisée précédemment ; indiquer toute partie non examinée.
- Corriger les défauts non ambigus et conserver les preuves avant et après correction.
- Ne pas installer, déployer, publier ou créer de commit automatiquement.
- Documenter les contrôles incomplets, les fonctions non lues et les limites des outils.

## Validation

Chaque correction doit avoir une reproduction, une recherche de variantes et une vérification ciblée. Les tests de régression adaptés et la décision calculée V15 portent sur la dernière révision. Les effets visibles nécessitent les preuves prévues par la compétence `preuves-correction`.
