# Outils - session 049 readonly (révision 0)

| Contrôle | Exécution (runs/) | Résultat | Portée réelle et limites |
|---|---|---|---|
| Compilation | 20261018T181013450756Z `swift build --build-tests --scratch-path /tmp/roadie-build-audit-049` | exit 0, 43 s | Aucun avertissement dans les fichiers du diff |
| Tests | 20261018T181057504048Z `swift test --skip-build` | 1 736 tests / 206 suites verts | Dont 5 tests Spec049 ; les deux tests instables connus ont réussi, aucune relance |
| Semgrep | 20261018T181124817830Z | 10 fichiers, 0 résultat | 163 règles figées, 1 seule Swift |
| Gitleaks fichiers (adaptateur) | 20261018T181124192591Z | ~7,75 Mo analysés, aucune fuite | Worktree `/tmp` : exclusion `.worktrees/` sans effet sur la racine ; `audits/` exclu |
| Gitleaks historique | 20261018T181123789883Z `--tool custom` : `gitleaks git <racine> --log-opts=v0.4.0..3dd5563b --report-path -` | 71 commits, ~3,04 Mo, aucune fuite | Décision utilisateur option A (18/10/2026). Le runner refuse `--command` avec `--tool gitleaks-history` : limite inscrite par le moteur. Historique antérieur à v0.4.0 non analysé |
| OSV (adaptateur) | 20261018T181127797472Z | 1 paquet, aucun avis | Manifestes inchangés |
| Préférences réelles | 20261018T181128556802Z `/usr/bin/defaults read com.apple.WindowManager` | 4 clés à 0 | Lecture seule ; observation de la machine de l'utilisateur, pas du binaire installé |

Budget cumulé consommé : environ 60 s sur 1 800 s.
