# Audit Code V15

Périmètre : /private/tmp/roadie155-audit-source-20261110
Sources : commit 1b08c06d1596f2b38f1a574ac0f918086b0590ee ; mode fix.
Décision : **pass** ; note globale : A. Les notes de qualité par axe sont présentées ci-dessous ; le compteur de pénalités n'est pas une note de qualité.
Contrôles vérifiés : 14/14.

## Notes par axe

Qualité observée = somme des niveaux justifiés / maximum des critères notés. Niveaux ancrés de0 à4, poids figés. Le nombre de défauts ne donne plus la note : leurs pénalités restent un garde-fou. Couverture séparée. Note démontrée = points acquis / maximum de tous les critères applicables ; les inconnus ne rapportent aucun point. Aucun niveau justifié : non noté. Pas de moyenne globale des axes.

| Axe | Qualité observée | Points démontrés /100 | Critères notés | État |
|---|---|---|---|---|
| Sécurité | 75/100 (C) | 75 | 5/5 | Évalué |
| Sécurité IA | 75/100 (C) | 75 | 2/2 | Évalué |
| Fiabilité et exploitation | 56/100 (F) | 56 | 4/4 | Évalué |
| Tests et validation | 65/100 (D) | 65 | 5/5 | Évalué |
| Performance et ressources | 58/100 (F) | 58 | 3/3 | Évalué |
| Complexité algorithmique | 75/100 (C) | 75 | 3/3 | Évalué |
| Qualité du code et des erreurs | 58/100 (F) | 58 | 3/3 | Évalué |
| Architecture et dépendances | 69/100 (D) | 69 | 4/4 | Évalué |
| Responsabilité future et hygiène | 67/100 (D) | 67 | 3/3 | Évalué |
| Minimalisme et frugalité | 67/100 (D) | 67 | 3/3 | Évalué |
| Métier et fidélité des données | 75/100 (C) | 75 | 3/3 | Évalué |
| Traçabilité des exigences | 75/100 (C) | 75 | 2/2 | Évalué |

### Sécurité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Analyse statique et validation des entrées | 3 | Entrées TOML/AX/CLI relues et erreurs testées ; Semgrep Python/YAML complète la compilation Swift. Limite : pas de scanner de sécurité Swift exhaustif. |
| Protection des secrets courants | 3 | Scanner des fichiers courants sans alerte, endpoint sans credentials, données de clic retirées. Pas de test d’accès à un secret. |
| Maîtrise des secrets historiques | 3 | Historique complet analysé, 18 empreintes vérifiées individuellement. Contre-vérification locale déclarée, sans indépendant inventé. |
| Authentification et séparation des droits | 3 | Aucun droit nouveau ni serveur entrant ; routeur local et URL fixe ; absence de données utilisateur dans la requête. |
| Maîtrise des dépendances vulnérables | 3 | Verrou de dépendances inchangé, OSV terminé sans candidat ; notices de licences incluses. Aucun scan dynamique d’exploitation revendiqué. |


### Sécurité IA

| Critère | Niveau /4 | Justification |
|---|---|---|
| Confidentialité et pseudonymisation | 3 | Suppression des positions de clic ; aucune donnée utilisateur envoyée au contrôle de version. Les preuves privées restent hors Git. |
| Permissions des appels externes | 3 | Un seul appel public à la demande, jamais un appel automatique du daemon ; aucune dépense ni credential requis. |
| Résistance aux instructions malveillantes | Non applicable | Le produit modifié ne comporte ni LLM, ni prompt, ni outil piloté par une sortie de modèle. |


### Fiabilité et exploitation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Conservation et rotation des sauvegardes | 3 | Éditeur conserve sa sauvegarde par session ; tests backup et refus sans perte de fichier existants réussis. Archives de preuve vérifiées avant retrait. |
| Reprise des traitements interrompus | 2 | CLI bornée et candidate config atomique ; les scripts préparatoires multi-fichiers ne garantissent pas une transaction globale lors d’un arrêt machine. |
| Continuité pendant une bascule | 2 | Cycle installation/arrêt/reprise testé par commandes simulées ; activation réelle de 0.14.0 reste T053, donc qualification limitée à ce gate code. |
| Restauration après sinistre | 2 | Sauvegarde de configuration et anciens exécutables conservés par procédure ; aucune qualification complète de reprise après sinistre du poste. |


