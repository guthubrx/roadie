# Audit Code V15

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability
Sources : commit d32105c863953a77d0f76ec50b4a571b3f80d3d2 ; mode fix.
Décision : **inconclusive** ; note globale : N/A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 12/13.

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



## Risque constaté

{"critical": 0, "high": 0, "medium": 2, "low": 0, "info": 0, "total": 2, "candidates": 0, "suppressed": 0}

- [fixed] LOW : Statut d'enregistrement mémorisé conservé après l'arrêt du watcher
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailController.swift:138 ; 9619f4d1404af7da63b9
  stop() arrête le watcher recording_status sans remettre recordingStatusDirty à vrai ; RailFileWatcher.start() reprend l'empreinte courante, donc un changement pendant l'arrêt n'est jamais signalé. Défaut latent : stop() n'est appelé qu'à l'arrêt du daemon aujourd'hui, mais son contrat autorise un redémarrage.
  Action : Remettre recordingStatusCache à nil et recordingStatusDirty à vrai dans stop().
- [confirmed] MEDIUM : R3 partielle : la minuterie du rail relit et décode stages.json et rail.json chaque seconde
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailController.swift:932 ; 62220d6c2a827922c88d
  R3 interdit toute relecture de fichier inchangé par la minuterie du rail. store.state() et railRuntimeStateStore.load() lisent et décodent le disque à chaque tick, sans cache (JSONPersistence.load). Seul recording.json est mémorisé. Coût non mesuré.
  Action : Mettre en cache par empreinte (modèle RailSettingsCache) puis mesurer, ou réduire le texte de R3 et le documenter dans validation.md.
- [fixed] LOW : Plan, tâches et recherche décrivent quietMaxAge = 1 s, contredits par le code
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/048-consommation-repos/plan.md:7 ; 4c4f52fc002aae4b9535
  Le code utilise allowQuietReuse et un plafond égal au filet du tiler (2 s), activé seulement avec les événements en direct ; plan.md, tasks.md T002 et research.md décrivent encore une API quietMaxAge et 1 s.
  Action : Aligner le texte sur le code et l'ADR 015 en gardant l'historique.
- [confirmed] MEDIUM : Variante hors diff : les poignées décodent stages.json toutes les 150 ms au repos
  /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DividerResizeRuntime.swift:167 ; 8d3b5fedd4b3ec996f1a
  Minuterie 0,15 s (l. 37) -> refresh -> readerSnapshot -> update(snapshot:) qui appelle effectiveStageStore.state() (l. 167) : lecture et décodage d'environ 58 Ko à chaque tick quand les poignées sont actives. Antérieur à 048. Coût non mesuré ; la nécessité d'une lecture fraîche plutôt que snapshot.state n'est pas établie.
  Action : Session 051 : réutiliser snapshot.state ou un cache par empreinte, puis mesurer.

## Vérification réalisée

- security.static : pass ; Semgrep 1.181.0 : 24 règles sur les 25 fichiers sélectionnés, 0 résultat. Swift n'a qu'une règle (9 fichiers) : la couverture statique Swift est quasi nulle ; l'analyse manuelle des entrées (fichiers locaux, ScreenCaptureKit) est dans notes/axes.md.
- security.secrets : pass ; L'adaptateur gitleaks a analysé 0 octet (exclusion figée .worktrees/ sur chemin absolu). Contrôle réel : gitleaks dir . avec la même configuration figée, 218 Mo analysés, aucune fuite ; fichiers > 5 Mo de .build ignorés.
- security.history : unknown ; gitleaks git interrompu deux fois au plafond de 300 s de la politique (--seconds 900 ramené à 300). Aucun commit dans le périmètre (HEAD = base d32105c8), mais l'historique n'est pas vérifié.
- security.dependencies : not_applicable ; Le diff 048 ne modifie ni Package.swift ni Package.resolved (git diff --stat d32105c8 vide) et n'ajoute aucune dépendance. L'adaptateur OSV ne voit pas le worktree (ignoré par le .gitignore du dépôt parent). Complément : osv-scanner --lockfile Package.resolved, TOMLKit 0.6.0, aucun avis.
- security.authorization : pass ; Aucune authentification, autorisation ni frontière de confiance modifiée : fichiers d'état locaux, permission Screen Recording vérifiée avant capture (inchangé), script de mesure sans shell.
- correctness.logic : pass ; Invariants A-01, C-01, C-02, C-03 vérifiés dans les appelants et fonctions appelées (contexte.md). F1 corrigé ; F2 (R3 partielle) et F4 (variante hors diff) restent ouverts, MEDIUM.
- correctness.concurrency : pass ; Génération et plafond sous NSLock ; lecteurs et ordonnanceur sur MainActor ; génération lue au départ du relevé (producteur l. 351, lecteur l. 253) ; un seul lot de capture (inFlight) ; ordonnancements décrits dans notes/axes.md.
- performance.complexity : pass ; Fonctions ajoutées O(1), O(k), O(w), O(c x m), bornes et annotations présentes ; aucune boucle imbriquée ni N+1. I/O périodiques restantes : F2 (1 s) et F4 (0,15 s).
- tests.regression : pass ; swift build --build-tests puis swift test : 1 721 tests / 203 suites verts en révision 1, dont Spec048QuietReaderTests, Spec048RailTests, Spec048RecordingStatusTests ; les deux tests instables connus ont réussi. Manques listés dans notes/axes.md.
- architecture.dependencies : pass ; Aucune dépendance de module ajoutée ; câblage dans la racine de composition (main.swift) ; pas de cycle introduit (lecture des imports et des appels ; pas d'outil de graphe pour Swift).
- quality.minimalism : pass ; Checklist exécutée : ~2 lignes suppressibles (retour Bool et @discardableResult de updateThumbnails), aucune dépendance ni abstraction prématurée, aucun changement hors périmètre.
- quality.llm : pass ; Charge cognitive réduite par une règle unique documentée (ADR 015) ; invariants explicables ; volume justifié par la mesure ; dérive documentaire F3 corrigée ; audit non indépendant.
- reliability.observability : pass ; Aucun journal sensible ajouté, aucune file ni retry sans borne (absence 5 s, plafond = filet). Recommandation INFO : compteur des réutilisations silencieuses et des énumérations SCK.
- spec.traceability : pass ; R1 à R5 vérifiées une à une (spec-matrice.md) : R1, R2, R4, R5 implémentées ; R3 partielle (F2). Plan, tâches et recherche réalignés sur le code (F3).

## Limites

- contrôle non vérifié : security.history
- outil gitleaks-history: timeout
- sous-contrôle d'axe non vérifié : axes.security.03
- sous-contrôle d'axe non vérifié : axes.tests.04
- sous-contrôle d'axe non vérifié : axes.performance.04
- sous-contrôle d'axe non vérifié : axes.quality.03

## Minimalisme et responsabilité future

Potentiel minimalisme : ~2 lignes suppressibles à comportement constant (retour Bool et @discardableResult de StageCardView.updateThumbnails, utilisés par un seul test) ; méthode : relecture ligne à ligne du diff source, tests exclus ; aucune dépendance, abstraction ou état dérivé superflu.

Vertus LLM et responsabilité future : charge cognitive réduite (une règle documentée par l'ADR 015, invariants explicables) ; volume justifié par une mesure avant/après ; abstractions avec usage réel ; dérive documentaire (F3) corrigée ; R3 annoncée sans réserve alors que partielle (F2) ; revue par un autre modèle documentée, cet audit n'est pas indépendant.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
