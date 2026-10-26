# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie
Sources : commit 01789d19cb76ee42626f818fc3dc8f1d8611000e ; mode fix.
Décision : **pass** ; note globale : A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 14/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 60/100 (D) | 60 | 5/5 | Évalué |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 63/100 (D) | 63 | 2/2 | Évalué |
| Tests et validation | 65/100 (D) | 65 | 5/5 | Évalué |
| Performance et ressources | 50/100 (F) | 50 | 4/4 | Évalué |
| Complexité algorithmique | 67/100 (D) | 67 | 3/3 | Évalué |
| Qualité du code et des erreurs | 67/100 (D) | 67 | 3/3 | Évalué |
| Architecture et dépendances | 69/100 (D) | 69 | 4/4 | Évalué |
| Responsabilité future et hygiène | 50/100 (F) | 50 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 75/100 (C) | 75 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep (peu de règles Swift) ; échappements de {query}, AppleScript et requêtes Spotlight relus. Niveau 3 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Gitleaks fichiers sans fuite. Niveau 4 : contrôle en CI à chaque commit. |
| Maîtrise des secrets historiques | 2 | Historique borné depuis 50e36a43. Niveau 3 : historique complet analysé. |
| Authentification et séparation des droits | 2 | Pas d'authentification ; frontière : code tiers des workflows avec les droits du démon (F2, mesuré), lu seulement depuis les dossiers de l'utilisateur. Niveau 3 : isolement des scripts (droits retirés). |
| Maîtrise des dépendances vulnérables | 3 | OSV exécuté depuis le checkout principal : 0 avis ; aucune dépendance ajoutée. Niveau 4 : surveillance continue. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucune fonction LLM dans le produit ni dans le diff. |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM. |
| Résistance aux instructions malveillantes | Non applicable | Aucune entrée traitée par un LLM. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Configuration de l'utilisateur non modifiée par la session ; tâches remplacées par commande explicite avec la licence ; pas de rotation. Niveau 3 : sauvegarde automatique avant remplacement. |
| Reprise des traitements interrompus | 3 | Scripts arrêtés à la frappe, au délai (10 s) et au plafond (5 Mo), groupe complet (test) ; un lot continue après un échec. Niveau 4 : reprise mesurée en charge. |
| Continuité pendant une bascule | Non applicable | Pas de bascule de service dans le périmètre. |
| Restauration après sinistre | Non applicable | Pas de restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et des tests sans erreur. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter Swift configuré ; avertissements du compilateur traités. Niveau 3 : linter configuré. |
| Régressions et cas limites | 3 | 2 086 tests ; 10 000 saisies aléatoires du calcul, corpus réel, cas limites (échappement, branches, signaux). Niveau 4 : mutation. |
| Qualification du runtime livré | 3 | Installation signée et santé 5/5 à chaque session ; essais réels par CLI (workflow list/check/trigger, R8). Niveau 4 : essai clavier enregistré. |
| Tests interface et intégration des données | 2 | Données réelles (workflows de l'utilisateur et corpus) ; parcours clavier non simulés. Niveau 3 : tests d'interface. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Un script par entrée à la fois, frappes regroupées 100 ms ; lecture de dossier en fond. Niveau 3 : mesure de charge. |
| Budget mémoire | 2 | Sorties plafonnées à 5 Mo, 200 éléments de dossier ; réponses gardées pour la barre ouverte seulement. Niveau 3 : mesure mémoire. |
| Délais, annulation et libération | 3 | Délais (10 s scripts, 30 s Raccourcis, 600 s dialogue) et annulations ; nettoyage à la fin de la barre. |
| Mesures représentatives de latence et charge | 1 | Latence par frappe (critère 50 ms de la 087) non mesurée. Niveau 2 : mesure représentative. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée annotés O(…) (calcul O(n), chemin O(e), mot-clé O(k), schéma O(o + c)). |
| Bornes des parcours et allocations | 3 | Bornes écrites et testées (5 000, 200, 200 étapes, 5 Mo, 20 saisies). |
| Coût des accès et écritures de données | 2 | Historique réécrit à chaque action (20 entrées) ; index relu par date de modification. Niveau 3 : écriture différée mesurée. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Messages clairs : interpréteur absent, brique non prise en charge, tâche absente avec la commande à lancer. Niveau 4 : messages essayés par l'utilisateur. |
| Gestion des erreurs partielles | 3 | Lot : « N sur M », un échec n'arrête pas la suite ; schéma arrêté proprement sur une brique manquante. |
| Ergonomie des parcours concernés | 2 | ⌥ + flèches et Maj + chiffre réaffectés (choix écrits) ; parcours clavier à essayer. Niveau 3 : parcours validés. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Types purs séparés, effets injectés (AlfredEffects) ; aucune dépendance ajoutée. |
| Maîtrise des cycles | 3 | Aucun cycle de module ajouté. |
| Séparation construction et exécution | 2 | Présentateur (+530 lignes) et contrôleur (+296) grossissent encore. Niveau 3 : services dédiés. |
| Assemblages et dépendances dynamiques | 3 | Assemblage par fermetures du contexte de barre ; aucun chargement dynamique de code Roadie. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Invariants et compromis écrits (research.md, commentaires, validation.md). |
| Périmètre et maintenabilité du changement | 2 | Cinq sessions en une passe, diff large (3 559 lignes) ; découpage par session, tests et convergence. Niveau 3 : diff réduit par livraison relue. |
| Revue contradictoire et responsabilité | 1 | Aucune revue contradictoire : Bridget a refusé trois admissions. Niveau 2 : revue indépendante documentée. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. |
| Poids et ressources justifiés | 2 | Un processus par frappe utile dans un mot-clé (borné, annulé) ; coût non mesuré. Niveau 3 : coût mesuré. |
| Code mort et simplifications possibles | 3 | Pas de code mort identifié. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Format d'Alfred relevé sur 101 workflows réels (types, échappement, branches, conditions). |
| Cohérence et idempotence des versions | 3 | Nouvelle stage créée une fois par lot ; annulation groupée idempotente ; historique sans doublon. |
| Conformité aux règles et données de référence | 3 | Règles de la référence Alfred et de la CJUE (format libre) respectées ; aucun workflow tiers livré. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats reliés aux corrections et preuves. |
| Couverture des exigences obligatoires | 3 | Exigences 087 à 091 couvertes ou limites écrites dans validation.md. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 1, "total": 1, "candidates": 0, "suppressed": 0}