### Tests et validation

| Critère | Niveau /4 | Justification |
|---|---|---|
| Typage des sources et des tests | 3 | Swift 6 compile code et tests ; suite 2549 réussie ; build Release dans runner borné. Aucun warning nouveau masqué. |
| Analyse de style et erreurs statiques | 2 | Pas de lint Swift projet. Compilation stricte, diff --check, syntaxe bash/zsh et analyse Python/YAML ; warnings de tests préexistants connus. |
| Régressions et cas limites | 3 | Cas mixtes, reset, types optionnels, vrais fichiers, HTTP/erreur/timeout et dirty non suivi ; suite globale et scripts réussis. |
| Qualification du runtime livré | 2 | Identité testée sur bundle temporaire ; runtime de 0.14.0 à qualifier en livraison. Aucune preuve runtime nouvelle anticipée. |
| Tests interface et intégration des données | 3 | Écriture réelle SettingsService et rechargement TOML testés, comparaison exacte de vingt modifications ; pas de nouvelle vue graphique. |


### Performance et ressources

| Critère | Niveau /4 | Justification |
|---|---|---|
| Admission et saturation des demandes | Non applicable | Aucune file, admission ou ordonnanceur ajouté : une commande CLI indépendante, sans charge du daemon. |
| Budget mémoire | 2 | Session libérée et durée bornée ; réponse GitHub reçue en mémoire sans plafond en octets. Pas de benchmark mémoire revendiqué. |
| Délais, annulation et libération | 3 | Timeout natif et arrêt du transport observés ; garde externe annule ; session interne invalidée. Requêtes réussies et HTTP 403 testées. |
| Mesures représentatives de latence et charge | 2 | Un appel réel 0,320 s et délais testés, mais aucun benchmark représentatif de charge ni p95 du produit. |


### Complexité algorithmique

| Critère | Niveau /4 | Justification |
|---|---|---|
| Complexité des points d’entrée | 3 | Décodage sur schéma et complétion sur table unique ; édition linéaire dans le fichier, alias en dictionnaire. |
| Bornes des parcours et allocations | 3 | Sous-commandes bornées et filtre des mots zsh ; aucun parcours ajouté par fenêtre ou tick. Corps réseau sans plafond classé dans mémoire. |
| Coût des accès et écritures de données | 3 | Deux passages de texte lors d’une migration, un seul remplacement atomique après validation ; aucun N+1 ni accès réseau en boucle. |


### Qualité du code et des erreurs

| Critère | Niveau /4 | Justification |
|---|---|---|
| Gestion des refus et messages utilisateur | 3 | Messages FR/EN, erreurs explicites HTTP/réseau/JSON, codes 0/1/64, validation TOML garde ses chemins. |
| Gestion des erreurs partielles | 2 | Erreurs d’édition empêchent la mutation et anciens cadres conservés par logique non modifiée. Limite documentée des outils multi-fichiers préparatoires. |
| Ergonomie des parcours concernés | 2 | Réglages internes et catégories stables, docs FR/EN alignées ; parcours macOS Open Anyway non exercé sur poste neuf. |


### Architecture et dépendances

| Critère | Niveau /4 | Justification |
|---|---|---|
| Frontières et résolution des dépendances | 3 | Modèle interne et catalogue uniques ; helpers existants réutilisés, logique de compatibilité aux frontières de lecture/édition. |
| Maîtrise des cycles | 3 | Graphes de modules inchangés, import Core déjà dépendance du daemon ; compilation vérifie résolution et aucun cycle nouveau. |
| Séparation construction et exécution | 3 | Version unique, commit dans Info.plist, pas de Git requis à l’exécution ; scripts install/DMG relus et dirty vérifié. |
| Assemblages et dépendances dynamiques | 2 | Aucun nouvel assemblage dynamique ; binaires arm64 et dépendances système existantes. Intel non qualifié, hors cible. |


