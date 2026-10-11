# Recherche : Tiling réactif façon yabai

**Date** : 2026-10-11
**Sources** :
- journal réel `~/.roadies/events.jsonl` ;
- code de yabai `/path/to/yabai/src` (commit `f17ef88`) ;
- code de Roadie (branche `017-reactive-tiling`) ;
- trois analyses de code et une mesure de référence, faites le 2026-10-11.

Notation : **[L]** = lu dans le code ou le journal ; **[D]** = déduit.

## Mesure de référence (Article XXII)

Outil : `scripts/measure-layout-reactivity`. Les horodatages du journal sont à la seconde près, donc les durées sont à ±1 s.

| Indicateur | Journal complet (59 épisodes avec placement) | Depuis 2026-10-10T23:49:30Z (18 épisodes) |
|---|---|---|
| Temps jusqu'à stabilité, médiane / p90 / max | 1 / 6 / 11 s | 1 / 7 / 9 s |
| Passes, médiane / p90 / max | 1 / 6 / 11 | 1,5 / 7 / 10 |
| Épisodes en une seule passe | 31 / 59 | 9 / 18 |
| Épisodes avec attente de stabilisation | 37 / 59 | 12 / 18 |
| `live_tick.latencyMs`, médiane / p90 | 15,9 / 16,1 ms | 73,6 / 108,7 ms |
| `live_tick.durationMs`, médiane / p90 | 35,6 / 61,1 ms | 13,9 / 54,3 ms |

Cas typique : sortie de plein écran de T3 Code à 23:56:07. Détection en 73 ms, attente de 2 s, puis 7 passes de 23:56:10 à 23:56:13. Le refus de taille porte sur une demande de 940x409, alors que l'application exige une hauteur minimale de 620 [L].

## R1 - Un seul moteur à arbre ; `mutableBsp` devient un alias

**Décision** : `spatialBsp` devient l'unique moteur à arbre. Les valeurs `mutableBsp` et `yabai` sont lues comme `spatialBsp`, aussi bien dans la config que dans `stages.json`. Le code propre à `mutableBsp` est supprimé.

**Raison** :
- `BSPTree` et ses opérations existent et sont testées (`Sources/RoadieTiler/BSPTree.swift`, `BSPTreeTests`, `BSPTreeMutationTests`) [L].
- `mutableBsp` est par nature un moteur sans état qui relit la géométrie (`MutableBSPLayoutStrategy.swift:94-206`). Lui greffer un arbre reviendrait à créer un deuxième moteur à arbre, contraire à l'Article XIX [D].

**Alternatives rejetées** :
- Ajouter un arbre à `mutableBsp` : doublon de `spatialBsp`.
- Garder les deux modes : double maintenance, et la lenteur resterait pour le mode par défaut de l'utilisateur.

**Migration** :
- Supprimer le cas `mutableBsp` de l'enum sans précaution est dangereux. Une valeur inconnue fait échouer tout le décodage de `stages.json`, qui passe alors en `loadFailure` (`StageStore.swift:164-176`) [L].
- Le décodage doit donc traduire les anciennes valeurs, puis l'écriture enregistre `spatialBsp`.
- Une stage migrée qui a des fenêtres mais un arbre vide ou périmé reçoit un arbre initial, construit une seule fois à partir de la géométrie actuelle (détection des coupes nettes). Cela évite le saut au premier démarrage.
- Une copie de sauvegarde de `stages.json` est faite avant la première écriture migrée.
- État réel de l'utilisateur : 52 stages `mutableBsp`, dont 5 avec des fenêtres [L].

## R2 - L'arbre fait foi

**Décision** : pour les modes à arbre, la disposition se calcule uniquement depuis l'arbre.
- Les intents de disposition ne servent plus qu'au marqueur de zoom (`zoomedWindowID`).
- `persistCurrentLayoutIntents` et `persistLayoutIntent` ne s'appliquent plus aux modes à arbre.
- La comparaison « à refaire » se fait contre le dernier plan appliqué ou la frame acceptée (R9), et non contre la relecture.

**Raison** : trois portes de côté remettent aujourd'hui de la géométrie dans le calcul [L] :
- intents prioritaires sur l'arbre (`DaemonSnapshot.swift:990-1016`) ;
- réparation des refus par la logique `mutableBsp` (`LayoutMaintainer.swift:1477`) ;
- exclusion des fenêtres qui refusent de grandir, ce qui retire leur feuille de l'arbre, puis la réinsère : la structure oscille (`LayoutMaintainer.swift:1165-1193` et `DaemonSnapshot.swift:1384`).

