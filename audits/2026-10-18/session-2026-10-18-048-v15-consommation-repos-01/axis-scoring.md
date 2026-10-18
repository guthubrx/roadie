## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 63/100 (D) | 63 | 4/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 50 | 1/1 | Évalué |
| Tests et validation | 56/100 (F) | 45 | 4/5 | Provisoire |
| Performance et ressources | 50/100 (F) | 38 | 3/4 | Provisoire |
| Complexité algorithmique | 75/100 (C) | 75 | 3/3 | Évalué |
| Qualité du code et des erreurs | 50/100 (F) | 25 | 1/2 | Provisoire |
| Architecture et dépendances | 63/100 (D) | 63 | 4/4 | Évalué |
| Responsabilité future et hygiène | 67/100 (D) | 67 | 3/3 | Évalué |
| Minimalisme et frugalité | 75/100 (C) | 75 | 3/3 | Évalué |
| Métier et fidélité des données | 67/100 (D) | 67 | 3/3 | Évalué |
| Traçabilité des exigences | 63/100 (D) | 63 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté mais une seule règle Swift ; entrées locales relues à la main. Niveau 3 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Adaptateur gitleaks : 7,72 Mo de sources analysés sans fuite, exclusions figées connues. Niveau 4 : contrôle en CI sur chaque commit. |
| Maîtrise des secrets historiques | 2 | Historique v0.4.0..ab9b28e9 (69 commits) sans fuite, décision utilisateur option A ; historique antérieur à v0.4.0 non analysé. Niveau 3 : historique complet sous budget. |
| Authentification et séparation des droits | Non applicable | Aucun mécanisme d'authentification ni de séparation des droits dans le diff ; la permission Screen Recording est inchangée. |
| Maîtrise des dépendances vulnérables | 3 | Adaptateur OSV exécuté sur Package.resolved : 1 paquet, aucun avis ; dépendances inchangées. Niveau 4 : suivi continu des avis. |

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
| Reprise des traitements interrompus | 2 | Reprises lues : capture nil retire le cache, absence réessayée après 5 s, arrêt du rail remet le statut à relire. Non testé à l'exécution. Niveau 3 : tests des échecs de capture et du redémarrage. |
| Continuité pendant une bascule | Non applicable | Aucune bascule ni redondance dans le périmètre ; le mode modulaire garde la règle des 150 ms, ce n'est pas une bascule. |
| Restauration après sinistre | Non applicable | Aucune restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et tests sans erreur ; aucun avertissement dans les fichiers du diff. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter dans le projet ; seuls les avertissements du compilateur, tous hors diff. Niveau 3 : linter configuré et exécuté. |
| Régressions et cas limites | 2 | Tests ciblés sur le vrai service, l'ordonnanceur et les vues ; manquent l'événement pendant l'acquisition, les échecs de capture et le redémarrage du rail. Niveau 3 : ces trois tests. |
| Qualification du runtime livré | Non vérifié | Runtime livré non qualifié par cet audit : installation et santé seulement rapportées par validation.md ; redémarrage et installation interdits. |
| Tests interface et intégration des données | 2 | RailPanel et StageCardView réels testés ; pas de test du routage renderPanels -> refreshThumbnails. Niveau 3 : test d'intégration du rail. |

- Contrôle non vérifié : axes.tests.04
- 1 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Un seul lot de capture, budgets et quarantaines inchangés, aucune file ajoutée. Pas de test de charge. Niveau 3 : mesure sous rafale. |
| Budget mémoire | 2 | Cache SCWindow borné par prune ; baisse RSS rapportée par les mesures de session, non rejouées. Niveau 3 : mesure rejouée. |
| Délais, annulation et libération | 2 | inFlight libéré par defer, absence bornée à 5 s, plafond borné par le filet ; chemins non testés. Niveau 3 : tests d'annulation et de délai. |
| Mesures représentatives de latence et charge | Non vérifié | Mesures avant/après de la session relues dans les fichiers figés, non rejouées (redémarrage et mesure de repos hors autorisation). |

