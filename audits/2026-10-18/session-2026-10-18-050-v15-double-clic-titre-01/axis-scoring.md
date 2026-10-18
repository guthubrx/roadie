## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 63/100 (D) | 63 | 4/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 50/100 (F) | 50 | 1/1 | Évalué |
| Tests et validation | 56/100 (F) | 45 | 4/5 | Provisoire |
| Performance et ressources | 75/100 (C) | 50 | 2/3 | Provisoire |
| Complexité algorithmique | 67/100 (D) | 67 | 3/3 | Évalué |
| Qualité du code et des erreurs | 63/100 (D) | 42 | 2/3 | Provisoire |
| Architecture et dépendances | 63/100 (D) | 63 | 4/4 | Évalué |
| Responsabilité future et hygiène | 67/100 (D) | 67 | 3/3 | Évalué |
| Minimalisme et frugalité | 75/100 (C) | 75 | 3/3 | Évalué |
| Métier et fidélité des données | 67/100 (D) | 67 | 3/3 | Évalué |
| Traçabilité des exigences | 63/100 (D) | 63 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté, une seule règle Swift ; entrées (préférences, rôle AX) relues à la main. Niveau 3 : règles Swift ciblées. |
| Protection des secrets courants | 3 | Adaptateur gitleaks : 7,77 Mo sans fuite. Niveau 4 : contrôle en CI. |
| Maîtrise des secrets historiques | 2 | Historique v0.4.0..8c207d67 (73 commits) sans fuite, option A ; historique antérieur non analysé. Niveau 3 : historique complet. |
| Authentification et séparation des droits | Non applicable | Aucun mécanisme d'authentification ni de séparation des droits dans le diff. |
| Maîtrise des dépendances vulnérables | 3 | OSV : aucun avis ; dépendances inchangées. Niveau 4 : suivi continu. |

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
| Reprise des traitements interrompus | 2 | Double-clic perdu ou refusé : aucune action, aucun état à reprendre ; retour par second double-clic testé dans la reproduction. Niveau 3 : test de bout en bout. |
| Continuité pendant une bascule | Non applicable | Aucune bascule dans le périmètre. |
| Restauration après sinistre | Non applicable | Aucune restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 sans erreur ni avertissement dans le diff. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter dans le projet. Niveau 3 : linter configuré. |
| Régressions et cas limites | 2 | Fonctions pures, décodage et santé testés ; handleDoubleClick non testé de bout en bout ; interaction avec le geste couverte seulement par la reproduction d'audit. Niveau 3 : test de bout en bout dans le dépôt. |
| Qualification du runtime livré | Non vérifié | Binaire installé non exécuté ; double-clic réel non essayé (pas d'accès au bureau). |
| Tests interface et intégration des données | 2 | Aucun test d'intégration du contrôleur avec ses injections. Niveau 3 : test avec readPreference et elementRoleAt injectés. |

- Contrôle non vérifié : axes.tests.04
- 1 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | Non applicable | Aucune file ni admission de demandes dans le périmètre. |
| Budget mémoire | 3 | Aucune allocation durable ajoutée. Niveau 4 : mesure. |
| Délais, annulation et libération | 3 | Requête AX bornée à 0,5 s par le délai global posé par le relevé précédent. Niveau 4 : délai mesuré sur application suspendue. |
| Mesures représentatives de latence et charge | Non vérifié | Latence d'un double-clic non mesurée. |

- Contrôle non vérifié : axes.performance.04
- 1 critère(s) sans niveau de qualité justifié

### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Clic simple O(1), double-clic O(w) avec un relevé, annotés. Niveau 4 : mesure. |
| Bornes des parcours et allocations | 3 | Parcours bornés par les fenêtres du relevé et la liste fixe des rôles. Niveau 4 : borne testée. |
| Coût des accès et écritures de données | 2 | Relevé complet avant le test de barre de titre à chaque double-clic actif, partout sur l'écran ; conforme à R4, pré-filtre possible. Niveau 3 : pré-filtre mesuré. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 2 | Message de santé clair, en français seulement ; aucun retour quand le double-clic est ignoré (voulu). Niveau 3 : libellés localisés. |
| Gestion des erreurs partielles | 3 | Résultat de toggleMaximize journalisé avec son message ; refus sans effet de bord. Niveau 4 : test des refus. |
| Ergonomie des parcours concernés | Non vérifié | Parcours réel du double-clic non observé (pas d'accès au bureau). |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Réutilise hitTest, toggleMaximize et le contrôle de santé existants. Niveau 4 : règle vérifiée par outil. |
| Maîtrise des cycles | 2 | Aucun cycle d'après la lecture ; pas d'outil de graphe Swift. Niveau 3 : graphe vérifié. |
| Séparation construction et exécution | 3 | Injections résolues à la construction ; composant démarré par défaut. Niveau 4 : test de composition. |
| Assemblages et dépendances dynamiques | 2 | La santé dépend du réglage d'un autre composant via effectiveConfig : warn même avec --no-titlebar-menu. Niveau 3 : état réel du composant. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Contrainte (moniteur sans consommation) et choix « Ne rien faire » expliqués dans research.md. Niveau 4 : essai réel consigné. |
| Périmètre et maintenabilité du changement | 3 | Changement ciblé, réversible par réglage. Niveau 4 : réversibilité testée. |
| Revue contradictoire et responsabilité | 2 | Revue 1 consignée et traitée ; validation finale non consignée ; cet audit n'est pas indépendant. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. Niveau 4 : inventaire mesuré. |
| Poids et ressources justifiés | 3 | Coût nul pour un clic simple. Niveau 4 : mesure. |
| Code mort et simplifications possibles | 3 | Aucun code mort identifié. Niveau 4 : outil de code mort. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Action macOS lue avec repli sur la préférence héritée ; préférences réelles cohérentes avec research.md. Niveau 4 : essai réel. |
| Cohérence et idempotence des versions | 3 | Second double-clic rend la disposition (toggle) ; arbre inchangé dans la reproduction. Niveau 4 : essai réel. |
| Conformité aux règles et données de référence | 2 | Défaut true + macOS par défaut : fonction inactive et santé warn chez l'utilisateur, contre le critère 049 (F1). Niveau 3 : défauts cohérents. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats reliés aux sources, aux observations runtime et à la reproduction. Niveau 4 : reproduction dans le dépôt. |
| Couverture des exigences obligatoires | 2 | Six exigences vérifiées ; T005 non consignée. Niveau 3 : validation consignée. |

