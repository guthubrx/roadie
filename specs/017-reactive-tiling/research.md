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

## Amendements après contre-revue adverse (Codex GPT-6.1-Sol, round 1, verdict BLOCKED)

Ces amendements **priment** sur les sections R1 à R15 ci-dessus en cas de contradiction. Le détail des objections est dans `adversarial-review-codex.md`.

### A1 - Une passe = un plan unifié (remplace les « ticks de suite » de R5)

- Le tick ne quitte plus après chaque étape. Ces étapes produisent toutes des frames dans **un seul plan de passe**, dédoublonné par fenêtre, appliqué une fois : placements par règle, restauration des épinglages, restauration du focus, réancrage du zoom, masquage des voisines d'une fenêtre plein écran, masquage des stages inactives, disposition finale.
- Ordre de priorité en cas de conflit sur une même fenêtre : masquage, puis épinglage, puis règle, puis disposition.
- **Pas de tick de suite fondé sur « la passe a agi »** : `followUpPassLimit` est abandonné. Une nouvelle passe n'a lieu que sur un nouvel événement externe ou une échéance identifiée.
- Les notifications AX déplacé ou redimensionné qui sont l'écho de nos propres écritures sont filtrées **dans le callback**, par le registre. Elles ne planifient aucun tick.

### A2 - Budget d'écriture par version de disposition (précise R4 et FR-005)

- Chaque calcul de l'arbre porte une **version de disposition** (compteur incrémenté à chaque mutation de l'arbre ou du conteneur).
- Budget par version et par fenêtre : **2 écritures au plus**, l'écriture initiale et une correction. Toutes les écritures comptent, y compris l'ancrage de position, le masquage et l'isolement.
- Un refus n'est confirmé que si deux observations concordent : la relecture immédiate, puis l'événement « redimensionné » ou le snapshot suivant. Une réponse transitoire (animation) ne fixe pas de taille minimale.
- Après un refus confirmé, on cherche l'ancêtre le plus proche dont le split coupe **l'axe contraint**. On vérifie que la correction est faisable, puis on ajuste ce split une seule fois. Les voisines touchées reçoivent leur correction dans le même budget.
- Si la correction est infaisable, l'arbre accepte le chevauchement, comme yabai. L'isolement des scopes infaisables ne s'applique plus aux modes à arbre. Il reste pour `masterStack` et `bsp`.
- La spec FR-005 est reformulée en conséquence : une seule correction par version, et les voisines au plus une fois de plus.

### A3 - Matrice par mode (portée de la garantie)

| Mode | Source de la disposition | Geste manuel | Refus de taille | Garantie |
|---|---|---|---|---|
| `spatialBsp` (et alias `mutableBsp`, `yabai`) | arbre | frontière de l'arbre ajustée au relâchement | A2 | une passe, budget A2 |
| `bsp`, `masterStack` | stratégie actuelle, ratios dérivés des frames | comportement actuel | réparation et isolement actuels | reconnaissance d'écho et plan unifié A1, sans garantie d'une passe |
| `float` | frames courantes | n/a | n/a | aucun placement |

La spec réduit explicitement la garantie « une passe » aux modes à arbre. Les autres modes profitent de l'écho et du plan unifié.

### A4 - Session de geste (remplace le classement « clic après écriture » de R6)

- Au `leftMouseDown`, une **session de geste** enregistre la fenêtre sous le curseur (dernier snapshot), sa frame et l'instant. Au `leftMouseUp`, si la frame de **cette** fenêtre a changé de plus de `frameMatch`, c'est un geste manuel sur cette fenêtre seulement.
- Ordre de classement d'une frame observée :
  1. fenêtre de la session de geste en cours : on attend le relâchement ;
  2. écho de la **dernière** écriture (frame demandée ou relue de la version courante) ;
  3. réponse de l'application, moins de `echoWindow` après l'écriture ;
  4. **changement externe**.
