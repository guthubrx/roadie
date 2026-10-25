# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability
Sources : commit 0a579d60b364347d4b202a50a4bae67116197d24 ; mode fix.
Décision : **inconclusive** ; note globale : N/A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 13/14.

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



## Risque constaté

{"critical": 0, "high": 0, "medium": 1, "low": 2, "info": 0, "total": 3, "candidates": 0, "suppressed": 0}

- [confirmed] MEDIUM : Onglets lus à chaque ouverture de la barre : demande d'automatisation sans geste lié
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/TargetModeRuntimeController.swift:1 ; 6c2f280f713e8268dccf
  openItems interroge chaque navigateur scriptable ouvert dès l'ouverture de la barre ; la première fois macOS demande l'automatisation par navigateur, ensuite un osascript par navigateur à chaque ouverture (2 s au plus, en fond).
  Action : Décision de conception : lire les onglets à la première frappe ou derrière un réglage.
- [confirmed] LOW : Relecture et réécriture du journal des déplacements à chaque affectation
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LauncherMemory.swift:1 ; 56e14d0ca2dd44b94be5
  record lit puis écrit un JSON de 200 entrées au plus sur le fil principal à chaque déplacement ; événement rare et borné.
  Action : Cache mémoire et écriture différée si un coût est mesuré.
- [confirmed] LOW : Première fenêtre nouvelle du paquet prise comme fenêtre ouverte par le lanceur
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/TargetModeRuntimeController.swift:1 ; e934ab814bd6eca2f45a
  Une fenêtre ouverte par l'utilisateur dans les 10 s serait rangée à la place ; limite connue depuis 074, reprise par 077 et 080.
  Action : Accepter la limite documentée ou relier la fenêtre au document ouvert (AXDocument) quand il est exposé.
- [fixed] LOW : Stage mémorisée pour des dossiers hors du dossier personnel
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/TargetModeRuntimeController.swift:1 ; e7d13c65f45b5aacae8c
  rememberFolder enregistrait folder:<dossier> pour tout fichier, dont /tmp : 4 entrées observées dans le classement réel.
  Action : Même règle que la recherche : LauncherFileRules.isShown.

## Vérification réalisée

- security.static : pass ; Semgrep : règles figées sur les 44 fichiers sélectionnés, 0 résultat ; une seule règle Swift dans le pack : relecture manuelle des appels externes (notes/axes.md).
- security.secrets : pass ; Gitleaks sur les fichiers : 0 fuite.
- security.history : pass ; Gitleaks historique limité à v0.10.0 (410ed34a)..0a579d60 : 0 fuite ; valable pour cette plage seulement.
- security.dependencies : unknown ; Adaptateur OSV en erreur (worktree sous .worktrees/, ignoré par Git ; l'adaptateur ne passe pas --no-ignore). Relance sur Package.resolved par l'exécuteur : 0 avis, manifestes inchangés depuis la base. Limite d'outil, pas de preuve de l'adaptateur.
- security.authorization : pass ; Aucune authentification ni frontière réseau ; appels AppleScript à des navigateurs fixes avec entiers, autorisation d'automatisation demandée par macOS (F1) ; règles écrites sur choix explicite et relues.
- correctness.logic : pass ; Invariants 1 à 5 vérifiés (notes/contexte.md) ; F3 limite connue ; F4 corrigé et testé.
- correctness.concurrency : pass ; Tâches MainActor ; jeton d'aperçu qui invalide les étapes asynchrones ; LayoutPreviewHold sous verrou à échéance ; lectures AX en tâches détachées sans état partagé mutable.
- performance.complexity : pass ; Fonctions annotées, bornes explicites (200 déplacements, 6 contextes, 40 fichiers) ; aucune boucle imbriquée non bornée ; F2 écriture bornée.
- tests.regression : pass ; scripts/test --no-parallel par l'exécuteur : 2 028 tests / 277 suites réussis, dont Spec075 à Spec082 et le test de F4.
- architecture.dependencies : pass ; Aucune dépendance de module ni externe ajoutée ; nouveaux types purs séparés du contrôleur.
- quality.minimalism : pass ; Checklist exécutée : pas de dépendance ; diagnostics documentés ; contrôleur volumineux signalé ; ~0 ligne suppressible à comportement constant identifiée.
- quality.llm : pass ; Changements expliqués par session (research, validation) ; défauts trouvés par essais réels corrigés sur données ; revue indépendante indisponible (Bridget).
- reliability.observability : pass ; Événements launcher.* sans titre, chemin ni adresse ; diagnostics lastSeen et open_items par comptes ; journaux bornés existants.
- spec.traceability : pass ; FR de 075 à 082 reliés au code et aux tests (validation.md par session) ; limites (clavier, onglets réels, Firefox) écrites.

## Limites

- contrôle non vérifié : security.dependencies
- outil osv-scanner: error

## Minimalisme et responsabilité future

Potentiel minimalisme : ~0 ligne suppressible à comportement constant identifiée ; vigilance sur la taille de TargetModeRuntimeController et sur deux options de diagnostic gardées (--preview-only, --open-items).

Vertus LLM et responsabilité future : charge cognitive en hausse (contrôleur volumineux, huit fonctions), compensée par des types purs testés, des invariants écrits et des validations par session ; volume justifié par les huit demandes ; revue indépendante absente (Bridget refusé), à faire.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
