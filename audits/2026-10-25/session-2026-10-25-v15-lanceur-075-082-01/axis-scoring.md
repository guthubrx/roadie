## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 56/100 (F) | 56 | 4/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | 63/100 (D) | 63 | 2/2 | Évalué |
| Tests et validation | 65/100 (D) | 65 | 5/5 | Évalué |
| Performance et ressources | 49/100 (F) | 49 | 4/4 | Évalué |
| Complexité algorithmique | 66/100 (D) | 66 | 3/3 | Évalué |
| Qualité du code et des erreurs | 55/100 (F) | 55 | 3/3 | Évalué |
| Architecture et dépendances | 69/100 (D) | 69 | 4/4 | Évalué |
| Responsabilité future et hygiène | 50/100 (F) | 50 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 74/100 (C) | 74 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté (une règle Swift) ; appels externes relus : identifiants fixes, pas de texte saisi interpolé. Niveau 3 : règles Swift ciblées ou CodeQL. |
| Protection des secrets courants | 3 | Gitleaks fichiers sans fuite. Niveau 4 : contrôle en CI à chaque commit. |
| Maîtrise des secrets historiques | 2 | Historique borné depuis v0.10.0. Niveau 3 : historique complet analysé. |
| Authentification et séparation des droits | Non applicable | Aucune authentification ni séparation de droits dans le périmètre. |
| Maîtrise des dépendances vulnérables | 2 | Package.resolved sans avis (relance), adaptateur en erreur. Niveau 3 : adaptateur réussi. |

- Contrôle commun non vérifié : security.dependencies
- outil osv-scanner: error

### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | Non applicable | Aucune fonction LLM dans le produit ni dans le diff. |
| Permissions des appels externes | Non applicable | Aucun appel à un service LLM. |
| Résistance aux instructions malveillantes | Non applicable | Aucune entrée traitée par un LLM. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 2 | Règles générées relues avant écriture ; sauvegardes manuelles des fichiers du lanceur pendant l'audit ; pas de rotation automatique. Niveau 3 : sauvegarde automatique avant réécriture. |
| Reprise des traitements interrompus | 3 | Aperçu à échéance 1,5 s, placements 10 s, positions 20 s, annulation 10 min : un traitement interrompu ne laisse rien bloqué. Niveau 4 : essai de panne en réel. |
| Continuité pendant une bascule | Non applicable | Pas de bascule de service dans le périmètre. |
| Restauration après sinistre | Non applicable | Pas de restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 des sources et des tests sans erreur. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter Swift configuré ; avertissements du compilateur traités. Niveau 3 : linter configuré. |
| Régressions et cas limites | 3 | 2 028 tests ; suites Spec075-082 avec cas limites (règle unique, rangs, échéances, format). Niveau 4 : propriétés ou mutation. |
| Qualification du runtime livré | 3 | Installation signée, santé 5/5 et essais réels par CLI à chaque session. Niveau 4 : essai clavier enregistré. |
| Tests interface et intégration des données | 2 | Rendu vérifié sur données fictives ; parcours clavier non simulés. Niveau 3 : tests d'interface. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | 2 | Chargements en fond (applications, fichiers, documents, onglets) ; pas de file sans borne. Niveau 3 : mesure de charge. |
| Budget mémoire | 2 | Bornes sur les mémoires persistantes ; onglets en mémoire pendant la barre sans plafond. Niveau 3 : plafond et mesure. |
| Délais, annulation et libération | 3 | Délais : osascript 2 s, aperçu 150 ms et 1,5 s, placement 10 s, position 20 s ; nettoyage à la fin de la barre. |
| Mesures représentatives de latence et charge | 1 | Critère de 50 ms par frappe et délai d'annonce non mesurés. Niveau 2 : mesure représentative. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Points d'entrée annotés O(…) ; analyse de phrase O(m × d), liste O(a × q × t + n log n). |
| Bornes des parcours et allocations | 3 | Bornes écrites et testées (200, 6, 9, 40, 5). |
| Coût des accès et écritures de données | 2 | F2 : réécriture JSON synchrone à chaque déplacement. Niveau 3 : écriture différée ou mesurée. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Refus expliqués (action non gardable, stage anonyme, stage inconnue en CLI). Niveau 4 : messages essayés par l'utilisateur. |
| Gestion des erreurs partielles | 2 | Projet rouvert en partie : arbre non remis, journalisé ; aperçu restauré à l'échec. Niveau 3 : reprise du reste. |
| Ergonomie des parcours concernés | 2 | F1 demande d'autorisation sans geste lié ; parcours clavier à essayer. Niveau 3 : parcours validés. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Types purs séparés du contrôleur ; aucune dépendance de module ajoutée. |
| Maîtrise des cycles | 3 | Aucun cycle de module ajouté (imports relus). |
| Séparation construction et exécution | 2 | Contrôleur TargetModeRuntimeController très volumineux, mêle orchestration et effets. Niveau 3 : services dédiés. |
| Assemblages et dépendances dynamiques | 3 | Assemblage par fermetures du contexte de barre ; aucun chargement dynamique. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Invariants et compromis écrits (research.md, commentaires). |
| Périmètre et maintenabilité du changement | 2 | Huit sessions en une passe, diff large ; découpage par session et tests ciblés. Niveau 3 : diff réduit par livraison relue. |
| Revue contradictoire et responsabilité | 1 | Aucune revue contradictoire : Bridget a refusé deux admissions. Niveau 2 : revue indépendante documentée. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. |
| Poids et ressources justifiés | 2 | osascript par navigateur à chaque ouverture, requêtes Spotlight par frappe (débounce 120 ms). Niveau 3 : coût mesuré. |
| Code mort et simplifications possibles | 3 | Pas de code mort identifié ; options de diagnostic justifiées par les essais réels. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Document lu en chaîne ou URL après relevé réel (077), cadres d'onglets comparés à 2 points. |
| Cohérence et idempotence des versions | 3 | Règle unique par application, projets remplacés par nom, annulation idempotente bornée. |
| Conformité aux règles et données de référence | 3 | Noms de stage réels selon la règle 067 ; règles générées relues. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constats reliés aux corrections et preuves (notes, tests, validation). |
| Couverture des exigences obligatoires | 3 | Exigences de 075 à 082 couvertes ou limites écrites dans validation.md. |

