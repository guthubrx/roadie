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