**Alternative rejetée** : garder les intents comme couche au-dessus de l'arbre. Deux sources de vérité, c'est la cause du tâtonnement.

## R3 - Sens de coupe selon la feuille

**Décision** : une nouvelle fenêtre coupe la feuille active selon la dimension dominante de cette feuille. C'est le `split_type auto` de yabai (`view.c:148`).

**Raison** : aujourd'hui le sens suit la forme de l'écran (`DaemonSnapshot.swift:1292, 1332` vers `BSPTree.swift:124`). Sur un écran paysage, on obtient des colonnes de 1/2, 1/4, 1/8, ce qui viole l'EF-004 de la SPEC-013 [L].

## R4 - Refus de taille : une seule nouvelle tentative, puis acceptation

**Décision** :
- Au premier refus, la taille minimale observée est mémorisée en mémoire.
- Le ratio du split parent est ajusté une seule fois pour la respecter, et seul ce sous-arbre est réécrit.
- La taille obtenue est ensuite acceptée (enregistrée comme « frame acceptée », R6).
- La structure de l'arbre ne change jamais à cause d'un refus.
- L'isolement des scopes infaisables (`LayoutMaintainer.swift:1508-1630`) reste en dernier recours.

**Raison** : yabai fait au plus une nouvelle écriture du nœud, puis accepte (`event_loop.c:805-822`) [L]. Roadie mémorise le refus 30 s et relance des passes (`LayoutMaintainer.swift:1139-1142, 1328-1336, 2976-2986`) [L].

## R5 - Ordonnanceur événementiel

**Décision** : un ordonnanceur unique sur le thread principal (`TickScheduler`, `@MainActor`) remplace la logique de `main.swift:314-356`. Il :
- ne perd aucun événement ;
- garde l'échéance la plus proche ;
- regroupe pendant 15 ms (création, destruction, fin de geste, changement de bureau) ou 30 ms (déplacement, redimensionnement) ;
- ne fait aucun tick tant qu'un bouton de souris est enfoncé, et en fait un au relâchement ;
- enchaîne immédiatement un tick de suite quand une passe a agi, au plus 3 par épisode ;
- arme un minuteur unique sur la prochaine échéance interne (`LayoutMaintainer.nextDeadline()`).

Le minuteur périodique devient un filet de sécurité à 2 s.

**Prérequis** : les durées deviennent absolues. `TickDuration.seconds = max(minimum, interval × ticks)` (`LayoutTolerance.swift:61-82`) ferait passer, avec un minuteur de 2 s, la stabilisation à 8 s et la dérive d'écran à 32 s [L].

**Notifications ajoutées** :
- `kAXWindowMovedNotification` et `kAXWindowResizedNotification` au niveau de l'application, comme yabai (`application.h:57-66`) ;
- NSWorkspace : `activeSpaceDidChange`, `didActivateApplication`, `didHide`, `didUnhide` ;
- moniteur NSEvent : `leftMouseUp`.

**Corrections** :
- La règle des 200 ms abandonne aujourd'hui les événements (`main.swift:332`) [L].
- Le cache AX est vidé pour toutes les applications à chaque création ou destruction (`AXWindowEventObserver.swift:107-109`). Il le sera désormais par pid.

**Alternative rejetée** : un thread dédié comme yabai. Le thread principal est déjà la file sérielle unique : observateurs AX, AppKit, socket CLI (`CommandSocketServer.swift:176`). En Swift 6 strict, isoler `LayoutMaintainer` et `SnapshotService` dans un acteur coûterait cher, pour un gain faible : un tick dure 7 à 30 ms [D].

## R6 - Registre des frames écrites et reconnaissance des gestes

**Décision** : un registre, partagé par tout le processus, est placé au point unique d'écriture AX (`AXWindowFrameWriter.setFrames`). Il garde pour chaque fenêtre : la frame demandée, la frame relue, la frame acceptée et l'instant. Une frame observée est classée ainsi :
- **écho** : proche de la frame demandée, relue ou acceptée (tolérance unique, R9). Elle est ignorée, sans limite de temps.
- **réponse de l'application** : différente, moins de 1 s après l'écriture, sans clic entre-temps. Elle est acceptée sans propagation.
- **geste manuel** : un clic a eu lieu depuis l'écriture, ou aucune écriture récente. L'arbre adopte le ratio au relâchement : la frontière (fence) entre la fenêtre et sa voisine, dans le sens du geste.

