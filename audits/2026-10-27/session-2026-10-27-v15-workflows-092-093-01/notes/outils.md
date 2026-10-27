# Outils
`doctor` : semgrep, gitleaks, osv-scanner, trivy présents ; CodeQL et opengrep absents.
- Semgrep (fichiers sélectionnés), Gitleaks fichiers, Gitleaks historique borné depuis `5ed75b05`,
  OSV-Scanner (dépôt, `Package.resolved`) : 0 candidat, aux deux révisions.
- Tests : `scripts/test --package-path <worktree> --no-parallel` (worktree vérifié au commit du
  manifeste avant chaque exécution) : réussis aux deux révisions.
- Trivy : non applicable (aucun conteneur ni infrastructure). Knip, dependency-cruiser, Ruff : non
  applicables (Swift). Pas de linter Swift configuré dans le projet.
