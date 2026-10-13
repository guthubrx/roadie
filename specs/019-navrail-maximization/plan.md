# Plan : Maximisation en laissant la place au navrail

**Branche** : `019-navrail-maximization` | **Date** : 2026-10-12 | **Spec** : [spec.md](spec.md)

## Résumé

Étendre le zoom de commande existant avec une réservation explicite du rail. Garder le marqueur zoomedWindowID comme source de protection du scope. Calculer un seul cadre de maximisation à partir du display visible et des marges de fenêtre seule, avec une marge gauche au moins égale à RailSettings.width. Lire visibleWidths par écran et isPinned dans le store existant : repli auto-hide sans pin donne le visibleFrame plein ; pin ou rail déplié donne la réservation. Persister des champs optionnels pour distinguer les modes et restaurer les placements précédents.

## Contexte technique

- Swift 6, SwiftPM, macOS 14+, AppKit et Accessibilité.
- Dépendances existantes seulement : RoadieCore, RoadieAX, RoadieStages, RoadieTiler, TOMLKit.
- Stockage : LayoutIntentStore JSON atomique et StageStore existants.
- Tests : Swift Testing avec les fixtures PowerUserProvider/Writer et LayoutMaintainer existantes.
- Coût : O(w) pour capture/restauration, O(w log w) pour les plans existants ; aucune boucle de scan nouvelle.
- Contraintes : un scope ciblé, pas de Space natif créé, cadres réellement acceptés, compatibilité des anciens intents.

## Contrôle constitutionnel

PASS avant recherche et après conception : documentation française, worktree dédié, tests de comportements avant livraison, aucune nouvelle dépendance, aucune couche de service nouvelle. Articles XIX/XX : un calcul de cadre partagé et une extension de la bascule actuelle évitent deux mécaniques concurrentes. Les hooks de commit optionnels sont reportés à la livraison, selon le pipeline invoqué. Le numéro 018 est occupé par un autre worktree ; 019 est isolé. Le pointeur courant 017 désignait une session livrée ; la demande nouvelle ouvre 019.

## Structure

Artefacts : spec.md, plan.md, research.md, data-model.md, contracts/cli.md, quickstart.md, reuse-audit.md, tasks.md et checklist requirements.md.

Code existant étendu :
- Sources/RoadieDaemon/LayoutIntentStore.swift : champs optionnels zoomReservesRail et restorePlacements.
- Sources/RoadieDaemon/WindowCommands.swift : toggleMaximize(windowID:), bascule commune des deux zooms, capture unique/restauration des cadres, validation des cadres acceptés avant masquage.
- Sources/RoadieDaemon/DaemonSnapshot.swift : maximizedFrame(on:) et interprétation actualisée de l'intent réservé dans validIntent ; restoration du zoom partagé.
- Sources/RoadieDaemon/LayoutMaintainer.swift : recalage et focus caché utilisant le cadre réservé ; sortie du zoom sur focus d'une voisine restaure la disposition sauvegardée.
- Sources/RoadieDaemon/StageCommands.swift : retour de stage avec cadre réservé recalculé.
- Sources/RoadieDaemon/CLICommandRouter.swift : route et aide toggle maximize.
- Sources/RoadieDaemon/TitlebarContextMenuController.swift et WindowContextActions.swift : action maximisation ciblée, sous-menu Fenêtre existant.
- Tests/RoadieDaemonTests : tests dans les suites existantes, sans nouvelles fixtures de stockage.
- README.md, README.fr.md, docs/en/README.md, docs/fr/README.md et docs/en/cli.md, docs/fr/cli.md : comportement et commandes.

## Réutilisation de l'existant

WindowCommands.toggleFullscreen (484) fournit application, masquage, focus et événements. LayoutIntentStore (4) accepte déjà des propriétés optionnelles. SnapshotService.outerGaps (1913) gère les overrides et smart gaps ; maximizedFrame force la bande complète du rail visible, ou renvoie le plein cadre utile lorsqu’il est replié. RailPanel (169) définit cette bande via config.railWidth, lui-même égal à RailSettings.width : on réserve le panneau, sans ajouter la largeur de carte 224 qui reste son contenu. LayoutMaintainer.fullscreenEntries (2295) reconnaît déjà le marqueur logique. StageCommands.targetFullscreenMemberID (1231) préserve ce marqueur. Les menus et routeurs existants suffisent.

