# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability
Sources : commit edd99a41b228ad35f41079dddc5860401a6c1441 ; mode fix.
Décision : **pass** ; note globale : A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 13/13.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 70/100 (C) | 70 | 5/5 | Évalué |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 63/100 (D) | 63 | 4/4 | Évalué |
| Tests et validation | 70/100 (C) | 70 | 5/5 | Évalué |
| Performance et ressources | 63/100 (D) | 63 | 4/4 | Évalué |
| Complexité algorithmique | 75/100 (C) | 75 | 3/3 | Évalué |
| Qualité du code et des erreurs | 75/100 (C) | 75 | 3/3 | Évalué |
| Architecture et dépendances | 75/100 (C) | 75 | 4/4 | Évalué |
| Responsabilité future et hygiène | 67/100 (D) | 67 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 75/100 (C) | 75 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 3 | Qualification locale de titre et types CG ; compilateur et Semgrep figé limités sur Swift ; pas de preuve inter-fichiers automatique. |
| Protection des secrets courants | 3 | Scan de fichiers exigé sur copie SHA hors du worktree ignoré ; aucune valeur secrète ajoutée dans les sources examinées. Copie SHA scannée sans candidat. |
| Maîtrise des secrets historiques | 2 | Historique examiné seulement après v0.4.0, borne explicitement conservée ; ne qualifie pas les commits antérieurs. |
| Authentification et séparation des droits | 3 | Autorité locale AX déjà accordée ; pas de nouveau droit, SIP, injection ou compte ; fenêtres ciblées par identité stricte. |
| Maîtrise des dépendances vulnérables | 3 | Une seule dépendance Swift verrouillée et inchangée ; OSV explicite du verrou terminé sans candidat. Pas de graphe atteignable complet. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucun modèle ni prompt ni réponse LLM dans le produit modifié. |
| Permissions des appels externes | Non applicable | Aucun modèle ni prompt ni réponse LLM dans le produit modifié. |
| Résistance aux instructions malveillantes | Non applicable | Aucun modèle ni prompt ni réponse LLM dans le produit modifié. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Archive de rollback et quatre empreintes vérifiées ; politique de rotation générale inchangée, pas de qualification exhaustive de rétention. |
| Reprise des traitements interrompus | 3 | Permis révoqués, génération externe prioritaire, restauration/annulation testées ; aucun rejeu persistant du geste. |
| Continuité pendant une bascule | 3 | Configuration inchangée, fin native marquée séparée du vrai up ; démarrage chargé et nouveau restart vérifiés avec santé5/5. |
| Restauration après sinistre | 2 | Archives précédentes et état sauvegardés ; restauration complète après sinistre non exercée sur le poste utilisateur. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilateur Swift6 et vérification Sendable sur les sources/tests, compilation et tests natifs ; quelques avertissements hérités conservés. |
| Analyse de style et erreurs statiques | 2 | Compilation, diff sans espace invalide et règles Semgrep ; pas de linter Swift de style dédié dans le projet. |
| Régressions et cas limites | 3 | Tests ciblés red/green et scénarios temporels, cellules hors main et contrôles matériels injectés ; suite finale2420tests réussie. |
| Qualification du runtime livré | 3 | Build signé chargé, UUID/PID et santé5/5 ; usage réel et limites doivent rester distingués des tests. |
| Tests interface et intégration des données | 3 | Deux sens, annulation/dépôt AppKit/Chrome et nouveau restart ; bouton fermer fenêtre non rejoué, toutes les apps non certifiées. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 3 | Un lot actif et une cible en attente par PID ; dernière cible seulement, délai borné et autres applications indépendantes. |
| Budget mémoire | 2 | État linéaire par fenêtre/PID et une tâche de qualification remplacée ; pas de nouvelle mesure de tas/mémoire privée145. |
| Délais, annulation et libération | 3 | Annulation au clic, fin/désactivation et notifications contexte ; tests slowAX et timer libéré ; appel AX engagé non interrompu de force. |
| Mesures représentatives de latence et charge | 2 | Huit parcours natifs stables, sans benchmark CPU/GPU ni latence physique isolée du piloteBTT. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Moteur O(k), dispatcher O(k+p), tap mouvements O(1) et clic O(w) mémoire ; le BSP quadratique hérité est nommé séparément. |
| Bornes des parcours et allocations | 3 | Clés d’animation limitées aux surfaces actives, états retirés, une dernière cible/PID et tâches de qualification remplacées. |
| Coût des accès et écritures de données | 3 | Pas de capture supplémentaire, aucune I/O dans le tap ; lecteurs/config/stages existants conservés hors callback. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Vrai contenu entre les deux écrans observés, annulation et maintien logique ; autres applications et contrôles non certifiés ; diagnostics sans contenu. |
| Gestion des erreurs partielles | 3 | Deferred distinct de résultat final, refus/budgets respectés, échec de persistance explicite ; aucune réussite inventée à la planification. |
| Ergonomie des parcours concernés | 3 | Même geste et même réglage real, aucune UI ni option supplémentaire ; pas d’étude d’ergonomie. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Core calcul pur, AX qualification/writer, daemon coordination/UI ; pas de dépendance inversée ajoutée. |
| Maîtrise des cycles | 3 | Imports du manifeste lus, aucune dépendance/package ajoutée ; absence de graphe automatique Swift explicitée. |
| Séparation construction et exécution | 3 | Installer signé réutilisé, code chargé vérifié par UUID et certificat ; callbacks et données persistées restent dans leurs propriétaires. |
| Assemblages et dépendances dynamiques | 3 | Identités/générations et services existants réutilisés ; chargements natifs vérifiés, pas de plugin générique ou d’injection dynamique nouvelle. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Spec/plan/reuse-audit et analysis expliquent fin native, séquence, annulation et masquage ; preuve de reflow réelle jointe. |
| Périmètre et maintenabilité du changement | 3 | Pas de nouveau moteur ; propriété du pointeur explicite et état verrouillé dans le service existant. |
| Revue contradictoire et responsabilité | 2 | Auto-relecture et protocole local réalisés ; revue indépendante demandée mais admission refusée, sans second avis inventé. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée ; dispatcher, store, UI de paramètres et fixture existants étendus. |
| Poids et ressources justifiés | 3 | Bail sur minuteur existant, pas de capture produit supplémentaire ; deux appels de fin clairement séparés. |
| Code mort et simplifications possibles | 2 | Ancien releasePoint et garde display retirés ; diagnostics utiles conservés. Pas de mesure exhaustive de code mort Swift. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Cadres réels CG/AX, aucune photo étirée ; données de configuration validées et appartenance au scope vérifiée. |
| Cohérence et idempotence des versions | 3 | Pas de mutation pendant aperçu, persistance unique au dépôt, source incompatible rejetée ; configuration antérieure garde ses défauts. |
| Conformité aux règles et données de référence | 3 | Préférences et autorité macOS conservées ; vraie source entre écrans, limite de qualification/application nommée. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats, reprises et preuves brutes conservés avec SHA ; pas de verdict indépendant inventé. |
| Couverture des exigences obligatoires | 3 | FR1..FR4 et T007 reliées aux sources/tests ; suite finale et huit parcours, limites et premier échec explicites. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0, "candidates": 0, "suppressed": 0}

- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:87 ; f09f4c663ecc3f2c9a49
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:88 ; ee843150da2eaf25c1ac
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:89 ; 84c9a4ca3acab1c22692
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:318 ; 955e6b8d7b3f285b6391
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:479 ; b231a3b8ae61959456fa
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:511 ; 873d37e25c3fdea931b5
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:90 ; e86aea514743b37b8066
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:91 ; dbc2a0df94977611d029
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:92 ; 3a10794cc7617b23ca68
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:321 ; d4864cfc135aa8c5b090
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:482 ; 96444f032664f7bfbc71
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:514 ; 9102892e618458cac1fa
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:87 ; 4e8a580c8ed017fda3ba
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:88 ; 04c0e8929eeb7e446619
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:89 ; b3f1b7a3e79d96c03615
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:318 ; 7bbe5504a50f7e7c0cf6
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:479 ; 57d5a728bbc090820600
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.
- [refuted] HIGH : Detected a Generic API Key, potentially exposing access to various services and sensitive operations.
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:511 ; ff5c046ce7a68c0ddea8
  La valeur égale SHA256 du fichier nommé relu dans le même commit ; aucun moyen d’authentification.
  Action : Aucun changement de règle ou baseline ; contre-preuve conservée.

## Vérification réalisée

- security.static : pass ; completed, 0 candidat(s). 
- security.secrets : pass ; completed, 0 candidat(s).  Périmètre et limites dans la note invocation. Périmètre et limites dans la note invocation.
- security.history : pass ; Historique borné après v0.4.0 :30occurrences relues, 18identités distinctes après déduplication des révisions ; empreintes toutes recalculées et réfutées.
- security.dependencies : pass ; completed, 0 candidat(s).  Périmètre et limites dans la note invocation. Périmètre et limites dans la note invocation.
- security.authorization : pass ; AX/CG locaux existants, qualification sémantique, IDs/PID ; aucun changement de droit.
- correctness.logic : pass ; Séparation des deux fins de geste, annulation et dépôt conservés ; masque déjà atteint corrigé en red/green.
- correctness.concurrency : pass ; État MainActor, résultat de qualification à verrou, séquences au clic et permis ; un vrai up routé, files existantes.
- performance.complexity : pass ; Tap O(1)/O(w), bail2Hz existant, pas de relevé AX ou disque ajouté au callback ; masquage O(k*d).
- tests.regression : pass ; 2420tests/362suites réussis,64ciblés,28tests scripts via runner ; huit parcours natifs, limites de contrôles documentées.
- architecture.dependencies : pass ; Aucune dépendance ni pipeline ; propriétaires et dispatcher existants étendus.
- quality.minimalism : pass ; État ajouté lié à la fin native distincte ; ancien releasePoint et limite display retirés, pas de nouvelle horloge.
- quality.llm : not_applicable ; Aucun appel de modèle, prompt ou réponse LLM dans le produit modifié ; responsabilité future analysée dans les axes applicables.
- reliability.observability : pass ; Journaux différés de qualification/décision ; timeout/stop, bail et rollback durable.
- spec.traceability : pass ; FR1..FR4 rapprochées du code/tests et des parcours dans analysis.md ; réserves natives maintenues.

## Limites

Aucune limite déclarée pour les contrôles définis. Cela ne prouve pas l'absence de tout défaut.

## Minimalisme et responsabilité future

Potentiel de lignes suppressibles : non mesuré exhaustivement. Ancien releasePoint et restriction display retirés ; aucun framework, dépendance ou timer nouveau.

Une phase logique capturée, un marqueur natif et une séquence sont expliqués par les invariants et tests. Relecture locale independent=false ; admissions indépendantes refusées, aucune seconde opinion inventée.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