**Raison** :
- yabai reconnaît les gestes par la souris : frame au clic, comparaison au relâchement (`event_loop.c:1117-1228`) [L].
- Roadie compare à la relecture faite juste après l'écriture (`LayoutMaintainer.swift:452, 1878-1885`), avec un seuil de 16 pt. Une application qui termine son redimensionnement plus tard passe donc pour un geste [L].
- Le journal le confirme : 13 « gestes » sur 33 arrivent moins de 1 s après un placement de Roadie [L].

**Limite assumée** : un ancrage au clavier par un outil tiers moins de 1 s après une écriture est classé comme réponse de l'application. Ce cas est rare et il est journalisé.

## R7 - Stabilisation par période calme et garde de transition de bureau

**Décision** :
- La stabilisation d'un scope dure « 200 ms sans nouveau changement de membres, avec un plafond de 1,5 s » au lieu de « 2 s depuis le changement ». Son échéance passe par `nextDeadline()`, donc la passe repart dès la fin de l'attente (FR-014).
- Une garde de transition de bureau s'ouvre quand une fenêtre quitte le plein écran natif, ou quand un membre manquant revient. Elle se ferme sur `activeSpaceDidChange`, sur une frame identique entre deux lectures à 50 ms d'écart, ou au plafond de 1,5 s. Elle exclut seulement le scope concerné (FR-017 de la SPEC-016).

**API privée** : aucune pour l'instant.
- Le moment d'envoi de `activeSpaceDidChange` n'est pas vérifié [D]. L'instrumentation de la phase 0 le mesurera.
- Si cette notification ne suffit pas, on utilisera `CGSGetActiveSpace` et `CGSSpaceGetType` (type 0 = bureau utilisateur, `space_is_user` chez yabai), en lecture seule, sur le modèle de `_AXUIElementGetWindow` déjà utilisé (`SystemSnapshotProvider.swift:5-6`). Ce choix demandera une ADR.

**Ce que protège FR-017 (SPEC-016)** : ne pas réorganiser deux fois pendant une rafale de changements de membres. Le test `tiledScopeMembershipChurnSettlesBeforeRelayout` vérifie 0 commande pendant la rafale et 1 commande ensuite, sans figer la durée [L]. Il reste valide.

## R8 - Écriture AX façon yabai

**Décision** :
- Ordre taille, position, taille.
- `AXEnhancedUserInterface` désactivé puis remis une fois par application et par lot, seulement s'il était actif.
- Une seule relecture en un aller-retour (`AXUIElementCopyMultipleAttributeValues`). Elle alimente le registre (R6) et la détection des refus.
- Un index des éléments AX par pid, issu du snapshot, est réutilisé par l'écrivain. Il est vidé à la destruction d'une fenêtre ou à la fin d'une application.

**Raison** :
- yabai écrit ainsi (`window_manager.c:729-762`, `misc/helpers.h:524-530`) [L].
- Roadie écrit position, taille, position, relit en 2 appels et réénumère `kAXWindows` à chaque écriture (`SystemSnapshotProvider.swift:811-827, 969-1013`) [L].

**On garde une relecture** (écart assumé avec yabai) : toute la gestion des refus attend la frame réelle de façon synchrone. Supprimer la relecture obligerait à réécrire cette logique sur l'événement « redimensionné », ce qui est risqué.

## R9 - Tolérance unique

**Décision** : un placement est « à refaire » si la frame observée s'écarte de plus de `LayoutTolerance.frameMatch` (2 pt) de la cible, sauf si cette frame est déjà la frame acceptée pour cette cible dans le registre. Le seuil « réussi » de 48 pt disparaît.

**Raison** :
- Aujourd'hui un placement est réussi à 48 pt près (`DaemonSnapshot.swift:1628-1630`), mais redemandé dès 1 pt d'écart (`LayoutTypes.swift:90`) [L].
- Passer simplement le seuil « réussi » à 2 pt classerait en boucle les terminaux comme refusés, car ils arrondissent leur taille à la cellule (environ 17 pt). La frame acceptée évite ce piège [D].

## R10 - Cache de l'état persisté

**Décision** : `JSONPersistence` garde, par chemin, la valeur décodée et sa signature (mtime en nanosecondes, taille, inode).
- `load` fait un `stat` et rend la valeur en cache si la signature n'a pas changé.
- `mutate` part de la valeur en cache sous verrou. Il n'encode et n'écrit rien si la valeur n'a pas changé (les types sont `Equatable`).

