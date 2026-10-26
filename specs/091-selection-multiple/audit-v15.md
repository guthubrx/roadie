# Audit V15 des sessions 087 à 091

Session : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-27/session-2026-10-27-v15-lanceur-087-091-01
Mode correction, base 50e36a43, révision 0 = e393b467, révision 1 = 01789d19 (89 fichiers sélectionnés).
Lancé depuis le checkout principal : le contrôle des dépendances (OSV) aboutit.

- Décision : **pass**, release_blocked = false, note indicative A (100).
- Contrôles réussis aux deux révisions : Semgrep 0, Gitleaks fichiers 0, historique 50e36a43..HEAD 0,
  OSV 0 avis, tests par l'exécuteur 2 085 puis 2 086 / 292 suites, et les dix contrôles d'analyse.
- Constats : F1 MEDIUM corrigé (presse-papiers remis en entier après la copie simulée de la
  sélection, commit 01789d19, test `AuditV15LanceurTests`) ; F2 INFO confirmé (un script de workflow
  obtient l'autorisation Accessibilité du démon, mesuré ; atténuations écrites).
- Notes par axe (qualité observée) : métier et traçabilité 75, architecture 69, complexité, qualité et
  minimalisme 67, tests 65, fiabilité 63, sécurité 60, performance et responsabilité future 50.
  Manques principaux : latence non mesurée, pas de linter Swift ni de CodeQL, aucune revue
  indépendante (Bridget : project_mapping_unknown, origin_request_invalid).
- Détail : axis-scoring.md et scoring.md de la session.
