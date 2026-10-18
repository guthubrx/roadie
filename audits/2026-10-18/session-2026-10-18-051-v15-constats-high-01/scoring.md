# Audit Code V15

Périmètre : /private/tmp/roadie-audit-051
Sources : commit 38f69a6a799aa3a9767ca042715a7d436e804a4b ; mode readonly.
Décision : **inconclusive** ; note globale : N/A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 14/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 63/100 (D) | 63 | 4/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 50 | 1/1 | Évalué |
| Tests et validation | 56/100 (F) | 45 | 4/5 | Provisoire |
| Performance et ressources | 46/100 (F) | 38 | 3/4 | Provisoire |
| Complexité algorithmique | 63/100 (D) | 63 | 3/3 | Évalué |
| Qualité du code et des erreurs | 50/100 (F) | 25 | 1/2 | Provisoire |
| Architecture et dépendances | 63/100 (D) | 63 | 4/4 | Évalué |
| Responsabilité future et hygiène | 58/100 (F) | 58 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 58/100 (F) | 58 | 3/3 | Évalué |
| Traçabilité des exigences | 63/100 (D) | 63 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté, une seule règle Swift ; entrées relues à la main. Niveau 3 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Adaptateur gitleaks : 7,74 Mo analysés sans fuite. Niveau 4 : contrôle en CI à chaque commit. |
| Maîtrise des secrets historiques | 2 | Historique v0.4.0..38f69a6a (70 commits) sans fuite, décision utilisateur option A ; historique antérieur non analysé. Niveau 3 : historique complet sous budget. |
| Authentification et séparation des droits | Non applicable | Aucun mécanisme d'authentification ni de séparation des droits dans le diff. |
| Maîtrise des dépendances vulnérables | 3 | OSV exécuté sur Package.resolved : aucun avis ; dépendances inchangées. Niveau 4 : suivi continu. |

- outil non exécuté : gitleaks-history

### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucune fonction LLM dans le produit ni dans le diff. |
| Permissions des appels externes | Non applicable | Aucun appel LLM externe dans le produit ni dans le diff. |
| Résistance aux instructions malveillantes | Non applicable | Aucune entrée transmise à un modèle dans le produit ni dans le diff. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | Non applicable | Le diff ne touche ni sauvegardes ni rotation. |
| Reprise des traitements interrompus | 2 | B-01 : fichier illisible traité comme avant (aucune écriture) ; index AX invalidé par l'observateur. Chemins d'échec non testés. Niveau 3 : test sur fichier corrompu et index invalide. |
| Continuité pendant une bascule | Non applicable | Aucune bascule ni redondance dans le périmètre. |
| Restauration après sinistre | Non applicable | Aucune restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et tests sans erreur ; aucun avertissement dans le diff. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter dans le projet ; avertissements du compilateur hors diff. Niveau 3 : linter configuré. |
| Régressions et cas limites | 2 | B-01 et D-03 testés sur le vrai service ; A-02, A-05, C-05 en fonctions pures ; A-03, exclusion C-06, warp et cadres appliqués non testés. Niveau 3 : ces cas. |
| Qualification du runtime livré | Non vérifié | Runtime livré non qualifié par cet audit : installation et santé seulement rapportées ; redémarrage interdit. |
| Tests interface et intégration des données | 2 | RailPanel réel testé pour le dépliage ; pas de test d'intégration du pré-filtre de clic ni des captures repliées. Niveau 3 : test d'intégration du rail. |

- Contrôle non vérifié : axes.tests.04
- 1 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Aucune file ajoutée ; dépliage à 8 captures, budgets conservés. Pas de test de charge. Niveau 3 : mesure sous rafale. |
| Budget mémoire | 2 | Caches bornés (bundle par relevé, chemins de config, index par PID remplacé à chaque relevé). Pas de mesure mémoire. Niveau 3 : mesure. |
| Délais, annulation et libération | 2 | Minuterie A-05 reprogrammée à chaud ; aucune attente nouvelle ; B-01 ne prend plus le verrou sans changement (test). Niveau 3 : test de reprogrammation. |
| Mesures représentatives de latence et charge | Non vérifié | Aucune mesure avant/après publiée par la 051 (T007 ouverte, F3) ; non rejouée ici. |