**Raison** :
- `stages.json` (49 Ko) est décodé au moins 4 fois par tick, et réencodé à chaque snapshot (`JSONPersistence.swift:61-99, 148-159` ; `LayoutMaintainer.swift:1968, 2033, 2493` ; `DaemonSnapshot.swift:1324, 1366`) [L].
- Le modèle de signature existe déjà (`ConfigReloadService.swift:273-277`, `RailSettings.swift:123-135`) [L].
- Les écritures des autres processus passent toutes par un renommage atomique sous verrou (ADR-008). Elles changent donc l'inode et le mtime, et sont vues à la passe suivante (FR-011).

## R11 - Un snapshot par passe ; publier au lieu d'invalider

**Décision** :
- Le snapshot reste global : la réconciliation est une fonction pure de l'état et des fenêtres vivantes (ADR-008).
- Une passe ne prend qu'un snapshot.
- Après un placement, le snapshot partagé est republié avec les frames écrites au lieu d'être invalidé (`DaemonSnapshot.swift:1607`). Les lecteurs (bordure 120 ms, focus qui suit la souris 100 ms, navrail) ne refont plus de relevé complet.

**Alternative rejetée** : un snapshot incrémental piloté par les événements, comme yabai. C'est une refonte à risque élevé, alors que le gain principal vient de R5, R6 et R10. À reconsidérer seulement sur mesure.

## R12 - Commandes sur l'arbre, appliquées tout de suite

**Décision** :
- Les commandes à arbre appliquent le sous-arbre modifié dans la commande elle-même. Le verrou global de 2 s (`LayoutCommandActivity`) ne bloque plus les ticks des modes à arbre (`WindowCommands.swift:108-119`, `LayoutCommandActivity.swift:37-44`) [L].
- Portages :
  - `balance` remet tous les ratios à 0,5 ;
  - `layout toggle-split` inverse le sens du split parent de la fenêtre active ;
  - `layout split horizontal|vertical` impose ce sens ;
  - `layout flatten` équivaut à `balance` ;
  - le glisser-déposer échange les fenêtres si on lâche au centre, et insère du côté indiqué si on lâche sur un bord ;
  - `stage_place_window` et le dépôt par le navrail respectent l'index d'insertion dans l'arbre.
- `layout insert`, `layout join-with` et `layout width` répondent par un refus explicite en mode à arbre. Aucun raccourci de l'utilisateur ne s'en sert [L : base BetterTouchTool].
- Sens de `resize` : on garde celui de `mutableBsp`, pour la mémoire musculaire de l'utilisateur. La direction désigne le bord à pousser vers l'extérieur. S'il n'y a pas de frontière dans ce sens, la frontière opposée est tirée vers l'intérieur.

## R13 - Feuille conservée pendant la grâce

**Décision** : une fenêtre absente du snapshot (plein écran natif, autre bureau) garde sa feuille dans l'arbre persisté tant que son membre de stage est dans sa période de grâce (`LayoutTolerance`, 45 s pour une fenêtre manquante). La disposition se calcule sur une copie de l'arbre sans les feuilles absentes. À son retour, la fenêtre reprend sa place (FR-007). Elle est insérée comme une nouvelle fenêtre seulement si sa feuille a disparu.

**Raison** : aujourd'hui la feuille est retirée immédiatement (`DaemonSnapshot.swift:1038`), et la fenêtre revient « à côté du focus » [L].

## R14 - Instrumentation à la milliseconde

**Décision** : `RoadieEvent` reçoit `tsMs` (epoch en ms, dérivé du timestamp) et `episodeId`. `layout_apply` reçoit `durationMs` et `cause`. Le format ISO du timestamp ne change pas.

**Raison** : un champ ajouté est ignoré par les lecteurs existants, ce qui a été vérifié par un test jetable. Un timestamp ISO avec fraction dépend de la version de Foundation [L].

## R15 - Code supprimé

Prévu (FR-018) :
- logique live tick de `main.swift:322-356` ;
- `TickDuration` ;
- `LayoutMaintainer.run()` (code mort) ;
- chaîne `mutableBsp` de `LayoutMaintainer.swift` (« geometry adopted », « resize propagated », référence synthétique, suppression des scopes stables visibles, environ 2067-2370 et 2492-2550) ;
- réparation d'ordre (`DaemonSnapshot.swift:1180-1230`) ;
- reflow `mutableBsp` du glisser-déposer ;
- `MutableBSPLayoutStrategy`, sauf la détection de coupes, déplacée vers la migration ;
- `revertedAppliedFrames` ;
- invalidation globale de `AXAttributeCache`.

Les tests propres à `mutableBsp` (environ 45) sont réécrits pour l'arbre ou retirés, et chaque retrait est justifié.
