# Audit V15 des sessions 092 et 093

Session : `audits/2026-10-27/session-2026-10-27-v15-workflows-092-093-01/` (fix, une révision de
correction). Racine : copie propre `/tmp/roadie-audit-092-093` (le checkout principal était occupé par
une autre session). Base `5ed75b05` ; révision 0 `2d81ec04`, révision 1 `b90f53d7`.

**Décision : `pass`, note A, `release_blocked` faux.** Aucun constat ouvert.

| Constat | Sévérité | Issue |
|---|---|---|
| F1 Fichier `.js` traduit relu comme AppleScript (`OsascriptCall.rebuilt`) | MEDIUM | corrigé, testé (exécution réelle) |
| F2 Réglage gardé sans workflow écrit dans `.json` | LOW | corrigé, testé |
| F3 `running()` absent de l'objet JavaScript | LOW | corrigé, testé (exécution réelle) |

Contrôles : Semgrep, Gitleaks (fichiers, historique depuis `5ed75b05`), OSV : 0 candidat aux deux
révisions ; suite complète réussie (2 110 tests). Variantes recherchées (`notes/variantes.md`).

Notes par axe (calculées) : sécurité 60, fiabilité 63, tests 65, performance 50, complexité 67,
qualité 67, architecture 69, responsabilité future 58, minimalisme 67, métier 75, traçabilité 75.

Limites : revue indépendante absente (Bridget `origin_request_invalid`) ; latence de la grille et coût
du passage par `roadie` non mesurés ; rendu des tuiles non capturé ; pas de linter Swift ; Semgrep a peu
de règles Swift.
