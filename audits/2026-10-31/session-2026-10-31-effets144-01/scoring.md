# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability
Sources : commit 37e5cd92e8bcaa5f0757427f7b16658dc45edd1d ; mode fix.
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
| Analyse statique et validation des entrées | 3 | Entrées TOML finies et bornées, identité CG ID/PID et qualification de surface ; Semgrep générique et compilateur, sans analyse Swift inter-fichiers. |
| Protection des secrets courants | 3 | Scan de fichiers exigé sur copie SHA hors du worktree ignoré ; aucune valeur secrète ajoutée dans les sources examinées. Scan complet joint. |
| Maîtrise des secrets historiques | 2 | Historique examiné seulement après v0.4.0, borne explicitement conservée ; ne qualifie pas les commits antérieurs. |
| Authentification et séparation des droits | 3 | Autorité locale AX déjà accordée ; pas de nouveau droit, SIP, injection ou compte ; fenêtres ciblées par identité stricte. |
| Maîtrise des dépendances vulnérables | 3 | Une seule dépendance Swift verrouillée et inchangée ; contrôle OSV explicite du verrou réussi. Pas de graphe atteignable complet. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucun modèle, prompt ou réponse LLM dans le produit du périmètre. |
| Permissions des appels externes | Non applicable | Aucun modèle, prompt ou réponse LLM dans le produit du périmètre. |
| Résistance aux instructions malveillantes | Non applicable | Aucun modèle, prompt ou réponse LLM dans le produit du périmètre. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Archive de rollback et quatre empreintes vérifiées ; politique de rotation générale inchangée, pas de qualification exhaustive de rétention. |
| Reprise des traitements interrompus | 3 | Permis révoqués, génération externe prioritaire, restauration/annulation testées ; aucun rejeu persistant du geste. |
| Continuité pendant une bascule | 3 | Configuration héritée compatible, transitions bornées, montage synchrone sans owner ; signature et état conservés pendant les chargements observés. |
| Restauration après sinistre | 2 | Archives précédentes et état sauvegardés ; restauration complète après sinistre non exercée sur le poste utilisateur. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilateur Swift6 et vérification Sendable sur les sources/tests, compilation et tests natifs ; quelques avertissements hérités conservés. |
| Analyse de style et erreurs statiques | 2 | Compilation, diff sans espace invalide et règles Semgrep ; pas de linter Swift de style dédié dans le projet. |
| Régressions et cas limites | 3 | Tests ciblés red/green et scénarios temporels, cellules hors main et contrôles matériels injectés ; suite finale2416 tests réussie. |
| Qualification du runtime livré | 3 | Build signé chargé, UUID/PID et santé5/5 ; usage réel et limites doivent rester distingués des tests. |
| Tests interface et intégration des données | 3 | Parcours natifs AppKit/éditeur/Finder/navigateur, rail et Échap ; captures fictives et métadonnées réelles, sans revue visuelle de tous les contrôles. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 3 | Un lot actif et une cible en attente par PID ; dernière cible seulement, délai borné et autres applications indépendantes. |
| Budget mémoire | 2 | RSS mesuré, état linéaire borné ; aucun profil de tas ni mesure de mémoire privée par application. |
| Délais, annulation et libération | 3 | Annulation au clic, fin/désactivation et notifications contexte ; tests slowAX et timer libéré ; appel AX engagé non interrompu de force. |
| Mesures représentatives de latence et charge | 2 | Mesures on/off natives mais BTT180ms inclus, caches/activité extérieure et GPU global empêchent une attribution précise. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Moteur O(k), dispatcher O(k+p), tap mouvements O(1) et clic O(w) mémoire ; le BSP quadratique hérité est nommé séparément. |
| Bornes des parcours et allocations | 3 | Clés d’animation limitées aux surfaces actives, états retirés, une dernière cible/PID et tâches de qualification remplacées. |
| Coût des accès et écritures de données | 3 | Pas de capture supplémentaire, aucune I/O dans le tap ; lecteurs/config/stages existants conservés hors callback. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Repli contour explicite, taille refusée conservée, réglages et aides FR/EN ; diagnostics sans contenu personnel. |
| Gestion des erreurs partielles | 3 | Deferred distinct de résultat final, refus/budgets respectés, échec de persistance explicite ; aucune réussite inventée à la planification. |
| Ergonomie des parcours concernés | 3 | Aperçu local, groupes repliés et valeurs héritées ; essais natifs, sans étude d’ergonomie multi-utilisateur. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Core calcul pur, AX qualification/writer, daemon coordination/UI ; pas de dépendance inversée ajoutée. |
| Maîtrise des cycles | 3 | Imports du manifeste lus, aucune dépendance/package ajoutée ; absence de graphe automatique Swift explicitée. |
| Séparation construction et exécution | 3 | Installer construit/signe, runtime n’active le writer animé que dans le composant tiler ; CLI sans owner reste synchrone. |
| Assemblages et dépendances dynamiques | 3 | Identités/générations et services existants réutilisés ; chargements natifs vérifiés, pas de plugin générique ou d’injection dynamique nouvelle. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | ADR024, plan/reuse-audit et tests expliquent propriété, annulation, héritage et limites macOS. |
| Périmètre et maintenabilité du changement | 3 | Responsabilités séparées et recherche d’existant tracée ; charge nouvelle du moteur/adapter explicitement assumée. |
| Revue contradictoire et responsabilité | 2 | Auto-relecture et protocole local réalisés ; revue indépendante demandée mais admission refusée, sans second avis inventé. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée ; dispatcher, store, UI de paramètres et fixture existants étendus. |
| Poids et ressources justifiés | 3 | Un moteur pour quatre consommateurs, ressources seulement actives ; mesures natives et limites de mémoire/GPU conservées. |
| Code mort et simplifications possibles | 2 | Revue locale des champs/helpers, ancien cubic et timer overview retirés ; pas d’outil Swift de code mort ni mesure exhaustive des lignes supprimables. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Cadres réels CG/AX, aucune photo étirée ; données de configuration validées et appartenance au scope vérifiée. |
| Cohérence et idempotence des versions | 3 | Pas de mutation pendant aperçu, persistance unique au dépôt, source incompatible rejetée ; configuration antérieure garde ses défauts. |
| Conformité aux règles et données de référence | 3 | Règles utilisateur/macOS indépendant conservées, modes et refus stricts ; limites multi-écrans explicites. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats, reprises et preuves brutes conservés avec SHA ; pas de verdict indépendant inventé. |
| Couverture des exigences obligatoires | 3 | FR/SC reliés aux sources/tests et à la matrice native ; réserves de terrain nommées, révision1 courante vérifiée. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0, "candidates": 0, "suppressed": 0}