- Contrôle non vérifié : axes.performance.04
- 1 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée ajoutés O(1), O(k), O(w) analysés et annotés. Niveau 4 : mesure à n élevé. |
| Bornes des parcours et allocations | 3 | Parcours bornés par les fenêtres d'une application ou des écrans actifs. Niveau 4 : borne vérifiée par test. |
| Coût des accès et écritures de données | 2 | kAXWindows, LaunchServices, verrou d'état et relevé de commande réduits ; un relevé complet par clic subsiste en mode run (F1). Niveau 3 : F1 traité et mesuré. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | Non applicable | Le diff ne modifie aucun refus ni message utilisateur. |
| Gestion des erreurs partielles | 2 | B-01 réconcilie à nouveau si l'état a bougé ; index non couvrant -> énumération. Erreurs partielles non testées. Niveau 3 : tests. |
| Ergonomie des parcours concernés | Non vérifié | Parcours visibles (glisser, rail replié, focus-souris) non observés : pas d'accès au bureau. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Frontières respectées : caches dans leurs modules, aucun import nouveau entre modules. Niveau 4 : règle vérifiée par outil. |
| Maîtrise des cycles | 2 | Aucun cycle introduit d'après la lecture ; pas d'outil de graphe Swift. Niveau 3 : graphe vérifié. |
| Séparation construction et exécution | 3 | Aucun changement de composition ; état replié exposé par accesseur, rappel onRevealed posé au rendu. Niveau 4 : test de composition. |
| Assemblages et dépendances dynamiques | 2 | Interaction non vue entre le pré-filtre du rail et la session de geste du même processus (F1). Niveau 3 : test du mode run. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 2 | Décisions et limites écrites (research.md, validation.md) ; l'effet de C-05 en mode run n'est pas expliqué. Niveau 3 : invariant de bout en bout écrit. |
| Périmètre et maintenabilité du changement | 3 | Huit interventions ciblées, réversibles une par une, aucun fichier hors périmètre. Niveau 4 : réversibilité testée. |
| Revue contradictoire et responsabilité | 2 | Revue externe (Claude Haiku) documentée avec objections ; revue indépendante finale et audit (T007) non faits ; cet audit n'est pas indépendant. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. Niveau 4 : inventaire mesuré. |
| Poids et ressources justifiés | 2 | Réductions par construction, gain non mesuré (F3). Niveau 3 : mesure publiée. |
| Code mort et simplifications possibles | 3 | Environ 2 lignes répétées, aucun code mort ajouté. Niveau 4 : outil de code mort Swift. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 2 | Relevé fidèle : index réutilisé seulement s'il couvre ; limite des processus lecteurs autonomes documentée. Niveau 3 : observation runtime. |
| Cohérence et idempotence des versions | 3 | B-01 : écriture unique, résultat réutilisé seulement si l'état persistant est identique. Niveau 4 : test de propriété. |
| Conformité aux règles et données de référence | 2 | R5 contredite en mode run ; critère de mesure absent ; autres exigences conformes. Niveau 3 : F1 et F3 traités. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Chaque constat relie cause, sources, exigence et correction ; variantes conservées. Niveau 4 : reproduction exécutée. |
| Couverture des exigences obligatoires | 2 | Neuf exigences et le critère vérifiés ; R5 contredite, mesure absente. Niveau 3 : toutes satisfaites ou réécrites. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 1, "low": 2, "info": 0, "total": 3, "candidates": 0, "suppressed": 0}

