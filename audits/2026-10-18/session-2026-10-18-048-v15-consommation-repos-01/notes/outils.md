# Outils - session 048 readonly (révision 0)

| Contrôle | Exécution (runs/) | Résultat | Portée réelle et limites |
|---|---|---|---|
| Compilation | 20261018T175716804629Z `swift build --build-tests --scratch-path /tmp/roadie-build-audit-048` | exit 0, 50 s | Swift 6 ; 84 lignes d'avertissement, toutes dans des fichiers hors diff (ex. `DaemonSnapshot.swift:2356` daté du 13/10, tests Audit022/Spec029/TickScheduler) |
| Tests | 20261018T175828587883Z `swift test --skip-build` | 1 721 tests / 203 suites verts | Les deux tests instables connus ont réussi : aucune relance |
| Semgrep | 20261018T175929318683Z | 24 fichiers analysés, 0 résultat, 0 erreur | 163 règles figées (core.yml + pack CI) dont 1 seule pour Swift, 21 Python, 7 génériques. Couverture statique Swift quasi nulle : l'analyse manuelle porte le contrôle |
| Gitleaks fichiers (adaptateur) | 20261018T175918180487Z | ~7,72 Mo analysés, aucune fuite | Le worktree est sous `/tmp` : l'exclusion figée `.worktrees/` ne masque plus la racine. `audits/` exclu par la configuration figée |
| Gitleaks historique | 20261018T175910740477Z `--tool custom` : `gitleaks git <racine> --log-opts=v0.4.0..ab9b28e9 --report-path -` | 69 commits, ~3,01 Mo, aucune fuite | Décision utilisateur option A (18/10/2026). Le runner refuse `--command` avec `--tool gitleaks-history` (« Les arguments libres nécessitent --tool custom ») : le contrôle reste sans exécution de l'adaptateur dédié, le moteur l'inscrit en limite. Historique antérieur à v0.4.0 non analysé. Configuration Gitleaks par défaut (comme l'adaptateur) |
| Gitleaks historique, 1re tentative | 20261018T175857457093Z `--report-path /dev/stdout` | erreur 1 (« open /dev/stdout: permission denied ») | Tentative conservée, remplacée par `--report-path -` |
| OSV (adaptateur) | 20261018T175932814586Z | `Package.resolved` : 1 paquet, aucun avis | Base OSV en ligne à la date du run ; `Package.swift` et `Package.resolved` inchangés depuis la base |

Budget cumulé consommé : environ 65 s sur 1 800 s.