- Contrôle non vérifié : axes.performance.04
- 1 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée ajoutés O(1) ou O(k) analysés et annotés. Niveau 4 : mesure à n élevé. |
| Bornes des parcours et allocations | 3 | Parcours bornés : k <= budget, cache réduit par prune, cartes x membres d'un écran. Niveau 4 : borne vérifiée par test. |
| Coût des accès et écritures de données | 3 | Relevés AX, énumérations SCK et lecture de recording.json réduits ; stages.json et rail.json revalidés par fstat sans décodage (F2/F4 réfutés). Niveau 4 : compteur runtime. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | Non applicable | Le diff ne modifie aucun refus ni message utilisateur ; l'absence de permission est journalisée une fois, inchangé. |
| Gestion des erreurs partielles | 2 | Échec d'énumération : abandon du lot ; capture nil : retrait du cache ; capture vide : ignorée. Lu, non testé. Niveau 3 : tests des trois cas. |
| Ergonomie des parcours concernés | Non vérifié | Parcours visibles (bordure, vignettes, indicateur) non observés : pas d'accès au bureau. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | État partagé dans SnapshotProcessState existant, câblage dans main.swift, aucune dépendance nouvelle. Niveau 4 : règle d'architecture vérifiée par outil. |
| Maîtrise des cycles | 2 | Aucun cycle introduit d'après la lecture des imports et appels ; aucun outil de graphe Swift. Niveau 3 : graphe des modules vérifié. |
| Séparation construction et exécution | 3 | Réutilisation activée une fois au démarrage par la racine de composition, seulement avec les événements en direct. Niveau 4 : test de composition. |
| Assemblages et dépendances dynamiques | 2 | Rappel onObservationChange injecté avec défaut sans effet : une composition sans rappel garderait des relevés jusqu'à 2 s ; documenté (ADR 015), non testé. Niveau 3 : test de câblage. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | ADR 015 nomme invariants, conditions et conséquences négatives ; amende 009 et 013. Niveau 4 : invariant « génération lue au départ » couvert par test. |
| Périmètre et maintenabilité du changement | 3 | Quatre mécanismes ciblés, aucun fichier hors périmètre, réversibles séparément. Niveau 4 : réversibilité démontrée par test. |
| Revue contradictoire et responsabilité | 2 | Revues par un autre modèle documentées ; la session antérieure a confirmé à tort F2/F4, corrigé dans validation.md ; cet audit n'est pas indépendant. Niveau 3 : contre-revue indépendante. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée ni nouveau fichier source. Niveau 4 : inventaire des dépendances mesuré. |
| Poids et ressources justifiés | 3 | Coût de repos réduit par construction ; lectures d'état réduites à fstat. Niveau 4 : mesure rejouée. |
| Code mort et simplifications possibles | 3 | Environ 2 lignes suppressibles, aucun code mort ajouté. Niveau 4 : outil de code mort Swift. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 2 | Données lues fidèles à 2 s près pour les changements sans notification (accepté par ADR 015) ; rendu réel non observé. Niveau 3 : observation runtime. |
| Cohérence et idempotence des versions | 3 | Génération monotone, empreintes d'état et de config comparées, republication qui conserve la génération. Niveau 4 : test de propriété. |
| Conformité aux règles et données de référence | 3 | Règle des 150 ms des commandes conservée et testée ; amendement d'ADR tracé. Niveau 4 : vérification runtime. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 2 | Constats reliés à cause, sources et tests ; la session versée ne peut pas être revalidée depuis Git (runs/ et configs/ ignorés). Niveau 3 : preuves versionnées ou archivées. |
| Couverture des exigences obligatoires | 3 | Cinq exigences vérifiées une à une, toutes implémentées. Niveau 4 : chaque exigence couverte par un test nommé. |

