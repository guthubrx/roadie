## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 50/100 (F) | 50 | 5/5 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 40/100 (F) | 13 | 1/4 | Provisoire |
| Tests et validation | 57/100 (F) | 35 | 3/5 | Provisoire |
| Performance et ressources | 49/100 (F) | 25 | 2/4 | Provisoire |
| Complexité algorithmique | 49/100 (F) | 49 | 3/3 | Provisoire |
| Qualité du code et des erreurs | 49/100 (F) | 33 | 2/3 | Provisoire |
| Architecture et dépendances | 50/100 (F) | 38 | 3/4 | Provisoire |
| Responsabilité future et hygiène | 42/100 (F) | 42 | 3/3 | Provisoire |
| Minimalisme et frugalité | 63/100 (D) | 42 | 2/3 | Provisoire |
| Métier et fidélité des données | 40/100 (F) | 33 | 2/3 | Provisoire |
| Traçabilité des exigences | 38/100 (F) | 38 | 2/2 | Provisoire |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep (0 signal), SwiftLint 6 règles (45 signaux relus) et lecture des nouvelles entrées ; peu de règles Swift. Le niveau supérieur exige une qualification plus complète. |
| Protection des secrets courants | 2 | Gitleaks sur les fichiers figés : 0 signal ; aucun contrôle continu démontré. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des secrets historiques | 2 | Historique depuis v0.4.0 sans signal ; l'historique complet a dépassé 300 s. Le niveau supérieur exige une qualification plus complète. |
| Authentification et séparation des droits | 2 | Socket local 0600, chemins de workflows et réglages gardés protégés ; scripts de workflow exécutés avec les droits de l'utilisateur, par conception. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des dépendances vulnérables | 2 | OSV : une dépendance verrouillée sans avis ; suivi continu non démontré. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : security.authorization

### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucun appel à un service LLM dans les sources ni dans les dépendances du produit. |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM dans les sources ni dans les dépendances du produit. |
| Résistance aux instructions malveillantes | Non applicable | Aucun appel à un service LLM dans les sources ni dans les dépendances du produit. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Reprise des traitements interrompus | 2 | Groupes de processus arrêtés au délai ou à la frappe, pause BTT rétablie au démarrage ; délais inadaptés pour Run Script et Spotlight, pas d'escalade si un script ignore SIGTERM et SIGINT. Le niveau supérieur exige une qualification plus complète. |
| Continuité pendant une bascule | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Restauration après sinistre | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.reliability.01
- Contrôle non vérifié : axes.reliability.03
- Contrôle non vérifié : axes.reliability.04
- Contrôle commun non vérifié : correctness.concurrency
- Contrôle commun non vérifié : reliability.observability
- 3 critère(s) sans niveau de qualité justifié

### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Sources et tests Swift compilés au commit figé ; avertissements existants conservés. Le niveau supérieur exige une qualification plus complète. |
| Analyse de style et erreurs statiques | 2 | Semgrep et SwiftLint ciblé exécutés ; tous les signaux et règles Swift ne sont pas qualifiés. Le niveau supérieur exige une qualification plus complète. |
| Régressions et cas limites | 2 | 2 267 tests réussis, mais trois défauts confirmés n'étaient couverts par aucun test et le test d'équivalence de l'index n'a pas vu la valeur vide. Le niveau supérieur exige une qualification plus complète. |
| Qualification du runtime livré | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Tests interface et intégration des données | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.tests.04
- Contrôle non vérifié : axes.tests.05
- 2 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Barre : attente de 100 ms entre frappes, une requête Spotlight à la fois, relance des filtres bornée à 0,1-5 s ; pas d'essai de saturation. Le niveau supérieur exige une qualification plus complète. |
| Budget mémoire | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Délais, annulation et libération | 2 | Délais, annulation et plafonds de sortie présents ; deux délais contredisent l'usage (F-RUNSCRIPT, F-SPOTLIGHT). Le niveau supérieur exige une qualification plus complète. |
| Mesures représentatives de latence et charge | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.performance.02
- Contrôle non vérifié : axes.performance.04
- Contrôle commun non vérifié : performance.complexity
- 2 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 2 | Points d'entrée chauds relus après une heuristique sur tout Sources ; annotations de complexité absentes sur plusieurs recherches. Le niveau supérieur exige une qualification plus complète. |
| Bornes des parcours et allocations | 2 | Parcours AX bornés, caches bornés ; un parcours quadratique (n ≤ 4 000) et une requête de fichiers récents sans plafond. Le niveau supérieur exige une qualification plus complète. |
| Coût des accès et écritures de données | 2 | Index TOML O(L) puis O(1), copies SQLite hors du fil principal avec cache ; coût disque des copies non mesuré. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : performance.complexity

### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 2 | Messages traduits et refus explicites ; reconstruction Spotlight et commandes système sans retour d'échec. Le niveau supérieur exige une qualification plus complète. |
| Gestion des erreurs partielles | 2 | Retour arrière des tâches d'automatisation et échange atomique relus ; interruption réelle non simulée. Le niveau supérieur exige une qualification plus complète. |
| Ergonomie des parcours concernés | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 2 | Frontières SwiftPM claires ; RoadieDaemon de 62 730 lignes sans frontières internes mesurées. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des cycles | 2 | Cycles de modules impossibles par SwiftPM ; cycles internes au module non analysés. Le niveau supérieur exige une qualification plus complète. |
| Séparation construction et exécution | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Assemblages et dépendances dynamiques | 2 | Symboles privés de macOS chargés par dlsym et protégés par des optionnels ; leur disparition dégraderait la fonction sans arrêt, non testé sur d'autres versions. Le niveau supérieur exige une qualification plus complète. |

- Contrôle non vérifié : axes.architecture.03
- 1 critère(s) sans niveau de qualité justifié

### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 2 | Invariants, bornes et complexités commentés dans le code récent ; plusieurs recherches sans annotation. Le niveau supérieur exige une qualification plus complète. |
| Périmètre et maintenabilité du changement | 2 | Changements ciblés par session et tests associés ; trois fichiers de plus de 2 000 lignes alourdissent la maintenance. Le niveau supérieur exige une qualification plus complète. |
| Revue contradictoire et responsabilité | 1 | Aucune revue indépendante : délégation Bridget absente du catalogue ; relecture par le même agent. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : quality.llm

### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Une seule dépendance d'exploitation, verrouillée et utilisée pour la configuration. Le niveau supérieur exige une qualification plus complète. |
| Poids et ressources justifiés | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Code mort et simplifications possibles | 2 | ~10 lignes suppressibles relevées sur un échantillon ; pas de recherche de code mort sur tout le dépôt. Le niveau supérieur exige une qualification plus complète. |

- Contrôle non vérifié : axes.minimalism.02
- Contrôle commun non vérifié : quality.minimalism
- 1 critère(s) sans niveau de qualité justifié

### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 2 | Signets et historiques lus sur copie ; affichage d'une valeur non appliquée pour un fichier TOML invalide (F-LITERAL-EMPTY). Le niveau supérieur exige une qualification plus complète. |
| Cohérence et idempotence des versions | Non vérifié | Non vérifié dans cet audit ; preuve ou mesure insuffisante. |
| Conformité aux règles et données de référence | 2 | Spec 088 et 127 rapprochées : Run Script plus restrictif que la spec, traduction complète vérifiée par recherche des textes restants. Le niveau supérieur exige une qualification plus complète. |

- Contrôle non vérifié : axes.business.02
- Contrôle commun non vérifié : correctness.logic
- 1 critère(s) sans niveau de qualité justifié

### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 2 | Chaque constat relié à sa reproduction, ses exécutions et ses variantes. Le niveau supérieur exige une qualification plus complète. |
| Couverture des exigences obligatoires | 1 | Exigences de 2 spécifications sur 128 vérifiées. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : spec.traceability
