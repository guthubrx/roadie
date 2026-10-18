# Audit Code V15

Périmètre : /private/tmp/roadie-audit-049
Sources : commit 3dd5563b24b29ca83312e2c15f881ad4787d51c0 ; mode readonly.
Décision : **inconclusive** ; note globale : N/A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 14/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 63/100 (D) | 63 | 4/4 | Provisoire |
| Sécurité IA | Non noté | — | 0/0 | Non applicable |
| Fiabilité et exploitation | Non noté | — | 0/0 | Non applicable |
| Tests et validation | 63/100 (D) | 50 | 4/5 | Provisoire |
| Performance et ressources | 75/100 (C) | 75 | 2/2 | Évalué |
| Complexité algorithmique | 75/100 (C) | 75 | 3/3 | Évalué |
| Qualité du code et des erreurs | 63/100 (D) | 42 | 2/3 | Provisoire |
| Architecture et dépendances | 69/100 (D) | 69 | 4/4 | Évalué |
| Responsabilité future et hygiène | 58/100 (F) | 58 | 3/3 | Évalué |
| Minimalisme et frugalité | 75/100 (C) | 75 | 3/3 | Évalué |
| Métier et fidélité des données | 63/100 (D) | 63 | 2/2 | Évalué |
| Traçabilité des exigences | 63/100 (D) | 63 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 2 | Semgrep exécuté, une seule règle Swift ; entrée = préférences locales relues à la main. Niveau 3 : règles Swift ciblées. |
| Protection des secrets courants | 3 | Adaptateur gitleaks : 7,75 Mo sans fuite. Niveau 4 : contrôle en CI. |
| Maîtrise des secrets historiques | 2 | Historique v0.4.0..3dd5563b (71 commits) sans fuite, option A ; historique antérieur non analysé. Niveau 3 : historique complet. |
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
| Reprise des traitements interrompus | Non applicable | Contrôle sans état ni traitement interruptible : rien à reprendre. |
| Continuité pendant une bascule | Non applicable | Aucune bascule dans le périmètre. |
| Restauration après sinistre | Non applicable | Aucune restauration après sinistre dans le périmètre. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Compilation Swift 6 sans erreur ni avertissement dans le diff. Niveau 4 : Thread Sanitizer. |
| Analyse de style et erreurs statiques | 2 | Pas de linter dans le projet. Niveau 3 : linter configuré. |
| Régressions et cas limites | 3 | Cas absents, explicites, ok, warn et jamais fail testés avec préférences injectées. Niveau 4 : valeurs non booléennes et lecteur réel. |
| Qualification du runtime livré | Non vérifié | Binaire installé non exécuté (installation interdite) ; seules les préférences réelles ont été lues. |
| Tests interface et intégration des données | 2 | Pas de test de bout en bout de daemon health avec le nouveau contrôle. Niveau 3 : test du routeur CLI. |

- Contrôle non vérifié : axes.tests.04
- 1 critère(s) sans niveau de qualité justifié

### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | Non applicable | Aucune file ni admission de demandes dans le périmètre. |
| Budget mémoire | 3 | Aucune allocation durable ; liste fixe de quatre réglages. Niveau 4 : mesure. |
| Délais, annulation et libération | 3 | Lectures CFPreferences synchrones et locales, sans attente réseau. Niveau 4 : délai mesuré. |
| Mesures représentatives de latence et charge | Non applicable | Aucune exigence de latence ou de charge pour ce contrôle de diagnostic. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Point d'entrée O(r), r = 4, annoté. Niveau 4 : non nécessaire au-delà. |
| Bornes des parcours et allocations | 3 | Parcours borné par la liste fixe. Niveau 4 : borne testée. |
| Coût des accès et écritures de données | 3 | Quatre lectures de préférences par appel, sans écriture. Niveau 4 : mesure. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 2 | Message clair avec chemin dans Réglages Système, en français seulement. Niveau 3 : libellés localisés. |
| Gestion des erreurs partielles | 3 | Valeur illisible ou d'un autre type : défaut de la version, sans erreur. Niveau 4 : test dédié. |
| Ergonomie des parcours concernés | Non vérifié | Sortie texte de roadie query health non observée sur le binaire installé. |

- Contrôle non vérifié : axes.quality.03
- 1 critère(s) sans niveau de qualité justifié

### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Contrôle ajouté dans DaemonHealthService existant, lecteur injecté. Niveau 4 : règle vérifiée par outil. |
| Maîtrise des cycles | 2 | Aucun cycle d'après la lecture ; pas d'outil de graphe Swift. Niveau 3 : graphe vérifié. |
| Séparation construction et exécution | 3 | Dépendances résolues à la construction (lecteur, version). Niveau 4 : test de composition. |
| Assemblages et dépendances dynamiques | 3 | Défauts de l'initialiseur sans effet sur les cinq appelants existants. Niveau 4 : test par appelant. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | Défauts macOS et réglages écartés expliqués dans research.md. Niveau 4 : source Apple. |
| Périmètre et maintenabilité du changement | 3 | Un fichier source, une fonction, docs et CHANGELOG. Niveau 4 : réversibilité testée. |
| Revue contradictoire et responsabilité | 1 | Aucune revue ni validation consignée pour la 049 (T004 ouverte) ; cet audit n'est pas indépendant. Niveau 2 : revue externe consignée. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Aucune dépendance ajoutée. Niveau 4 : inventaire mesuré. |
| Poids et ressources justifiés | 3 | Coût négligeable, appel seulement sur demande de santé. Niveau 4 : mesure. |
| Code mort et simplifications possibles | 3 | Environ 1 ligne inatteignable. Niveau 4 : outil de code mort. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Préférences lues telles quelles ; préférences réelles cohérentes avec research.md. Niveau 4 : vérification sur plusieurs versions de macOS. |
| Cohérence et idempotence des versions | Non applicable | Aucune donnée versionnée ni écriture idempotente dans le périmètre. |
| Conformité aux règles et données de référence | 2 | Défauts macOS d'une clé absente déduits de Réglages Système, non documentés par Apple. Niveau 3 : référence vérifiable. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Constat relié au critère, aux tâches et à l'observation runtime. Niveau 4 : validation exécutée. |
| Couverture des exigences obligatoires | 2 | Cinq exigences vérifiées ; critère d'installation non vérifié. Niveau 3 : validation consignée. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 1, "info": 0, "total": 1, "candidates": 0, "suppressed": 0}

- [confirmed] LOW : Critère de réussite non vérifié : aucune validation consignée
  /private/tmp/roadie-audit-049/specs/049-reglages-macos/tasks.md:6 ; 4b2a4e5ffc40eec8d8a4
  La spec exige que roadie query health installé renvoie ok chez l'utilisateur ; T004 est ouverte et le commit ne contient ni validation.md, ni revue, ni résultat d'installation. Les préférences réelles (toutes à 0) laissent attendre ok, sans exécution du binaire.
  Action : Exécuter la suite, installer, consigner roadie query health dans validation.md et cocher T004, ou réduire le critère.

## Vérification réalisée

- security.static : pass ; Semgrep : 163 règles figées sur les 10 fichiers sélectionnés, 0 résultat. Une seule règle Swift : l'analyse manuelle porte le contrôle.
- security.secrets : pass ; Adaptateur gitleaks : ~7,75 Mo analysés, aucune fuite ; audits/ exclu par la configuration figée.
- security.history : pass ; Décision utilisateur du 18/10/2026 (option A) : l'historique complet dépasse le plafond de 300 s ; plage analysée v0.4.0 (5ab0ab95)..3dd5563b, 71 commits, ~3,04 Mo, aucune fuite (gitleaks 8.30.1, --redact). Exécuté en --tool custom : le runner refuse --command avec --tool gitleaks-history. Limite connue : historique antérieur à v0.4.0 non analysé dans cette session.
- security.dependencies : pass ; OSV-Scanner (adaptateur) : Package.resolved, 1 paquet, aucun avis ; manifestes inchangés.
- security.authorization : pass ; Lecture seule de préférences locales ; aucune écriture de réglage (recherche vide), aucun réseau, aucune frontière de confiance modifiée.
- correctness.logic : pass ; Contrôle warn/ok, jamais fail ; valeur explicite prioritaire ; défaut par version ; aucun consommateur de warn. F1 : validation absente.
- correctness.concurrency : pass ; Fonction pure du lecteur injecté et de la version ; aucun état partagé ajouté.
- performance.complexity : pass ; O(r), r = 4 réglages, annoté ; quatre lectures CFPreferences par appel de santé.
- tests.regression : pass ; swift build --build-tests puis swift test : 1 736 tests / 206 suites verts, dont 5 tests Spec049 ; tests instables connus réussis.
- architecture.dependencies : pass ; Injection par l'initialiseur avec défauts ; aucune dépendance ni cycle ajoutés.
- quality.minimalism : pass ; Checklist exécutée : ~1 ligne inatteignable (cas Bool après NSNumber) ; aucune dépendance ni changement hors périmètre.
- quality.llm : pass ; Changement petit et explicable, limites écrites, docs FR/EN ; aucune validation ni revue consignée (F1) ; audit non indépendant.
- reliability.observability : pass ; Contrôle visible dans daemon health --json ; aucun journal ni ressource ajoutés.
- spec.traceability : pass ; R1 à R5 implémentées ; critère « santé installée ok » non vérifié (F1), préférences réelles à 0 observées.

## Limites

- outil non exécuté : gitleaks-history
- sous-contrôle d'axe non vérifié : axes.tests.04
- sous-contrôle d'axe non vérifié : axes.quality.03

## Minimalisme et responsabilité future

Potentiel minimalisme : ~1 ligne suppressible à comportement constant (cas `value as? Bool` inatteignable après `as? NSNumber` pour une valeur CFPreferences) ; méthode : relecture ligne à ligne du diff source, tests exclus ; aucune dépendance, abstraction ou état dérivé superflu.

Vertus LLM et responsabilité future : charge cognitive faible (un contrôle pur, injecté, documenté) ; volume justifié ; défauts macOS et limites écrits ; aucune revue ni validation consignée (F1) ; message en français seulement ; cet audit n'est pas indépendant.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
