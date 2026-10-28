# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie
Sources : commit 5ed75b0532c4179c2b6b7d6a4a88e5e2ec2e92fd ; mode fix.
Décision : **inconclusive** ; note globale : N/A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 5/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 50/100 (F) | 50 | 5/5 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 25 | 2/4 | Provisoire |
| Tests et validation | 58/100 (F) | 35 | 3/5 | Provisoire |
| Performance et ressources | 50/100 (F) | 13 | 1/4 | Provisoire |
| Complexité algorithmique | 50/100 (F) | 33 | 2/3 | Provisoire |
| Qualité du code et des erreurs | 50/100 (F) | 33 | 2/3 | Provisoire |
| Architecture et dépendances | 50/100 (F) | 25 | 2/4 | Provisoire |
| Responsabilité future et hygiène | 58/100 (F) | 58 | 3/3 | Provisoire |
| Minimalisme et frugalité | 50/100 (F) | 17 | 1/3 | Provisoire |
| Métier et fidélité des données | 50/100 (F) | 33 | 2/3 | Provisoire |
| Traçabilité des exigences | 50/100 (F) | 25 | 1/2 | Provisoire |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep et cinq règles SwiftLint ; une seule règle Semgrep Swift, lecture manuelle partielle. Le niveau supérieur exige une qualification plus complète. |
| Protection des secrets courants | 2 | Recherche locale des secrets des fichiers ; configuration d'exclusion figée, pas de contrôle continu démontré. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des secrets historiques | 2 | Historique examiné depuis v0.4.0 ; commits antérieurs exclus. Le niveau supérieur exige une qualification plus complète. |
| Authentification et séparation des droits | 2 | Socket local 0600 examiné ; scripts de workflow exécutés avec les droits de l'utilisateur, sans isolement démontré. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des dépendances vulnérables | 2 | OSV a examiné une dépendance Swift verrouillée ; suivi continu non démontré. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : security.authorization

### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucun appel à un service LLM trouvé dans les sources et dépendances du produit. |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM trouvé dans les sources et dépendances du produit. |
| Résistance aux instructions malveillantes | Non applicable | Aucun appel à un service LLM trouvé dans les sources et dépendances du produit. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Fichiers illisibles conservés et écritures transactionnelles testées sur cinq magasins ; restauration globale non testée. Le niveau supérieur exige une qualification plus complète. |
| Reprise des traitements interrompus | 2 | Échange atomique et panne injectée testés ; interruption réelle pendant l'échange non testée. Le niveau supérieur exige une qualification plus complète. |
| Continuité pendant une bascule | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Restauration après sinistre | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.reliability.03
- Contrôle non vérifié : axes.reliability.04
- Contrôle commun non vérifié : correctness.concurrency
- Contrôle commun non vérifié : reliability.observability
- 2 critère(s) sans niveau de qualité justifié

### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Sources et tests Swift compilés ; avertissements existants et suites exclues conservés. Le niveau supérieur exige une qualification plus complète. |
| Analyse de style et erreurs statiques | 2 | Semgrep et SwiftLint ciblé exécutés ; toutes les règles Swift et tous les signaux ne sont pas qualifiés. Le niveau supérieur exige une qualification plus complète. |
| Régressions et cas limites | 2 | Suite Swift et tests ciblés réussis ; trois suites exclues et parcours graphique non exécuté. Le niveau supérieur exige une qualification plus complète. |
| Qualification du runtime livré | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Tests interface et intégration des données | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.tests.04
- Contrôle non vérifié : axes.tests.05
- 2 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Budget mémoire | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Délais, annulation et libération | 2 | Délai et annulation du lanceur lus ; tests de signaux groupés exclus. Le niveau supérieur exige une qualification plus complète. |
| Mesures représentatives de latence et charge | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.performance.01
- Contrôle non vérifié : axes.performance.02
- Contrôle non vérifié : axes.performance.04
- Contrôle commun non vérifié : performance.complexity
- 3 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 2 | Quelques chemins critiques lus ; inventaire des complexités de tous les points d'entrée incomplet. Le niveau supérieur exige une qualification plus complète. |
| Bornes des parcours et allocations | 2 | Borne de récursion et allocations examinées sur les calculs et sorties de scripts ; reste du dépôt partiel. Le niveau supérieur exige une qualification plus complète. |
| Coût des accès et écritures de données | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.complexity.03
- Contrôle commun non vérifié : performance.complexity
- 1 critère(s) sans niveau de qualité justifié

### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 2 | Erreurs explicites de stockage et notifications ajoutées ; résultat CLI de projet toujours asynchrone. Le niveau supérieur exige une qualification plus complète. |
| Gestion des erreurs partielles | 2 | Échec de remplacement injecté et ancienne donnée conservée ; interruption réelle non simulée. Le niveau supérieur exige une qualification plus complète. |
| Ergonomie des parcours concernés | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 2 | Dépendances de modules et accès aux fichiers lus sur les chemins audités ; frontières internes non exhaustives. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des cycles | 2 | Graphe des cibles Swift lu ; aucune analyse complète des cycles internes. Le niveau supérieur exige une qualification plus complète. |
| Séparation construction et exécution | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Assemblages et dépendances dynamiques | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.architecture.03
- Contrôle non vérifié : axes.architecture.04
- Contrôle commun non vérifié : architecture.dependencies
- 2 critère(s) sans niveau de qualité justifié

### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 2 | Invariants et limites des corrections expliqués ; tous les invariants historiques ne sont pas relus. Le niveau supérieur exige une qualification plus complète. |
| Périmètre et maintenabilité du changement | 2 | Patch ciblé avec tests ; la maintenabilité globale reste partiellement examinée. Le niveau supérieur exige une qualification plus complète. |
| Revue contradictoire et responsabilité | 3 | Contre-audit et revues indépendantes documentés ; aucun essai macOS côté relecteurs. Le niveau supérieur exige une qualification plus complète. |

- Contrôle commun non vérifié : quality.llm

### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 2 | Une dépendance Swift directe verrouillée ; aucune preuve exhaustive d'absence de dépendances évitables. Le niveau supérieur exige une qualification plus complète. |
| Poids et ressources justifiés | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |
| Code mort et simplifications possibles | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.minimalism.02
- Contrôle non vérifié : axes.minimalism.03
- Contrôle commun non vérifié : quality.minimalism
- 2 critère(s) sans niveau de qualité justifié

### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 2 | Conservation des fichiers et lecture de workflows testées sur des données synthétiques ; usage réel non rejoué. Le niveau supérieur exige une qualification plus complète. |
| Cohérence et idempotence des versions | 2 | Installation, remplacement et suppression ordinaires testés ; idempotence générale non démontrée. Le niveau supérieur exige une qualification plus complète. |
| Conformité aux règles et données de référence | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.business.03
- Contrôle commun non vérifié : correctness.logic
- 1 critère(s) sans niveau de qualité justifié

### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 2 | Reproductions, corrections et tests reliés ; couverture des spécifications historiques incomplète. Le niveau supérieur exige une qualification plus complète. |
| Couverture des exigences obligatoires | Non vérifié | Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante. |

- Contrôle non vérifié : axes.traceability.02
- Contrôle commun non vérifié : spec.traceability
- 1 critère(s) sans niveau de qualité justifié


## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0, "candidates": 0, "suppressed": 0}

