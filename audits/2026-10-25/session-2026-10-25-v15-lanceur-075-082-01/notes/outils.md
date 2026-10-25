# Outils

- Semgrep : règles figées sur les fichiers sélectionnés, 0 résultat (une seule règle Swift dans le
  pack : l'analyse manuelle porte le contrôle).
- Gitleaks fichiers : 0 fuite. Gitleaks historique : plage v0.10.0 (410ed34a)..HEAD, 0 fuite.
- OSV-Scanner : l'adaptateur récursif a échoué (« No package sources found », code 128, parcours
  d'un seul dossier) ; relance par l'exécuteur en commande personnalisée sur `Package.resolved` :
  0 avis. Manifestes `Package.swift`/`Package.resolved` inchangés depuis la base.
- Tests : `scripts/test --no-parallel` par l'exécuteur, 2 028 tests / 277 suites réussis.
- Pas de linter Swift configuré dans le projet ; pas de CodeQL Swift.

## Révision 1 (0a579d60)
Mêmes contrôles relancés : Semgrep 0, Gitleaks 0, historique v0.10.0..HEAD 0, OSV sur
`Package.resolved` 0 avis, tests 2 028 / 277 réussis.
Cause de l'échec de l'adaptateur OSV vérifiée hors preuve : le worktree vit sous `.worktrees/`, ignoré
par Git dans le dépôt principal ; `osv-scanner scan source -r .` ne voit rien, `--no-ignore` trouve
`Package.resolved` (1 paquet). L'adaptateur ne passe pas cette option : contrôle laissé inconnu.
