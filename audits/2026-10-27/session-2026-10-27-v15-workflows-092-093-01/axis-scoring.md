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
| Responsabilité future et hygiène | 58/100 (F) | 58 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 75/100 (C) | 75 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep (peu de règles Swift) ; citations shell, AppleScript (quoted form of) et JavaScript relues et testées. Niveau 3 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Gitleaks fichiers sans fuite. Niveau 4 : contrôle en CI à chaque commit. |
| Maîtrise des secrets historiques | 2 | Historique borné depuis 5ed75b05. Niveau 3 : historique complet analysé. |
| Authentification et séparation des droits | 2 | Pas d'authentification ; frontière : code tiers des workflows avec les droits du démon (inchangé) ; l'osascript de Roadie ne s'applique qu'à leurs scripts. Niveau 3 : isolement des scripts. |
| Maîtrise des dépendances vulnérables | 3 | OSV depuis une copie propre hors .worktrees : 0 avis ; aucune dépendance ajoutée. Niveau 4 : surveillance continue. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucune fonction LLM dans le produit ni dans le diff. |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM. |
| Résistance aux instructions malveillantes | Non applicable | Aucune entrée traitée par un LLM. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Configuration de l'utilisateur non modifiée ; réglages des workflows gardés à part, jamais dans le dossier d'Alfred. Niveau 3 : migration et retour arrière écrits. |
| Reprise des traitements interrompus | 3 | Grille : erreur de script notifiée, source inconnue signalée ; osascript de Roadie passe la main sans ordre ; scripts toujours bornés (délai, plafond, groupe). |
| Continuité pendant une bascule | Non applicable | Pas de bascule de service dans le périmètre. |
| Restauration après sinistre | Non applicable | Pas de restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et des tests sans erreur. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter Swift configuré ; avertissements du compilateur traités. Niveau 3 : linter configuré. |
| Régressions et cas limites | 3 | 2 110 tests ; formes réelles du corpus, exécutions réelles d'osascript, cas limites (espaceurs, bords, apostrophe, #!). |
| Qualification du runtime livré | 3 | Installation signée et santé 5/5 ; essai réel de la grille (journal) et mesure réelle des ordres (fichier d'essai). Niveau 4 : essai automatisé de bout en bout. |
| Tests interface et intégration des données | 2 | Workflows réels de l'utilisateur et corpus ; rendu des tuiles non capturé. Niveau 3 : test d'interface automatisé. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Script de grille lancé une fois, filtre en mémoire ; traduction O(n) au lancement. Niveau 3 : mesure du coût par script. |
| Budget mémoire | 2 | Tuiles en mémoire pour la barre ouverte ; sorties plafonnées à 5 Mo. Niveau 3 : mesure mémoire. |
| Délais, annulation et libération | 3 | Délais des scripts conservés (10 s), osascript de Roadie remplacé par execv (aucun processus en plus). |
| Mesures représentatives de latence et charge | 1 | Latence de la barre en grille et coût du passage par roadie non mesurés. Niveau 2 : mesure représentative. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée annotés O(…) (traduction, voisins, disposition, fiche). |
| Bornes des parcours et allocations | 3 | Bornes écrites et testées (1 à 12 colonnes, tuiles montrées, 200 étapes). |
| Coût des accès et écritures de données | 2 | Fiche : regex par variable JavaScript sur tout le texte (O(v × n), v petit). Niveau 3 : un seul passage. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Messages clairs : source de grille inconnue, script de grille absent, ordres non traduits nommés. |
| Gestion des erreurs partielles | 3 | Grille : Retour sur une tuile invalide sans effet ; ordre inconnu laissé visible (erreur) plutôt qu'ignoré. |
| Ergonomie des parcours concernés | 2 | ← → réservées à la grille (choix de l'utilisateur) ; parcours clavier à essayer. Niveau 3 : parcours validé. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Types purs (AlfredGridView, AlfredBridge), effets injectés (showGrid) ; aucune dépendance ajoutée. |
| Maîtrise des cycles | 3 | Aucun cycle de module ajouté. |
| Séparation construction et exécution | 2 | Présentateur (+80) et contrôleur (+40) grossissent encore. Niveau 3 : services dédiés. |
| Assemblages et dépendances dynamiques | 3 | Grille par la vue en attente et le contexte de barre ; aucun chargement dynamique de code Roadie. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Invariants, compromis et mesures écrits (research.md, validation.md, commentaires). |
| Périmètre et maintenabilité du changement | 3 | Deux sessions découpées, diff borné (~1 200 lignes), Converge en deux passages chacune. |
| Revue contradictoire et responsabilité | 1 | Aucune revue contradictoire : Bridget a refusé l'admission (origin_request_invalid). Niveau 2 : revue indépendante documentée. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. |
| Poids et ressources justifiés | 2 | Un passage par roadie pour chaque osascript de workflow (execv, coût non mesuré). Niveau 3 : coût mesuré. |
| Code mort et simplifications possibles | 3 | Pas de code mort identifié ; mentionsAlfred remplacé, non dupliqué. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Format d'Alfred relevé sur les workflows réels (grilles, externalid, 12 workflows à ordres). |
| Cohérence et idempotence des versions | 3 | Réglages gardés idempotents (fusion par clé) ; une grille à la fois. |
| Conformité aux règles et données de référence | 3 | Dossier d'Alfred jamais écrit ; aucun workflow tiers livré. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats reliés aux corrections, reproductions et tests. |
| Couverture des exigences obligatoires | 3 | Exigences 092 et 093 couvertes ou limites écrites dans validation.md. |