- [fixed] HIGH : Suppression hors du dossier des workflows
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:975 ; 3f97992ebae1926f57fd
  Les composants . et .. pouvaient viser le dossier des workflows ou son parent.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] HIGH : Perte de l'ancien workflow si le remplacement échoue
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StagedFileReplacement.swift:17 ; 5721844f49ae3b638a61
  L'ancien dossier était supprimé avant le déplacement ; l'échange prépare maintenant la copie et conserve l'ancienne en cas d'échec.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Mise à jour incomplète des tâches d'automatisation
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AlfredAutomationTasks.swift:62 ; 14982e1e8bde259a88c7
  La variante Tasks et LICENSE supprimait les éléments installés avant leur remplacement.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Arrêt sur un nombre de workflow hors plage
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AlfredWorkflow.swift:7 ; 49bf8e4666be13ab11c2
  Un réel plist de 1e100 provoquait une conversion fatale ; les valeurs hors plage sont refusées.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Arrêt sur un code de touche hors plage
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AlfredLiveEffects.swift:116 ; b3b59a4d83bc1d642626
  La conversion d'un entier supérieur à UInt16 arrêtait le processus ; le test remplace l'émetteur réel.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Arrêt sur une expression très imbriquée
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherCalculator.swift:127 ; e382d0eba769e38eed53
  Une expression de 50 000 parenthèses arrêtait le sous-processus ; la profondeur est bornée.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] LOW : Débordement des compteurs de classement
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherRanking.swift:62 ; 1c68b69e1c4d8b093062
  Un compteur Int.max pouvait provoquer un arrêt à l'incrément ou à la somme.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Ancre extrême rendant le classement non encodable
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherRanking.swift:77 ; d1a708dba11299bb2db5
  Une ancre finie extrême produisait une valeur infinie ; les scores et ancres restent finis.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Historique de saisie : écriture non transactionnelle
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherHistory.swift:18 ; 197a278f4d8d481d25bc
  Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Mémoire des déplacements : écriture non transactionnelle
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherMemory.swift:112 ; a00058d9c5a6f2bfb526
  Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Abréviations enregistrées : écriture non transactionnelle
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherAliases.swift:118 ; ef7cebf56e4758da03ee
  Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Classement du lanceur : écriture non transactionnelle
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LauncherRanking.swift:74 ; 16700b9eda3f46c6bb48
  Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.
- [fixed] MEDIUM : Projets de stages : écriture non transactionnelle
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageProjects.swift:19 ; 2a985ff83084ebfe4526
  Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.
  Action : Correction ciblée appliquée et vérifiée par les tests référencés.

## Vérification réalisée

- security.static : pass ; completed, 0 candidat(s).  Les quatre nouveaux fichiers ont été analysés séparément avec les mêmes règles figées.
- security.secrets : pass ; completed, 0 candidat(s). 
- security.history : pass ; completed, 0 candidat(s).  Historique limité à 5ab0ab9544de68edbd6642f58ac6140ef8a07f1e..5ed75b0532c4179c2b6b7d6a4a88e5e2ec2e92fd; les commits antérieurs sont hors périmètre.
- security.dependencies : pass ; completed, 0 candidat(s). 
- security.authorization : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- correctness.logic : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- correctness.concurrency : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- performance.complexity : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- tests.regression : pass ; Suite Swift séquentielle et tests de scripts exécutés sur la dernière révision ; trois suites Swift exclues pour les signaux et notifications système.
- architecture.dependencies : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- quality.minimalism : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- quality.llm : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- reliability.observability : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.
- spec.traceability : unknown ; Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.

## Limites

- contrôle non vérifié : security.authorization
- contrôle non vérifié : correctness.logic
- contrôle non vérifié : correctness.concurrency
- contrôle non vérifié : performance.complexity
- contrôle non vérifié : architecture.dependencies
- contrôle non vérifié : quality.minimalism
- contrôle non vérifié : quality.llm
- contrôle non vérifié : reliability.observability
- contrôle non vérifié : spec.traceability
- sous-contrôle d'axe non vérifié : axes.reliability.03
- sous-contrôle d'axe non vérifié : axes.reliability.04
- sous-contrôle d'axe non vérifié : axes.tests.04
- sous-contrôle d'axe non vérifié : axes.tests.05
- sous-contrôle d'axe non vérifié : axes.performance.01
- sous-contrôle d'axe non vérifié : axes.performance.02
- sous-contrôle d'axe non vérifié : axes.performance.04
- sous-contrôle d'axe non vérifié : axes.complexity.03
- sous-contrôle d'axe non vérifié : axes.quality.03
- sous-contrôle d'axe non vérifié : axes.architecture.03
- sous-contrôle d'axe non vérifié : axes.architecture.04
- sous-contrôle d'axe non vérifié : axes.minimalism.02
- sous-contrôle d'axe non vérifié : axes.minimalism.03
- sous-contrôle d'axe non vérifié : axes.business.03
- sous-contrôle d'axe non vérifié : axes.traceability.02

## Minimalisme et responsabilité future

Potentiel minimalisme : non mesuré pour tout le dépôt ; une suppression présumée a été annulée après échec de compilation.

Correctifs ciblés, reproductions et revues conservées ; l'ensemble des invariants du dépôt et la compréhension de l'auteur humain ne sont pas démontrés.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