### Responsabilité future et hygiène

| Critère | Niveau /4 | Justification |
|---|---|---|
| Invariants et compromis expliqués | 3 | ADR 032 explique priorité, migration progressive, ancienne version et contrainte TOMLKit ; observations de données avant correction répétée. |
| Périmètre et maintenabilité du changement | 3 | Périmètre 155 et décisions D1/D2/D3/D8 respectés ; 51 tâches de développement, aucun paquet ni nouvelle interface. |
| Revue contradictoire et responsabilité | 2 | Contre-revue du plan reçue BLOCKED et traitée ; nouvelle revue du commit source à demander après audit pour disposer de la vue immuable requise. |


### Minimalisme et frugalité

| Critère | Niveau /4 | Justification |
|---|---|---|
| Dépendances nécessaires en exploitation | 3 | Foundation et TOMLKit existants couvrent le besoin ; aucun paquet ajouté et pas de second type de configuration. |
| Poids et ressources justifiés | 3 | 21 diaporamas retirés avec archive et empreintes, 26 images utiles conservées ; aucun gain physique APFS ni CPU inventé. |
| Code mort et simplifications possibles | 2 | Deux émissions supprimées et extraction mécanique contrôlée ; potentiel de code mort global non mesuré, pas de suppression hors périmètre. |


### Métier et fidélité des données

| Critère | Niveau /4 | Justification |
|---|---|---|
| Fidélité des données lues | 3 | Comparaison ancienne/nouvelle forme, valeurs héritées, override par clé et tableaux remplacés ; types invalides gardent une erreur. |
| Cohérence et idempotence des versions | 3 | Version et identité du bundle testées, statut ancien compatible et dirty comprend les nouveaux fichiers ; aucun update installé automatiquement. |
| Conformité aux règles et données de référence | 3 | Apache officielle inchangée, signature existante et CI manuelle conservées, consentement réseau explicite ; décisions enregistrées. |


### Traçabilité des exigences

| Critère | Niveau /4 | Justification |
|---|---|---|
| Lien constats, corrections et preuves | 3 | Commandes, SHA, code, tests et réfutations historiques reliés ; aucune validation attribuée à une opération non exécutée. |
| Couverture des exigences obligatoires | 3 | Toutes les exigences du code ont une réalisation et preuve ; livraison et runtime qualifiés séparément en T053 conformément au périmètre figé. |



## Risque constaté