## Vérification réalisée

- security.static : pass ; completed, 0 candidat(s). 
- security.secrets : pass ; completed, 0 candidat(s).  Copie SHA exacte hors chemin .worktrees, 13.27Mo effectivement scannés ; voir note invocation.
- security.history : pass ; completed, 0 candidat(s).  Historique limité à 5ab0ab9544de68edbd6642f58ac6140ef8a07f1e..37e5cd92e8bcaa5f0757427f7b16658dc45edd1d; les commits antérieurs sont hors périmètre.
- security.dependencies : pass ; completed, 0 candidat(s).  Verrou explicite TOMLKit0.6.0, aucune dépendance ajoutée.
- security.authorization : pass ; Autorité locale AX, identité CG ID/PID et qualification sémantique, aucun changement de droits ; contrôles/tabs et fenêtres incompatibles exclus.
- correctness.logic : pass ; Calcul de cibles, héritage et deferred examinés dans leurs consommateurs ; tests courbes, tailles refusées et restauration ; huit essais Chrome réels.
- correctness.concurrency : pass ; État de géométrie MainActor, résultat AX à verrou, permis et générations entre attributs, coalescence par PID et fin bornée ; aucun takeGesture ajouté.
- performance.complexity : pass ; O(k) calcul d’animation, un lot actif/dernière cible par PID, tap O(1) par mouvement et O(w) par clic mémoire ; BSP hérité séparé et limites mesures explicites.
- tests.regression : pass ; 2416 tests/360 suites et28 tests de scripts réussis sur la révision1 ; tests ciblés et huit parcours natifs Chrome documentés.
- architecture.dependencies : pass ; Core pur, couche AX pour qualification et writer, coordination daemon ; aucune dépendance ajoutée, dispatcher et services existants réutilisés.
- quality.minimalism : pass ; Un moteur partagé par quatre usages, reprise de la session et fixture143 ; pas de service générique ni capture supplémentaire. Potentiel de suppression exhaustive non mesuré.
- quality.llm : not_applicable ; La modification ne contient ni appel de modèle, ni agent produit, ni traitement de réponse LLM. La qualification de fenêtre est locale AX/CG.
- reliability.observability : pass ; Événements de décision/qualification, starts/ends des effets, annulations et fallback ; diagnostics hors callback et sans contenu de fenêtre.
- spec.traceability : pass ; Huit FR/cinq SC rapprochés du code et des tests, limites multi-écrans/mesures/revue distante explicites ; livraison distincte de l’implémentation.

## Limites

Aucune limite déclarée pour les contrôles définis. Cela ne prouve pas l'absence de tout défaut.

## Minimalisme et responsabilité future

Potentiel minimalisme : non mesuré exhaustivement ; moteur commun et dispatcher/session/fixture repris. Aucun service ou dépendance supprimable identifié dans les chemins lus. Pas de promesse de lignes supprimées.

Charge future : une horloge commune et un adaptateur AX à maintenir ; invariants, limites et variantes documentés dans ADR024 et tests. Relecture locale independent=false, revue distincte refusée et tracée.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