## Ordre et vérification

1. Tests de cadre réservé, transitions, restauration, persistance ancienne et refus.
2. Modèle et commande commune ; cadre partagé et protection après maintien.
3. Intégration CLI/menu ciblé et documents anglais/français.
4. Tests complets, convergence exigence par exigence, audit v14 restreint.
5. Commit des seuls fichiers du manifeste, fusion sur main, push vérifié.
6. make install puis make restart avec signature conservée ; doctor/self-test et audit d'état.
7. Retirer seulement le worktree/branche de 019 et ses temporaires, conserver 018 et les fichiers préexistants.

## Divergences volontaires

Aucune duplication de service. Le calcul maximizedFrame est une règle métier de maximisation suivant la visibilité du rail, utilisée par les commandes, les plans, le maintien et les transitions de stage. La disposition sauvegardée est un dictionnaire optionnel ; pas de copie récursive d'intent ni de pile de zooms.


## Correction du 2026-10-13 — Visibilité du rail

Le besoin utilisateur précise que le rail masqué libère toute sa bande. Réutiliser visibleWidths et isPinned du RailRuntimeStateStore. Une largeur absente au démarrage auto-hide non épinglé signifie repliée ; pin impose la réservation immédiatement malgré une largeur périmée. Le callback existant onVisibleWidthChanged relance déjà resize ; l'étendre à la seule fenêtre maximisée en overlay. Écarter le zoom rail-aware de l'heuristique hide_on_maximized pour éviter une boucle, tout en gardant le plein écran natif prioritaire. Le getter currentRailSettings et le callback restent internes et deviennent accessibles aux tests ; aucune nouvelle abstraction ni stockage.


## Correction des placements observés depuis 5 h 50

Réutiliser les chemins existants : LayoutMaintainer.changedWindows/nonTreeLayout/focusedHiddenRestore, WrittenFrameRegistry/générations et règles de refus, SnapshotService et RestoreSafetyService.unhideAll/run marker. Exclure les observations de fenêtres inactives/masquées des intentions manuelles. Résoudre l’activation avant le masque des voisines. Diagnostiquer les refus AX à partir des états natifs et de la disponibilité, sans augmenter arbitrairement le budget ni masquer un échec. Restauration basée sur visibilité réelle, diagnostics arrêt/crash fidèles. Fixtures synthétiques avant corrections ; sources réparties entre responsables sans chevauchement ; aucun build pendant des écritures. Suite complète, revue adverse, convergence puis livraison intégrée.


Précisions après revue : le filtre des faux redimensionnements agit sur le chemin de resize et préserve les signaux d’adoption/dérive. Le focus d’une voisine visible autant que cachée doit être couvert. La garde de restauration native utilise un état natif fiable ; isOnScreen seul ne suffit pas car les fenêtres parkées doivent être restaurées. Les journaux privés restent locaux, la revue utilise le code et les documents synthétiques.


Mise en œuvre précisée : préflight AXFullScreen au point commun d’écriture, sous timeout/quarantaine actuels, avant consommation du budget. Les codes de phase déjà retournés par les appels AX sont enregistrés dans WrittenFrame puis ajoutés aux événements de refus compatibles ; aucune lecture de diagnostic supplémentaire. Restaurer avec un marqueur optionnel de demande d’arrêt ; publier crash après réservation de la reprise seulement si cette demande est absente. Refus réels et native-skipped identifiés par IDs/compteur. Les causes précises des refus historiques Grayjay/iTerm ne sont pas établies ; les protections et les traces réduisent le risque sans prétendre contrôler une application qui refuse AX.


Le focus validé du snapshot inclut un repli ; confirmer l’activation visible par la cause et le focus réel partagé avec le masque. Conserver la restauration historique du focus caché au poll. Aucun champ de snapshot ni nouvelle mémoire de focus créé. Le centrage de repli ne doit pas changer une voisine visible dont restorePlacement est déjà respecté.