{"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0, "candidates": 0, "suppressed": 0}

- [fixed] MEDIUM : GitHub Actions step uses a mutable tag or branch reference. Tags and branch names can be silently repointed by the action owner, enabling supply-chain attacks — as seen in the trivy-action and kics-github-action compromises. Pin the reference to a full 40-character commit SHA instead, e.g. `uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1ea18608`.
  /private/tmp/roadie155-audit-source-20261110/specs/155-consolidation-projet/gabarits/tests.yml:16 ; 0e95e6f75ebd4c5eb23a
  Gabarit de recette avec tag mobile ; workflow réel déjà épinglé. Gabarit et recette alignés sur le même SHA vérifié.
  Action : Référence checkout épinglée au SHA complet dans le gabarit et la recette.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:87 ; e4d6229997ab3a9cbe8e
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:88 ; 993aca314f1268ce2457
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:89 ; 2a7806115c53dba1e732
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:318 ; b39cd68a4e58034f8678
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:479 ; 2332686cf392e0b73370
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map-final.json:511 ; a8f8e421ece500496d7d
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:87 ; 0311a68ab585f701597c
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:88 ; 7b210804f9350d7d1440
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:89 ; 3645bdadf2b267ed72d3
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:318 ; d8b5506b5949dc10010c
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:479 ; a6021ecc62481641be02
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-transfert145-01/notes/scanner-snapshot-map.json:511 ; 46a2788ad1a2b672228d
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:90 ; 740f5b0b6f6a3238dd02
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:91 ; a14b57139fec97d8ebe0
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:92 ; c3cfce1b5d79d4198017
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:321 ; a4165569cb7a742ce4c4
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:482 ; db305b4e4682dd3abc8a
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.
- [refuted] HIGH : Empreinte SHA-256 de fichier source, pas un identifiant d’accès
  /private/tmp/roadie155-audit-source-20261110/audits/2026-10-31/session-2026-10-31-effets144-01/notes/scanner-snapshot-map.json:514 ; 04a021e30000d808538b
  Entrée JSON de 64 caractères hexadécimaux ; SHA256(git show COMMIT:fichier nommé) égale exactement la valeur signalée. Vérification individuelle des 18 entrées.
  Action : Aucune révocation ni modification de règle : faux positif démontré par les octets de chaque fichier dans le commit d’origine.

## Vérification réalisée

- security.static : pass ; completed, 0 candidat(s). 
- security.secrets : pass ; completed, 0 candidat(s). 
- security.history : pass ; Historique Git complet jusqu’au commit figé ; 18 candidats réfutés par égalité SHA-256 avec chaque fichier source historique. Aucun identifiant d’accès trouvé.
- security.dependencies : pass ; completed, 0 candidat(s). 
- security.authorization : pass ; CLI locale, endpoint HTTPS GitHub fixe, aucune donnée utilisateur ni jeton transmis ; isDaemonRouted exclut update. Signature et permissions existantes conservées par procédure.
- correctness.logic : pass ; Priorité par clé, types, listes, reset, identité et codes de retour lus dans les appelants ; 26 tests ciblés et suite complète réussis.
- correctness.concurrency : pass ; ResultBox protège la réponse avec NSLock ; timeout annule la tâche et session privée invalidée. SettingsService sérialise les écritures et valide le candidat avant remplacement.
- performance.complexity : pass ; Parcours de clés et de texte linéaires ; dictionnaire d’alias réutilisé ; une requête au plus, attente bornée. Aucun gain de performance revendiqué.
- tests.regression : pass ; 2549 tests / 388 suites, code 0 après recontrôle du cas intermittent ; 29 scripts, dont dirty suivi/non suivi. Build Release qualifié par reçu custom terminé.
- architecture.dependencies : pass ; Aucun paquet ajouté ; même modèle TargetModeConfig et modules existants. Initialiseur à conteneurs nécessaire à TOMLKit ; catalogue/éditeur/routeur/build réutilisés.
- quality.minimalism : pass ; Pas de wrapper de service, ni catalogue doublé, ni dépendance ; deux événements supprimés, extraction mécanique, anciennes preuves retirées après archive.
- quality.llm : pass ; Invariants et compromis explicites dans ADR 032 ; observations réelles après échecs ; sorties de tests et limites séparées des opérations de livraison futures.
- reliability.observability : pass ; Erreurs HTTP/décodage/timeout affichées avec code 1, aide avec 64 ; aucune boucle automatique. Les coordonnées des clics ne sont plus émises. Diagnostic du build facultatif compatible avec ancien statut.
- spec.traceability : pass ; 30 exigences reliées aux sources et aux contrôles ; audit du code et préparation de publication uniquement. Les opérations T053 sont un gate distinct sans succès anticipé.

## Limites

Aucune limite déclarée pour les contrôles définis. Cela ne prouve pas l'absence de tout défaut.

## Minimalisme et responsabilité future

Potentiel minimalisme : non mesuré globalement. Sur le périmètre : deux émissions retirées, un type extrait sans changement, aucun paquet ni modèle de configuration doublé ; limites et volumes documentés dans notes/complexite-minimalisme.md.

Invariants, reprise ancienne version et panne TOMLKit explicités dans ADR 032 ; preuves des échecs et succès conservées. Revue indépendante du plan traitée ; revue du commit et activation réelle restent gates de livraison distincts.

## Tendance

Comparer seulement des périmètres, contrôles et conditions équivalents.
