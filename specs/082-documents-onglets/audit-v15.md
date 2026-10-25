# Audit V15 des sessions 075 à 082

Session : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-25/session-2026-10-25-v15-lanceur-075-082-01
Mode correction, base 6daaa8b2, révision 1 = 0a579d60 (44 fichiers sélectionnés).

- Décision : **inconclusive**, release_blocked = true, note indicative 95 (N/A).
- Cause unique : contrôle security.dependencies non vérifié. L'adaptateur OSV échoue (worktree
  sous .worktrees/, ignoré par Git ; l'adaptateur ne passe pas --no-ignore). Relance sur
  Package.resolved par l'exécuteur : 0 avis ; manifestes inchangés depuis la base.
- Contrôles réussis : Semgrep 0, Gitleaks fichiers 0, historique v0.10.0..0a579d60 0, tests
  2 028 / 277, et les dix contrôles d'analyse.
- Constats : F1 MEDIUM (onglets lus à l'ouverture, demande d'automatisation), F2 LOW (écriture
  synchrone par déplacement), F3 LOW (première fenêtre nouvelle du paquet), F4 LOW corrigé
  (stage mémorisée pour /tmp, commit 0a579d60, test ajouté).
- Revue indépendante : aucune (Bridget : capability_unavailable puis project_mapping_unknown).
- Notes par axe : axis-scoring.md de la session.