- [fixed] MEDIUM : Copie simulée de la sélection : presse-papiers non texte perdu
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetModeRuntimeController.swift:1 ; 9f9fb739461977263910
  Seul le texte était gardé puis remis après clearContents ; une image ou des fichiers copiés étaient perdus.
  Action : PasteboardSnapshot garde et remet toutes les représentations.
- [confirmed] INFO : Un script de workflow obtient l'autorisation Accessibilité du démon
  /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AlfredScriptRunner.swift:1 ; 0dc59bb564fc2a0bb91b
  Mesure R8 : AXIsProcessTrusted() vrai pour un script lancé par roadied, faux depuis le Terminal ; même situation que dans Alfred.
  Action : Atténuations en place : workflows installés par l'utilisateur seulement, réglages workflows_enabled et alfred_workflows, avertissement.

## Vérification réalisée

- security.static : pass ; Semgrep sur les fichiers sélectionnés, 0 résultat.
- security.secrets : pass ; Gitleaks fichiers, 0 fuite.
- security.history : pass ; Historique 50e36a43..HEAD, 0 fuite.
- security.dependencies : pass ; OSV depuis le checkout principal, 0 avis.
- security.authorization : pass ; Aucune authentification ni réseau entrant ; scripts tiers lancés seulement depuis des workflows installés par l'utilisateur ; autorisation Accessibilité héritée mesurée et documentée (F2) ; dossier d'Alfred jamais écrit.
- correctness.logic : pass ; Calcul, chemins, mots-clés, Script Filter, schéma (flèches, modificateurs, branches), web, lot : 63 tests neufs et corpus de 102 workflows ; F1 corrigé et testé.
- correctness.concurrency : pass ; Scripts hors fil principal, réponses périmées ignorées par saisie demandée, annulation par groupe de processus (test), lecture de dossier par génération, verrou de l'index.
- performance.complexity : pass ; Points d'entrée annotés O(…) ; bornes : 5 000 éléments lus, 200 gardés, 200 étapes de schéma, 5 Mo de sortie, 10 s ; latence de la barre non mesurée (limite).
- tests.regression : pass ; Suite complète par l'exécuteur : 2 086 tests / 292 suites réussis à la révision 1 ; test de régression F1.
- architecture.dependencies : pass ; Aucune dépendance ajoutée ; outils système seulement (posix_spawn, mdfind, curl, ditto, osascript) ; types purs séparés, effets injectés.
- quality.minimalism : pass ; Potentiel minimalisme : ~0 ligne suppressible identifiée ; volume justifié par cinq demandes ; vigilance sur la taille du présentateur et du contrôleur.
- quality.llm : pass ; Invariants écrits dans research.md et validation.md ; défauts trouvés par mesure et corrigés ; revue indépendante refusée par Bridget (limite écrite).
- reliability.observability : pass ; Événements launcher.workflow_filter, launcher.workflow.run, launcher.batch, launcher.url, launcher.undo sans saisie ni sortie (relu dans le journal réel).
- spec.traceability : pass ; Spécifications 087 à 091 reliées aux tâches, tests et validations ; écarts de convergence ajoutés puis traités.

## Limites

Aucune limite déclarée pour les contrôles définis. Cela ne prouve pas l'absence de tout défaut.

## Minimalisme et responsabilité future

Potentiel minimalisme : ~0 ligne suppressible à comportement constant identifiée ; vigilance sur la taille de TargetOverlayPresenter et TargetModeRuntimeController.

Vertus LLM et responsabilité future : charge cognitive en hausse (deux gros fichiers), compensée par des types purs testés, des effets injectés et des mesures réelles (corpus, R8) ; volume justifié par cinq demandes ; revue indépendante absente (Bridget refusé).

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
