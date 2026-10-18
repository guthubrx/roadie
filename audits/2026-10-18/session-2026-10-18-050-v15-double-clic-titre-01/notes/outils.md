# Outils - session 050 readonly (révision 0)

| Contrôle | Exécution (runs/) | Résultat | Portée réelle et limites |
|---|---|---|---|
| Compilation | 20261018T181307730317Z `swift build --build-tests --scratch-path /tmp/roadie-build-audit-050` | exit 0, 44 s | Aucun avertissement dans les fichiers du diff |
| Tests | 20261018T181353173059Z `swift test --skip-build` | 1 742 tests / 207 suites verts | Dont 6 tests Spec050 ; les deux tests instables connus ont réussi, aucune relance |
| Semgrep | 20261018T181435857327Z | 14 fichiers, 0 résultat | 163 règles figées, 1 seule Swift |
| Gitleaks fichiers (adaptateur) | 20261018T181435213558Z | ~7,77 Mo analysés, aucune fuite | `audits/` exclu ; exclusion `.worktrees/` sans effet sous `/tmp` |
| Gitleaks historique | 20261018T181434803820Z `--tool custom` : `gitleaks git <racine> --log-opts=v0.4.0..8c207d67 --report-path -` | 73 commits, ~3,06 Mo, aucune fuite | Décision utilisateur option A (18/10/2026). Le runner refuse `--command` avec `--tool gitleaks-history` : limite inscrite par le moteur. Historique antérieur à v0.4.0 non analysé |
| OSV (adaptateur) | 20261018T181438819967Z | 1 paquet, aucun avis | Manifestes inchangés |
| Préférences réelles | 20261018T181439624967Z, 20261018T181439810239Z `defaults read -g` | clé d'action absente ; réduction héritée = 0 | Lecture seule |
| Config utilisateur | 20261018T181452406416Z `grep` | section présente, sans `double_click_maximize` | Lecture seule |
| Reproduction isolée (build) | 20261018T181745533802Z puis 20261018T181907817940Z `swift build --package-path /tmp/roadie-repro-050` | exit 0 | Copie `git archive` du commit dans `/tmp/roadie-repro-050` + un fichier de test (copie conservée dans `repro/`). Racine auditée inchangée |
| Reproduction isolée (tests) | 20261018T181855206693Z puis 20261018T181919915545Z `swift test --filter Repro050` | 2 tests verts | Témoin sans geste et double-clic avec geste ouvert ; voir `constats.md` |

Budget cumulé consommé : environ 130 s sur 1 800 s.
