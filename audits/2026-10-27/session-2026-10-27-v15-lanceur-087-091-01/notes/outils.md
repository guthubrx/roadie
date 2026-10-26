# Outils

Révision 0 (e393b467) puis révision 1 (01789d19), mêmes contrôles :
- Semgrep sur les fichiers sélectionnés : 0 résultat (pack figé, peu de règles Swift).
- Gitleaks fichiers : 0. Gitleaks historique, plage 50e36a43..HEAD : 0.
- OSV-Scanner depuis le checkout principal : terminé, 0 avis (le défaut d'adaptateur des worktrees
  noté en 082 est évité).
- Tests par l'exécuteur : `scripts/test --package-path <worktree> --no-parallel`, worktree au même
  commit que le manifeste (vérifié `git rev-parse HEAD`) : révision 0 2 085 tests / 291 suites,
  révision 1 2 086 tests / 292 suites, tous réussis.
- Mesures de la session : corpus de 102 workflows (`roadie workflow check`), R8 `AXIsProcessTrusted`.
