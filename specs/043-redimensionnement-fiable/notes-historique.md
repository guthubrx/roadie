# Historique AX — résultat et contrat pour le parent

Implémentation terminée sur `session-043-redimensionnement-fiable`, base vérifiée `e86e71b74cdb870f7b7ae6b151e178bcd3303f1d`.
Les compilations, tests Swift, installation et livraison restent au parent. Aucun sous-agent supplémentaire, commit, push ou benchmark.

## Fichiers de ce livrable

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieAX/WrittenFrameRegistry.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieAX/AXWindowEventObserver.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieAXTests/ReactiveTilingAXTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieAXTests/Spec043WrittenFrameHistoryTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieAXTests/Spec043AXEchoTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/043-redimensionnement-fiable/notes-historique.md

Aucun fichier daemon, BSP ou configuration modifié par cet agent. Les modifications concurrentes de ces fichiers restent intactes.

## Décisions et garanties

Le registre conserve l'entrée courante et un historique distinct par fenêtre. L'historique contient au plus 32 cadres individuels, demandés, relus ou acceptés. Chaque cadre porte sa date et sa génération. Une relecture occupe une place comme une demande ; ce ne sont pas 32 triplets. La purge est locale et paresseuse, à l'enregistrement, l'acceptation ou la classification. Un cadre historique est inutilisable dès 1,5 seconde, borne exclue. Une notification ne renouvelle jamais ce délai.

L'entrée courante conserve son comportement existant : cadre demandé, relecture et cadre accepté restent reconnaissables sans expiration. Le délai de 1,5 seconde porte sur les cadres supplémentaires des écritures antérieures. Cela préserve l'API et les tests existants. L'historique ne modifie ni date de dernière écriture, ni génération, ni compteur, ni diagnostic, ni acceptation, ni budget. La fenêtre de réponse applicative reste `LayoutTolerance.echoWindow`, soit 1 seconde. Les recherches parcourent au plus 32 cadres d'une seule fenêtre : coût O(1), mémoire O(32) par fenêtre. `forget` retire entrée et historique. La destruction utilise ce même chemin avant la callback ; la fin d'application et l'arrêt conservent leur nettoyage existant.

L'ancienne paire « classify, puis confirmRefusal » dans l'observateur avait deux verrous distincts. `consumeEcho` regroupe ces opérations sous un verrou. Une notification correspondant à un ancien cadre d'une autre génération ne confirme ni n'efface le refus courant, même si son rectangle correspond aussi à la demande/relecture actuelle. Cette ambiguïté attend une lecture AX fraîche. Une observation datée avant la dernière écriture ne confirme rien.

La lecture système des boutons est `NSEvent.pressedMouseButtons != 0`, injectée dans l'observateur. Pendant l'appui, les notifications de géométrie sont transmises sans absorption ni confirmation de refus. Aucun classement forcé en `.external`, aucune génération et aucune géométrie ne sont créés par l'observateur.

## Interface et raccordement

- Les appels existants à `record`, `entry`, `classify`, `forget`, `pendingRefusals` et `isOverBudget` restent identiques.
- `accept(windowID:frame:at:)` ajoute une date facultative, par défaut `Date()`. Les appels à deux arguments restent valides. Les tests à horloge contrôlée peuvent fournir `at:` pour dater réellement l'acceptation.
- `confirmRefusal(windowID:observed:at:generation:)` ajoute une génération attendue facultative. Les appels actuels restent valides. Le parent peut transmettre la génération capturée **avant** une lecture AX fraîche pour rejeter une confirmation si une nouvelle écriture intervient entre lecture et enregistrement. Cette méthode reste dédiée aux observations fraîches ; une notification ambiguë doit passer par `consumeEcho`.
- `consumeEcho(windowID:observed:now:) -> Bool` absorbe un écho et protège sa confirmation atomiquement. L'observateur l'appelle seulement en l'absence de bouton pressé.
- Initialiseur interne injectable : `AXWindowEventObserver(writtenFrames:mouseButtonsPressed:onEvent:)`. La fermeture `mouseButtonsPressed: () -> Bool` a une valeur système par défaut. Les initialiseurs publics sont inchangés. Deux tests existants injectent `false` pour être indépendants de la souris réelle pendant les tests.

**Aucune nouvelle information obligatoire à transmettre au daemon.** Le chemin existant convient : la callback de l'observateur demande une passe avec la notification `Moved`/`Resized`, classée comme cause interne par `currentGeneration`; le maintainer suspend les écritures pendant l'appui. Au relâchement, `layoutGesture` puis `applyGesture` traitent le geste avant le filtre d'écho de l'arbre. Hors arbre, la liste des redimensionnements issus d'une session de geste reste distincte du filtre des simples changements observés. Conserver cet ordre. Ne pas convertir chaque notification reçue pendant l'appui en nouvelle intention. Le parent possède les corrections des refus et les éventuels contrôles de génération dans le maintainer.

## Tests à exécuter par le parent

Répertoire de travail : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability

Filtre ciblé, dans le créneau Swift sérialisé du parent :

```sh
swift test --filter 'Spec043WrittenFrameHistoryTests|Spec043AXEchoTests|WrittenFrameRegistryTests|AXWindowEventObserverDispatchTests'
```

Les nouveaux tests comprennent 18 fonctions, soit 20 cas avec les deux tests paramétrés déplacement/redimensionnement. Ils couvrent A après B, tolérance géométrique, relecture et acceptation historiques, échéance exacte, absence de prolongation, limite de 32 partagée, budget conservé, oubli et réutilisation d'ID, destruction, ambiguïtés entre générations, confirmation fraîche avec génération attendue, bouton pressé, relâchement et cadre illisible. Tous les nouveaux scénarios utilisent des dates contrôlées et une entrée souris injectée.

Régressions utiles après intégration des autres livrables :

```sh
swift test --filter 'RoadieAXTests|TreeAuthorityTests|TickSchedulerTests|Spec029Resize|Spec043Refusal'
```

Résultat à ce stade : `git diff --check` réussi pour les fichiers de ce livrable. Aucun build ni test Swift exécuté, conformément à la consigne de sérialisation. Aucune preuve visuelle autonome produite : ce livrable change le filtrage AX et doit être validé dans le parcours réel après intégration par le parent.