- **Changement externe** (application qui se redimensionne seule, outil clavier qui déplace une fenêtre) : en mode arbre, une seule réécriture vers la frame de l'arbre (comportement yabai, `event_loop.c:805-822`). Si l'application refuse, on applique A2. Ce n'est jamais un geste : l'arbre ne change pas.
- Politique BetterTouchTool : les raccourcis de l'utilisateur appellent des commandes `roadie`, qui modifient l'arbre. Un déplacement direct par un outil tiers est un changement externe, ramené une fois à l'arbre.
- Une frame acceptée est liée à la frame demandée et à la version de disposition. Une nouvelle commande, donc une nouvelle version, l'invalide.
- Le repli local de la CLI (autre processus, registre non partagé) ne tourne que si le daemon ne tourne pas (verrou d'instance, ADR-007). Il ne peut donc pas entrer en conflit avec le registre.

### A5 - Garde de transition de bureau par écran (précise R7)

- Garde **par écran**, ouverte à la sortie du plein écran natif ou au retour d'un membre manquant sur cet écran.
- Fermeture prouvée : le bureau courant de cet écran est un bureau utilisateur. On le lit par `CGSCopyManagedDisplaySpaces` (lecture seule, résolu par `dlsym`), comme `space_is_user` chez yabai (`window_manager.c:2258-2295`). Lecture toutes les 50 ms tant que la garde est ouverte.
- Si le symbole est absent (`dlsym` renvoie nil), repli sur `activeSpaceDidChange` suivi d'une frame stable.
- Au plafond de 1,5 s, la garde se ferme avec `closedBy=timeout`, distinct de `closedBy=userSpace`, et c'est journalisé.
- Une ADR 010 justifie cette lecture privée : en lecture seule, sans désactiver SIP, avec repli public.
- `activeSpaceDidChange` est journalisé avec `tsMs`, pour mesurer son moment réel d'envoi.

### A6 - Pas de période calme pour les événements ordinaires (remplace la période calme de R7)

- Un événement ordinaire (une fenêtre créée ou détruite, sans transition de bureau) déclenche une passe immédiate, après seulement les 15 ms de regroupement de l'ordonnanceur. Il n'y a pas d'attente de stabilisation.
- La stabilisation FR-017 (SPEC-016) ne s'ouvre que sur une **rafale** : au moins 2 changements de membres sur le même scope en moins de 300 ms. Elle se termine après 100 ms de calme, plafonnée à 1 s, et repart par `nextDeadline`.
- L'activation d'un scope ne compte pas comme un changement de membres (inchangé).
- SC-001 se mesure depuis le **dernier** événement d'une rafale.
- Nouveaux tests : rafale de plusieurs changements ; plafond atteint ; deux écrans indépendants ; activation sans changement de membres ; aucun chemin d'écriture ne contourne l'exclusion du scope.

### A7 - Contrat du cache d'état (précise R10)

- `load`, sans verrou : ouvrir le fichier, `fstat` sur le descripteur, comparer à la signature en cache. Si elle est égale, rendre la valeur en cache. Sinon, lire les octets **depuis ce descripteur**, les décoder et les mettre en cache avec cette signature.
- `mutate` :
  1. prendre le verrou exclusif ;
  2. ouvrir, `fstat` et comparer ;
  3. relire depuis le descripteur si la signature diffère ;
  4. muter ;
  5. si la valeur a changé, écrire de façon atomique, puis faire `stat` du nouveau fichier et publier valeur et signature dans le cache, verrou encore tenu ;
  6. libérer le verrou.
- Les cas `.missing`, `.corrupt` et le refus d'écriture de la SPEC-016 sont inchangés. Pas de hash systématique.

### A8 - Migration explicite et durable (remplace la traduction au décodage de R1)

- Le cas `mutableBsp` **reste** dans `WindowManagementMode`, et le décodage est inchangé. Un accesseur `usesTreeEngine` vaut vrai pour `spatialBsp` et `mutableBsp`. La config traduit `mutableBsp` et `yabai` en `spatialBsp`, car elle n'a pas d'état.
- `StageStore.migrateLegacyTreeModes(infer:)`, sous un seul verrou :
  1. lire les octets bruts ;
  2. si une stage est `mutableBsp`, copier les octets d'origine vers `stages.json.pre-017` (une fois, sans écraser une sauvegarde existante) ;
  3. passer chaque stage en `spatialBsp` et construire l'arbre manquant par `infer` ;
  4. écrire. L'écriture est forcée, car le mode décodé change.
- Inférence : `BSPTree.inferred(from: [(WindowID, CGRect?)], in:)` reçoit les membres **dans leur ordre**. Si une frame manque ou est inutilisable (stage cachée, fenêtre hors écran, chevauchement), le repli déterministe insère tous les membres dans l'ordre. Aucun membre n'est perdu.
- Les symboles `mutableBsp` (cas d'enum, stratégie) sont supprimés seulement en vague 3, après le portage de tous les appelants. Le cas d'enum reste pour le décodage des anciens fichiers.

### A9 - Cycle de vie de la feuille et arbre projeté (précise R13)

- La feuille d'un membre absent est gardée tant que le membre existe, avec la **grâce réelle de 30 min** (`DaemonSnapshot.swift:75`).
- Une destruction confirmée (`kAXUIElementDestroyedNotification` pour cet identifiant) retire la feuille tout de suite.
- **Arbre projeté** : copie de l'arbre où les feuilles absentes sont retirées et les splits devenus unaires sont repliés. Toutes les opérations géométriques utilisent cet arbre projeté : placement, voisins pour focus/warp, ancre d'insertion, frontière d'un geste ou d'un resize.
- Chaque split visible dans la projection correspond à un seul split de l'arbre complet (même identité de nœud). Une mutation sur la projection s'applique donc au nœud correspondant de l'arbre complet. Un split replié n'a pas de frontière visible : il n'est pas ajustable.
- Tests : retour après plus de 45 s ; redimensionnement pendant l'absence d'une voisine, puis retour de la voisine.

### A10 - Vagues compilables

- La vague 1 n'enlève aucun symbole utilisé ailleurs. `MutableBSPLayoutStrategy` et `LayoutStrategy.mutableBsp` restent jusqu'à la vague 3.
- Avant la vague 2, l'orchestrateur pose des **stubs compilables** :
  - `LayoutMaintainer.tick(cause:) -> MaintenanceTick`, avec `tick()` qui délègue ;
  - `LayoutMaintainer.nextDeadline(now:) -> Date?` ;
  - `SnapshotService.applyTreeScope(_:cause:) -> MaintenanceTick`, l'application immédiate utilisée par les commandes (L9) et fournie par L8.
- L7 travaille par étapes séquentielles dans son fichier, avec un build vert entre chaque étape.

### A11 - Glisser, bascules et restaurations

- `WindowDragActivity` est confié à L6. À la fin d'un glisser, pas de grâce pour les modes à arbre : le relâchement déclenche la passe.
- La bascule de stage (`StageCommands.swift:1029-1041`), la bascule de bureau (`DesktopCommands.swift:308`) et l'aller vers un signet (`WindowBookmarkCommands.swift:117`) posent directement les frames **finales** de l'arbre pour les modes à arbre. Ils ne restaurent plus les frames mémorisées avant de recalculer. Ces fichiers sont confiés à L9.
- Le moniteur local du navrail (`RailController`) et tous les boutons de souris sont couverts par la suspension « bouton enfoncé ».

### A12 - Mesure et épisodes

- Les événements AX transmis portent le pid et l'identifiant de fenêtre (L3).
- Après une écriture, le snapshot est republié avec les frames **relues**. Une écriture en échec invalide la fenêtre concernée.
- Un épisode reste ouvert à travers ses échos et les échéances qu'il a armées. Il se ferme après 1 s sans cause externe nouvelle.
- `layout_apply` porte aussi `scans` (relevés complets) et `axWrites` (écritures AX) de la passe, et un compteur d'écritures par fenêtre.
- La mesure distingue trois instants : fin d'écriture, stabilité observée, fin de garde de bureau (animation macOS).
- `quickstart.md` ajoute une campagne avec plusieurs applications actives et une application lente.
- **Limite assumée** : les lecteurs du snapshot (bordure, focus qui suit la souris) gardent leur cadence actuelle, avec un rescan au plus toutes les 150 ms. Ce coût existe déjà. Le réduire est hors périmètre.

## Amendements après contre-revue adverse, round 2 (verdict BLOCKED, 5 objections du round 1 levées, 7 partielles)

Ces amendements priment sur A1 à A12.

### A13 - Génération de placement (remplace la « version de disposition » de A2)

- Une **génération** est un identifiant global et monotone (UInt64, pas par scope). Elle s'ouvre à chaque **intention externe** : événement système, commande, bascule de stage ou de bureau, changement de visibilité, geste.
- Une correction interne (refus de taille, ajustement de ratio qui en découle) **garde** la génération en cours, même si elle mute l'arbre.
- Budget : 2 écritures par fenêtre et par génération, sur tous les chemins d'écriture (maintainer, commandes, bascules, masquage). L'écrivain AX reçoit la génération par le protocole `WindowFrameWriting`, avec une valeur par défaut pour les anciens appelants.
- Budget épuisé : la frame observée est acceptée.
- Application qui se redimensionne en boucle : un changement externe est ramené à l'arbre **une fois par génération**. Les suivants sur la même fenêtre sont acceptés sans lutte, et journalisés.

### A14 - Confirmation des refus (précise A2)

- Quand une notification déplacé ou redimensionné est un écho de la relecture alors qu'un refus est en attente (frame relue différente de la frame demandée), le registre marque le refus comme confirmé **avant** d'absorber l'écho.
- Sans notification, le maintainer arme une échéance de relecture **fraîche** (lecture AX directe, environ 100 ms après l'écriture). Le snapshot republié ne compte jamais comme seconde observation.
- La correction garde la génération et le budget du placement initial.

### A15 - Ordre d'une passe (précise A1)

1. **Changements d'état logique** sur une copie de travail du snapshot : affectations par règle, stage active, épinglages, zoom.
2. **Calcul des placements** depuis cette copie : disposition de l'arbre, masquage des seules fenêtres hors de la stage active de la copie, frame de zoom qui remplace la frame de l'arbre pour la fenêtre zoomée.
3. **Arbitrage** par fenêtre.
4. **Application** unique.
5. **Focus** : action après l'application, pas une frame.

Une commande est une intention de l'utilisateur. `applyTreeScope` l'applique même si le scope est en rafale ou en garde, et clôt cette attente pour ce scope.

Test combiné : une règle qui change la stage active, le masquage et la disposition finale, dans la même passe.

### A16 - Faisabilité réelle des corrections (précise A2)

`correctingForMinimumSize(of:minimum:in:excluding:knownMinimums:)` :
- recalcule les frames candidates avec les mêmes marges, bornes de ratio (0,05 à 0,95) et arrondis que le placement ;
- vérifie les minimums connus des fenêtres touchées ;
- remonte les ancêtres de l'axe contraint, du plus proche au plus haut, jusqu'au premier qui rend la correction faisable ;
- renvoie `nil` sinon.

Tests : ratio hors bornes, voisine contrainte, correction possible seulement à un ancêtre supérieur.

### A17 - Cycle de vie de la session de geste (précise A4)

- Un clic qui ne tombe sur aucune fenêtre gérée (bureau, panneau, navrail, fenêtre exclue) ouvre une session **sans cible**, qui ne produit aucun geste.
- Le résultat d'une session se consomme **une seule fois** (`takeGesture()`).
- Arbitrage au relâchement :
  1. un **dépôt** reconnu par le glisser-déposer consomme la session, et l'ajustement de frontière n'a pas lieu ;
  2. une taille changée donne un ajustement de frontière ;
  3. une position seule changée, sans dépôt, ramène la fenêtre à l'arbre (une écriture).
- Les moniteurs **locaux et globaux** alimentent le même état, car le moniteur global ne voit pas les événements destinés à Roadie lui-même.
- Tests : clic sans cible, navrail, fenêtre détruite pendant le geste, deux ordres de réception du relâchement (dépôt puis maintainer, et l'inverse).

### A18 - Premier placement d'une rafale (précise A6)

- Le premier changement est placé immédiatement. Si un second changement révèle une rafale, le premier placement est **conservé**, et une seule passe finale suit le calme.
- SC-001 compte au plus 2 passes pour un épisode en rafale. L'objectif « une passe dans 95 % des épisodes » vise les épisodes isolés.
- Le test existant `tiledScopeMembershipChurnSettlesBeforeRelayout` est adapté : 1 commande immédiate, rien pendant la rafale, 1 commande finale. Ajouter des événements espacés de 80 ms et de 250 ms.

### A19 - Contrat de la sonde de bureau (précise A5)

- Connexion obtenue par `SLSMainConnectionID` ou `CGSMainConnectionID` (dlsym).
- Appel de `SLSCopyManagedDisplaySpaces` ou `CGSCopyManagedDisplaySpaces`, qui renvoie un tableau de dictionnaires.
- Pour l'écran voulu (`Display Identifier`, UUID ou `Main`), lecture de `Current Space` puis `type` : 0 = bureau utilisateur, 4 = plein écran.
- La sonde renvoie `nil` si le symbole est absent, si la réponse n'est pas conforme ou si l'écran est introuvable.
- Le décodage est une fonction pure, testée sur des données de test : deux écrans, bureau utilisateur, plein écran, données incomplètes.
- Repli public : `activeSpaceDidChange` reçu **après** l'ouverture de la garde, puis deux lectures AX fraîches et identiques, espacées de 50 ms.

### A20 - Interfaces avant la vague 2 et mesure de la stabilité (précise A10 et A12)

**Interfaces.**
- Les constantes de `LayoutTolerance` sont posées à la jonction. L3 utilise des constantes locales en vague 1.
- Stubs avant la vague 2 :
  - `UserInputActivity.currentGesture` et `takeGesture()` ;
  - `LayoutMaintainer.tick(cause:)`, `nextDeadline(now:)` et `spaceDidChange(displayUUID:)` ;
  - `SnapshotService.applyTreeScope(_:cause:generation:)` ;
  - `PlacementGeneration.next()`.
- Les opérations sur l'arbre avec exclusions s'appliquent directement à l'arbre complet. Il n'y a pas d'identifiant de nœud persistant.

**Stabilité observée.**
- Nouvel événement `layout_stable` : il est émis quand une observation fraîche, faite au moins 100 ms après la dernière écriture de l'épisode, montre toutes les fenêtres de la passe à leur frame cible ou acceptée. Il porte `stableAfterMs`.
- Un épisode reste ouvert tant qu'une échéance qu'il a armée est en attente (garde, refus, rafale). Il se ferme ensuite après 1 s de calme.
- Les compteurs distinguent les tentatives de placement (`windowWrites`) des appels AX élémentaires (`axWrites`).
- Tests : garde de 1,5 s dans un seul épisode, réponse différée, correction dans le même épisode.
