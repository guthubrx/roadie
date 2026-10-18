## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 58/100 (F) | 44 | 3/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 50 | 1/1 | Évalué |
| Tests et validation | 56/100 (F) | 45 | 4/5 | Provisoire |
| Performance et ressources | 44/100 (F) | 38 | 3/4 | Provisoire |
| Complexité algorithmique | 61/100 (D) | 61 | 3/3 | Évalué |
| Qualité du code et des erreurs | 50/100 (F) | 25 | 1/2 | Provisoire |
| Architecture et dépendances | 63/100 (D) | 63 | 4/4 | Évalué |
| Responsabilité future et hygiène | 67/100 (D) | 67 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 67/100 (D) | 67 | 3/3 | Évalué |
| Traçabilité des exigences | 63/100 (D) | 63 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté mais une seule règle Swift ; entrées locales relues à la main. Niveau 4 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Analyse gitleaks réelle de 218 Mo sans fuite, adaptateur vide expliqué. Niveau 4 : exclusion corrigée dans la politique pour les worktrees. |
| Maîtrise des secrets historiques | Non vérifié | Historique Git non analysé : deux expirations à 300 s. |
| Authentification et séparation des droits | Non applicable | Aucun mécanisme d'authentification ni de séparation des droits dans le diff ; la permission Screen Recording est inchangée. |
| Maîtrise des dépendances vulnérables | 2 | Verrou analysé par OSV (1 paquet, aucun avis) ; adaptateur aveugle sur le worktree. Niveau 3 : analyse par l'adaptateur figé. |

- Contrôle non vérifié : axes.security.03
- Contrôle commun non vérifié : security.history
- outil gitleaks-history: timeout
- 1 critère(s) sans niveau de qualité justifié

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
| Reprise des traitements interrompus | 2 | Reprises lues : capture en échec retire le cache, absence réessayée après 5 s, redémarrage du rail relit le statut (F1 corrigé). Non testé à l'exécution. Niveau 3 : tests des chemins d'échec de capture et du redémarrage. |
| Continuité pendant une bascule | Non applicable | Aucune bascule ni redondance dans le périmètre ; le mode modulaire garde la règle des 150 ms (test readerWithoutTrackingTilerKeepsTheOldRule), ce n'est pas une bascule. |
| Restauration après sinistre | Non applicable | Aucune restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et des tests sans erreur en révision 1 ; aucun avertissement venant du diff. Niveau 4 : vérification de concurrence au runtime (Thread Sanitizer). |
| Analyse de style et erreurs statiques | 2 | Pas de linter dans le projet ; seuls les avertissements du compilateur, aucun nouveau dans le diff (5 antérieurs). Niveau 3 : linter configuré et exécuté. |
| Régressions et cas limites | 2 | Tests ciblés sur le vrai service, le vrai ordonnanceur et les vraies vues, bornes 1,99 / 2,01 s et mode modulaire ; manquent l'événement pendant l'acquisition, les échecs de capture et le redémarrage du rail. Niveau 3 : ces trois tests. |
| Qualification du runtime livré | Non vérifié | Runtime livré non qualifié par cet audit : installation et santé seulement rapportées par validation.md, redémarrage interdit. |
| Tests interface et intégration des données | 2 | RailPanel et StageCardView réels testés (identité des cartes, redessin) ; pas de test du routage renderPanels -> refreshThumbnails ni du rendu effectif. Niveau 3 : test d'intégration du rail avec un magasin de vignettes injecté. |

- Contrôle non vérifié : axes.tests.04
- 1 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Un seul lot de capture à la fois, budgets et quarantaines inchangés, regroupement des demandes inchangé ; aucune file ajoutée. Pas de test de charge. Niveau 3 : mesure sous rafale d'événements. |
| Budget mémoire | 2 | Cache SCWindow borné par prune à chaque rendu ; RSS 112 -> 92 Mo selon les mesures de la session (non rejouées). Niveau 3 : mesure rejouée. |
| Délais, annulation et libération | 2 | inFlight libéré par defer, absence bornée à 5 s, plafond borné par le filet, contrôle Task.isCancelled conservé. Sans test de ces chemins. Niveau 3 : tests d'annulation et de délai. |
| Mesures représentatives de latence et charge | Non vérifié | Mesures avant/après de la session relues dans les fichiers figés, non rejouées (redémarrage et mesure de repos hors autorisation). |

- Contrôle non vérifié : axes.performance.04
- 1 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée ajoutés O(1) ou O(k) analysés et annotés. Niveau 4 : mesure de l'effet à n élevé. |
| Bornes des parcours et allocations | 3 | Parcours bornés : k <= budget, cache réduit par prune, cartes x membres d'un écran. Niveau 4 : borne vérifiée par test. |
| Coût des accès et écritures de données | 2 | Relevés AX, énumérations SCK et lecture de recording.json réduits ; stages.json et rail.json encore décodés chaque seconde (F2) et stages.json toutes les 150 ms par les poignées (F4). |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | Non applicable | Le diff ne modifie aucun refus ni message utilisateur ; l'absence de permission est journalisée une fois, inchangé. |
| Gestion des erreurs partielles | 2 | Échec d'énumération : abandon du lot ; capture nil : retrait du cache ; capture vide : ignorée. Comportements lus, non testés. Niveau 3 : tests des trois cas. |
| Ergonomie des parcours concernés | Non vérifié | Parcours visibles (bordure, vignettes, indicateur) non observés : pas d'accès au bureau. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Frontières respectées : état partagé dans SnapshotProcessState existant, câblage dans main.swift, aucune dépendance nouvelle. Niveau 4 : règle d'architecture vérifiée par outil. |
| Maîtrise des cycles | 2 | Aucun cycle introduit d'après la lecture des imports et appels ; aucun outil de graphe pour Swift. Niveau 3 : graphe des modules vérifié. |
| Séparation construction et exécution | 3 | Réutilisation activée une fois au démarrage par la racine de composition, seulement avec les événements en direct. |
| Assemblages et dépendances dynamiques | 2 | Rappel onObservationChange injecté avec défaut sans effet : une nouvelle composition qui active la réutilisation sans le rappel garderait des relevés jusqu'à 2 s ; le lien est documenté (ADR 015), non vérifié par test. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | ADR 015 nomme invariants, conditions et conséquences négatives ; amende 009 et 013. Niveau 4 : invariant « génération lue au départ » couvert par test. |
| Périmètre et maintenabilité du changement | 3 | Quatre mécanismes ciblés, aucun fichier hors périmètre, réversibles séparément (plan.md). |
| Revue contradictoire et responsabilité | 2 | Revue de plan et d'implémentation par un autre modèle documentée avec objections ; cet audit n'est pas indépendant. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée ni nouveau fichier source. |
| Poids et ressources justifiés | 2 | Coût de repos réduit par construction (relevés et énumérations évités) ; lectures de fichiers restantes (F2, F4). |
| Code mort et simplifications possibles | 3 | Environ 2 lignes suppressibles, aucun code mort ajouté. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 2 | Données lues fidèles à 2 s près pour les changements sans notification (accepté par ADR 015) ; F1 corrigé. Rendu réel non observé. |
| Cohérence et idempotence des versions | 3 | Génération monotone, empreintes d'état et de config comparées, republication qui conserve la génération. |
| Conformité aux règles et données de référence | 3 | Règle des 150 ms des commandes conservée et testée ; amendement d'ADR tracé. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Chaque constat relie cause, extrait avant correction, diff, exécutions et variantes. |
| Couverture des exigences obligatoires | 2 | Cinq exigences vérifiées ; R3 partielle (F2). |

