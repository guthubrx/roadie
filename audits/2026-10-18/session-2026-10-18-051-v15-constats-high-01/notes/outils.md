# Outils - session 051 readonly (révision 0)

| Contrôle | Exécution (runs/) | Résultat | Portée réelle et limites |
|---|---|---|---|
| Compilation | 20261018T180313235252Z `swift build --build-tests --scratch-path /tmp/roadie-build-audit-051` | exit 0, 51 s | Aucun avertissement dans les fichiers du diff (seul `DaemonSnapshot.swift:2368`, ligne antérieure à la 051) |
| Tests | 20261018T180405368306Z `swift test --skip-build` | 1 731 tests / 205 suites verts | Les deux tests instables connus ont réussi : aucune relance |
| Semgrep | 20261018T180434073021Z | 18 fichiers, 0 résultat, 0 erreur | 163 règles figées, 1 seule Swift : couverture statique Swift quasi nulle |
| Gitleaks fichiers (adaptateur) | 20261018T180433357791Z | ~7,74 Mo analysés, aucune fuite | Worktree `/tmp` : l'exclusion `.worktrees/` ne masque plus la racine ; `audits/` exclu |
| Gitleaks historique | 20261018T180432844325Z `--tool custom` : `gitleaks git <racine> --log-opts=v0.4.0..38f69a6a --report-path -` | 70 commits, ~3,03 Mo, aucune fuite | Décision utilisateur option A (18/10/2026). Le runner refuse `--command` avec `--tool gitleaks-history` : pas d'exécution de l'adaptateur dédié, limite inscrite par le moteur. Historique antérieur à v0.4.0 non analysé |
| OSV (adaptateur) | 20261018T180437250281Z | `Package.resolved` : 1 paquet, aucun avis | Manifestes inchangés depuis la base |

Budget cumulé consommé : environ 65 s sur 1 800 s.
