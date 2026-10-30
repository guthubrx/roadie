# Audit Code V15

Périmètre : /private/tmp/roadie-audit-131
Sources : commit 740a0f78fb6615b931e9dd60463d4dc5f8c3cccd ; mode fix.
Décision : **pass** ; note globale : A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 14/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 65/100 (D) | 65 | 5/5 | Évalué |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 50 | 1/1 | Évalué |
| Tests et validation | 60/100 (D) | 60 | 5/5 | Évalué |
| Performance et ressources | 56/100 (F) | 56 | 4/4 | Évalué |
| Complexité algorithmique | 67/100 (D) | 67 | 3/3 | Évalué |
| Qualité du code et des erreurs | 58/100 (F) | 58 | 3/3 | Évalué |
| Architecture et dépendances | 63/100 (D) | 63 | 2/2 | Évalué |
| Responsabilité future et hygiène | 58/100 (F) | 58 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 58/100 (F) | 58 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 3 | Semgrep sans signal, SwiftLint sur les sources changées (2 signaux nouveaux, protégés), diff lu en entier. Le niveau supérieur exige une qualification plus complète. |
| Protection des secrets courants | 2 | Gitleaks sans signal sur les fichiers figés. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des secrets historiques | 3 | Historique de la session (depuis a9c627fc) sans signal. Le niveau supérieur exige une qualification plus complète. |
| Authentification et séparation des droits | 3 | Actions locales sur verbe explicite, sans shell, arguments séparés, application ciblée mémorisée. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des dépendances vulnérables | 2 | Aucune dépendance ajoutée ; OSV sans avis. Le niveau supérieur exige une qualification plus complète. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucun appel à un service LLM ajouté (IA d'Alfred 6 écartée). |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM ajouté (IA d'Alfred 6 écartée). |
| Résistance aux instructions malveillantes | Non applicable | Aucun appel à un service LLM ajouté (IA d'Alfred 6 écartée). |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | Non applicable | Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée. |
| Reprise des traitements interrompus | 2 | Tâches téléchargées une fois par processus ; échecs notifiés ; reprise après échec non testée en réel. Le niveau supérieur exige une qualification plus complète. |
| Continuité pendant une bascule | Non applicable | Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée. |
| Restauration après sinistre | Non applicable | Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Sources et tests compilés au commit audité. Le niveau supérieur exige une qualification plus complète. |
| Analyse de style et erreurs statiques | 2 | Semgrep et SwiftLint ciblés ; règles Swift limitées. Le niveau supérieur exige une qualification plus complète. |
| Régressions et cas limites | 3 | Tests de chaque exigence, dont mise en page réelle des tableaux et données réelles de macOS ; suite complète réussie. Le niveau supérieur exige une qualification plus complète. |
| Qualification du runtime livré | 2 | Runtime livré installé et signé, santé 5/5 ; parcours réels de l'utilisateur sur ce runtime (C1 à C4 trouvés et corrigés). Le niveau supérieur exige une qualification plus complète. |
| Tests interface et intégration des données | 2 | Rendus hors écran regardés (grille, tableau) ; parcours graphiques réels non rejoués. Le niveau supérieur exige une qualification plus complète. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Menus lus une fois par ouverture, raccourcis Apple gardés 10 minutes ; pas d'essai de charge. Le niveau supérieur exige une qualification plus complète. |
| Budget mémoire | 2 | Catalogue SF Symbols mesuré (environ 5 Mio, chargé à l'ouverture du navigateur) ; roadied 246 Mio sans référence antérieure. Le niveau supérieur exige une qualification plus complète. |
| Délais, annulation et libération | 3 | Lectures AX bornées (0,25 s par appel, 0,8 s au total), osascript borné, empreinte hors du fil principal. Le niveau supérieur exige une qualification plus complète. |
| Mesures représentatives de latence et charge | 2 | Dictionnaire mesuré ; durée des menus seulement journalisée. Le niveau supérieur exige une qualification plus complète. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Complexités annotées sur chaque fonction publique ajoutée. Le niveau supérieur exige une qualification plus complète. |
| Bornes des parcours et allocations | 3 | Parcours bornés (menus, symboles 600 résultats, taille de dossier 50 000 éléments). Le niveau supérieur exige une qualification plus complète. |
| Coût des accès et écritures de données | 2 | Catalogue SF Symbols lu une fois ; empreinte par blocs ; coût du très gros fichier non borné en durée. Le niveau supérieur exige une qualification plus complète. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Refus explicites (destination, homonyme, numéro inconnu) et notifications d'échec. Le niveau supérieur exige une qualification plus complète. |
| Gestion des erreurs partielles | 2 | Bilan par source pour les lots ; « en remplaçant » met l'ancien à la corbeille avant l'écriture. Le niveau supérieur exige une qualification plus complète. |
| Ergonomie des parcours concernés | 2 | Parcours réels essayés par l'utilisateur (29-30 octobre) : quatre défauts trouvés (C1 à C4), corrigés après le commit audité et confirmés ; fiche Informations remplacée par la fenêtre du Finder. Le niveau supérieur exige une qualification plus complète. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Logique pure dans des fichiers dédiés, contrôleur réduit à l'aiguillage. Le niveau supérieur exige une qualification plus complète. |
| Maîtrise des cycles | Non applicable | Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée. |
| Séparation construction et exécution | Non applicable | Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée. |
| Assemblages et dépendances dynamiques | 2 | Données SF Symbols et dictionnaire de macOS lus au besoin, repli vide si absents. Le niveau supérieur exige une qualification plus complète. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Invariants, preuves et limites écrits (research, analyse, validation). Le niveau supérieur exige une qualification plus complète. |
| Périmètre et maintenabilité du changement | 3 | Changements par lot, commits par lot, tests par exigence. Le niveau supérieur exige une qualification plus complète. |
| Revue contradictoire et responsabilité | 1 | Pas de revue indépendante : délégation Bridget indisponible. Le niveau supérieur exige une qualification plus complète. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. Le niveau supérieur exige une qualification plus complète. |
| Poids et ressources justifiés | 2 | Binaire +2,4 % (+506 112 octets) contre la 0.11.1 publiée ; aucune dépendance ajoutée. Le niveau supérieur exige une qualification plus complète. |
| Code mort et simplifications possibles | 3 | ~3 lignes suppressibles relevées sur tout le diff. Le niveau supérieur exige une qualification plus complète. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Données de macOS lues telles quelles (symboles, catégories, versions), testées sur ce Mac. Le niveau supérieur exige une qualification plus complète. |
| Cohérence et idempotence des versions | 2 | Clés ajoutées facultatives, défauts identiques à l'existant, valeur inconnue ramenée au défaut ; fichier d'épinglage absent = vide. Le niveau supérieur exige une qualification plus complète. |
| Conformité aux règles et données de référence | 2 | Format d'Alfred : numéros prouvés ou déduits et documentés. Le niveau supérieur exige une qualification plus complète. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Défauts trouvés reliés à leur preuve et à leur correction ; exigences reliées aux tests. Le niveau supérieur exige une qualification plus complète. |
| Couverture des exigences obligatoires | 3 | Toutes les exigences obligatoires de la spec 131 vérifiées, sauf SC-003 mesuré à l'essai. Le niveau supérieur exige une qualification plus complète. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0, "candidates": 0, "suppressed": 0}

- [fixed] HIGH : Vue Texte sans champ de saisie : exception de mise en page puis plantage
  /private/tmp/roadie-audit-131/Sources/RoadieDaemon/WorkflowTextPanel.swift:117 ; f3311562a0179592e435
  La largeur du champ de saisie est contrainte même quand il n'est pas dans la pile ; l'exception AppKit traverse Swift et corrompt l'état d'exécution (plantage à la minuterie suivante, 4 essais sur 4).
  Action : Ne contraindre que les lignes présentes dans la pile.
- [fixed] MEDIUM : Barre sans défilement au trackpad
  /private/tmp/roadie-audit-131/Sources/RoadieDaemon/TargetOverlayPresenter.swift:861 ; c4d49d69300fbddb4200
  Le tap de la barre n'écoute pas scrollWheel : la liste et la grille apps ne défilent pas.
  Action : Écouter la molette en recherche et déplacer la sélection.
- [fixed] LOW : Champ de recherche SF Symbols : loupe sur le texte
  /private/tmp/roadie-audit-131/Sources/RoadieDaemon/WorkflowTextPanel.swift:376 ; 277d137ef179cef5a672
  Le style retire le cadre natif, qui réserve la place de la loupe d'un NSSearchField ; reproduit hors écran.
  Action : Garder le cadre natif des champs de recherche.
- [fixed] LOW : Créer un alias sans retour visible
  /private/tmp/roadie-audit-131/Sources/RoadieDaemon/TargetModeRuntimeController.swift:1973 ; f847454a4c3e5593458e
  L'alias est créé sur disque mais rien ne le montre à l'utilisateur.
  Action : Montrer les alias créés sélectionnés dans le Finder.

## Vérification réalisée

- security.static : pass ; completed, 0 candidat(s). 
- security.secrets : pass ; completed, 0 candidat(s). 
- security.history : pass ; completed, 0 candidat(s).  Historique limité à a9c627fc4ace91da82dfb4436e2c4629a3d847c9..740a0f78fb6615b931e9dd60463d4dc5f8c3cccd; les commits antérieurs sont hors périmètre.
- security.dependencies : pass ; completed, 0 candidat(s). 
- security.authorization : pass ; Diff lu : aucune nouvelle entrée ; écritures de fichiers sur verbe explicite, corbeille seule suppression, menus de l'application mémorisée seulement.
- correctness.logic : pass ; Diff et appelants lus ; tables d'Alfred prouvées ou déduites et documentées ; numéro inconnu refusé ; convergence FR-003 ajoutée et testée.
- correctness.concurrency : pass ; États partagés ajoutés sous verrou ou sur le fil principal ; boîte Sendable justifiée ; session de barre neuve à chaque ouverture.
- performance.complexity : pass ; Recherches O(n) sur listes préparées, menus bornés, dictionnaire mesuré (92 ms à froid, 10 ms ensuite).
- tests.regression : pass ; Suite complète 2 318 tests / 343 suites et 28 tests de scripts au commit audité.
- architecture.dependencies : pass ; Aucune dépendance ajoutée ; six fichiers pour des responsabilités distinctes ; réutilisations listées.
- quality.minimalism : pass ; Checklist exécutée sur le diff : ~3 lignes suppressibles ; réutilisations préférées aux créations.
- quality.llm : pass ; Diff relu, invariants et limites écrits ; pas de revue indépendante (Bridget indisponible).
- reliability.observability : pass ; Événements ajoutés sans saisie ni chemin (nombres, durées, verbe) ; échecs de verbes notifiés.
- spec.traceability : pass ; FR-001 à FR-016 reliées au code et aux tests (Converge) ; SC-003 non mesuré, journalisé.

## Limites

Aucune limite déclarée pour les contrôles définis. Cela ne prouve pas l'absence de tout défaut.

## Minimalisme et responsabilité future

Potentiel minimalisme : ~3 lignes suppressibles à comportement constant (conformités CaseIterable réservées aux tests), mesuré sur tout le diff.

Diff relu en entier ; logique pure séparée et testée ; deux défauts trouvés et corrigés avant figement, quatre autres à l'essai réel puis corrigés ; pas de revue indépendante.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