- [confirmed] MEDIUM : R5 contredite en mode run : la session de geste fait un relevé complet à chaque clic gauche
  /private/tmp/roadie-audit-051/Sources/roadied/main.swift:429 ; 355e359e3f314c2619f0
  Chaque leftMouseDown appelle la cible de geste du tiler, qui lit sharedSnapshot() (règle des 150 ms, sans réutilisation silencieuse) : au repos, un relevé AX complet a lieu sur le fil principal avant tout test de barre de titre, plus une ligne events.jsonl. Le rail et la session de geste partagent la même publication : le pré-filtre C-05 ne retire aucun relevé par clic dans le mode par défaut.
  Action : Décision de conception : cible de geste via readerSnapshot (génération d'observation) ou pré-filtre sur les cadres gérés, puis mesure ; sinon réécrire R5 et validation.md.
- [confirmed] LOW : Variante : le menu de barre de titre relève à chaque clic droit quand il est activé
  /private/tmp/roadie-audit-051/Sources/RoadieDaemon/TitlebarContextMenuController.swift:212 ; d883fcfafcd382d1e3cc
  handleRightMouseDown appelle snapshotService.snapshot(), qui relève toujours, avant le test de barre de titre. Option expérimentale désactivée par défaut ; antérieur à la 051.
  Action : Tester la bande de titre sur un relevé partagé et relever seulement si le point est éligible.
- [confirmed] LOW : Critère de réussite non rempli : aucune mesure avant/après publiée
  /private/tmp/roadie-audit-051/specs/051-constats-high/tasks.md:9 ; d9e859065f43542d8c9e
  La spec exige une mesure au repos avec mesure-repos.py et des résultats publiés ; T007 n'est pas cochée et le commit ne contient aucun fichier mesures/. Sans mesure, les gains restent des hypothèses (constitution XXII).
  Action : Mesurer au repos dans les conditions de la 048 et publier avant/après, ou retirer le critère de la spec.

## Vérification réalisée

- security.static : pass ; Semgrep : 163 règles figées sur les 18 fichiers sélectionnés, 0 résultat, 0 erreur. Une seule règle Swift : l'analyse manuelle porte le contrôle (notes/axes.md).
- security.secrets : pass ; Adaptateur gitleaks : ~7,74 Mo analysés, aucune fuite ; audits/ exclu par la configuration figée.
- security.history : pass ; Décision utilisateur du 18/10/2026 (option A) : l'historique complet dépasse le plafond de 300 s ; plage analysée v0.4.0 (5ab0ab95)..38f69a6a, 70 commits, ~3,03 Mo, aucune fuite (gitleaks 8.30.1, --redact). Exécuté en --tool custom : le runner refuse --command avec --tool gitleaks-history. Limite connue : historique antérieur à v0.4.0 non analysé dans cette session.
- security.dependencies : pass ; OSV-Scanner (adaptateur) : Package.resolved, 1 paquet, aucun avis ; manifestes inchangés depuis la base.
- security.authorization : pass ; Aucune authentification, autorisation ni frontière de confiance modifiée : caches internes, minuteries et pré-filtre de clic.
- correctness.logic : pass ; Invariants 1-7 vérifiés ; B-01 garde une seule écriture et les événements ; D-03 applique l'arbre relu. F1 (R5 contredite en mode run) et F3 (mesure absente) ouverts.
- correctness.concurrency : pass ; B-01 : lecture sans verrou sur écriture atomique, transaction flock avec comparaison d'état ; caches sous verrou ; reprogrammation A-05 sur MainActor ; course résiduelle décrite et non retenue.
- performance.complexity : pass ; Fonctions ajoutées O(1), O(k), O(w), bornées et annotées ; aucune boucle imbriquée ni N+1 ; relevé par clic restant (F1) ; aucune mesure publiée (F3).
- tests.regression : pass ; swift build --build-tests puis swift test : 1 731 tests / 205 suites verts, dont Spec051* et les tests D-03 ; les deux tests instables connus ont réussi. Manques listés dans notes/axes.md.
- architecture.dependencies : pass ; Aucune dépendance de module ajoutée ; accesseurs RailPanel ; pas de cycle (lecture des imports).
- quality.minimalism : pass ; Checklist exécutée : ~2 lignes répétées dans handleMouseDownOutsideTitleBands ; aucune dépendance ni abstraction prématurée ; aucun changement hors périmètre.
- quality.llm : pass ; Changements petits et réversibles, revue externe documentée ; R5 annoncée sans réserve (F1), mesure absente (F3) ; audit non indépendant.
- reliability.observability : pass ; Aucun journal ajouté ; aucune file ni retry sans borne ; journal window_gesture_target écrit à chaque clic (préexistant, F1).
- spec.traceability : pass ; R1 à R9 et le critère de mesure vérifiés un à un : R5 contredite en mode run (F1), mesure absente (F3), autres exigences implémentées.

## Limites

- outil non exécuté : gitleaks-history
- sous-contrôle d'axe non vérifié : axes.tests.04
- sous-contrôle d'axe non vérifié : axes.performance.04
- sous-contrôle d'axe non vérifié : axes.quality.03

## Minimalisme et responsabilité future

Potentiel minimalisme : ~2 lignes suppressibles à comportement constant (preview.hide() et pending = nil répétés dans handleMouseDownOutsideTitleBands, gardés pour la lisibilité) ; méthode : relecture ligne à ligne du diff source, tests exclus ; aucune dépendance, abstraction ou état dérivé superflu.

Vertus LLM et responsabilité future : charge cognitive faible (huit interventions ciblées, commentées par identifiant, réversibles) ; volume justifié mais gain non mesuré (F3) ; l'interaction du pré-filtre C-05 avec la session de geste du même processus n'a pas été vue (F1) ; revue externe documentée, revue finale et audit T007 non faits ; cet audit n'est pas indépendant.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
