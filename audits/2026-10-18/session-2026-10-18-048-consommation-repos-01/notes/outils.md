# Outils - révision 1 (cycle final readonly)

| Contrôle | Exécution (runs/) | Résultat | Portée réelle et limites |
|---|---|---|---|
| Compilation | 20261018T173021917521Z `swift build --build-tests` | exit 0, RailController recompilé | Swift 6, concurrence stricte : typage sources et tests |
| Tests | 20261018T173027311569Z `swift test --skip-build` | 1 721 tests / 203 suites verts, dont Spec048* | Les deux tests instables connus (047) ont réussi : aucune relance nécessaire |
| Semgrep | 20261018T173347636496Z | 0 résultat | 24 règles sur 25 fichiers : Swift = 1 règle (9 fichiers), multilangue 2, Python 21 (script de mesure). Couverture statique Swift quasi nulle : l'analyse manuelle porte le contrôle |
| Gitleaks fichiers (adaptateur) | 20261018T173350769733Z | 0 octet analysé | Vide : la liste d'exclusion figée `(^\|/)\.worktrees/` correspond au chemin absolu de la racine (worktree) |
| Gitleaks fichiers (complément) | 20261018T173350995886Z `gitleaks dir .` même config, `--max-target-megabytes 5` | 218 Mo analysés, aucune fuite | Chemins relatifs : l'exclusion ne masque plus tout. Fichiers > 5 Mo (index et paquets `.build`) ignorés |
| Gitleaks historique | 20261018T171738924329Z (et 20261018T170642056975Z en r0) | timeout 300 s, deux fois | Plafond `tool_seconds` = 300 s de la politique ; `--seconds 900` est ramené à 300. Aucun commit dans le périmètre (HEAD = base d32105c8) |
| OSV (adaptateur) | 20261018T171142543043Z (r0) | erreur 128, aucune source | Le worktree est ignoré par le `.gitignore` du dépôt parent (`.worktrees/`) |
| OSV (complément) | 20261018T173400927587Z `osv-scanner scan source --lockfile Package.resolved` | 1 paquet (TOMLKit 0.6.0), aucun avis | Base OSV en ligne à la date du run ; Package.swift et Package.resolved inchangés depuis la base (`git diff --stat d32105c8` vide) |

Budget cumulé consommé : environ 712 s sur 1 800 s.
