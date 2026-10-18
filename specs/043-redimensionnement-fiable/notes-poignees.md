# Poignées — implémentation et contrat d’intégration

Propriétaire : géométrie BSP, nouveaux fichiers SplitResize et tests associés. Aucun fichier existant du daemon, configuration, runtime ou LayoutMaintainer modifié. Base vérifiée : e86e71b74cdb870f7b7ae6b151e178bcd3303f1d. Pas de compilation/test Swift, commit, push ou installation par cet agent.

## Interface retenue

- `BSPTree.dividers(in:innerGap:excluding:) -> [BSPDivider]` : coordonnées AX absolues ; `path: [Bool]` suit **l’arbre complet** (`true = first`, `false = second`, `[] = racine`). `orientation`, `ratio`, `container`, `hitRect`, `position` (centre exact de la bande avant arrondi) décrivent la séparation visible. Une séparation sans espace de prise reste décrite, avec un rectangle vide.
- `BSPTree.movingDivider(at:to:in:innerGap:excluding:knownMinimums:) -> BSPTree?` : `to` désigne le centre de la séparation en AX. `nil` si chemin invisible/invalide. Modifie seulement le ratio visé ; conserve toutes les feuilles et autres ratios. Réutilise childRects, ratioBounds et les minimums du placement BSP.
- `SplitResizeHandle(scope: StageScope, divider: BSPDivider)` : identité = scope + chemin. Le parent doit fournir seulement les scopes actifs, spatialBsp, sur des écrans présents. Ajouter ses exclusions de fenêtres non tuilées à `excluding`.
- `@MainActor SplitResizeController(onBegin:onUpdate:onEnd:)`. `onBegin(handle, pointAX) -> Bool` accepte/refuse le geste. `onUpdate(handle, pointAX)` donne la position absolue corrigée de l’écart de prise initial, donc sans saut. `onEnd(handle, cancelled)` est appelé une seule fois pour toute session acceptée.
- `update(handles:)` remplace les poignées. `cancel()` libère le geste ; `stop()` annule et retire fenêtres/observateurs. Un changement des identités/orientations ou la disparition d’une poignée annule. Un simple changement de ratio/frame conserve le geste. Le parent doit appeler `cancel()` si sa génération/topologie change sans changement des identités.

Le parent possède validation du scope/génération, snapshot, configuration, arbitrage avec les autres gestes, point d’écriture AX, application/persistance et raccordement runtime. Aucune lecture AX pendant mouseDragged. Aucun aperçu P2.

## Décisions

Les fenêtres de prise sont des NSPanel sans activation ni focus. Elles ne couvrent que les bandes libres (arrondi tenant compte de place().integral). Sans bande libre, aucune fenêtre de prise. L’arrêt, Échap, perte du bouton ou changement de topologie annulent le geste. Une frontière injectable permet de tester début/fin/annulation sans bureau.

## Validation à effectuer par le parent

15 fonctions de test ajoutées (22 cas avec les paramètres) : 10 fonctions pour la géométrie et 5 pour le contrôleur. Couverture : deux/quatre fenêtres, splits imbriqués, projection et chemins complets, absence, minimums des deux côtés et d’un descendant, minimum déjà impossible, bornes existantes, espaces fractionnaires, relecture sans dérive, translation entre écrans ; prise explicite, refus de début, fin unique, annulation/perte du bouton/arrêt/changement de stage/écran/orientation/retrait, ratio rafraîchi et conversion multi-écran.

À exécuter **par le parent**, dans son créneau Swift sérialisé :

```sh
cd /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability
swift test --filter Spec043DividerTests
swift test --filter Spec043SplitResizeTests
swift test --filter 'BSPTree|SpatialBSPLayoutStrategyTests|ResizeHandlePickerTests'
```

Tests Swift et compilation **non exécutés**, conformément au mandat. Relecture statique complète et contrôle des espaces des cinq nouveaux fichiers : aucune anomalie signalée (`git diff --no-index --check`, code 1 normal pour des fichiers nouveaux différents de /dev/null). Aucun fichier existant modifié par cet agent. Aucun benchmark.

Preuves incomplètes : contrôleur non raccordé et aucune installation autorisée à cet agent. Le parent doit faire le parcours natif et le diaporama après intégration.

## Raccordement précis et limites

1. Fournir à `dividers` le conteneur **déjà corrigé des marges extérieures et du rail**, le même `innerGap` que le placement, et les mêmes feuilles exclues. Le calcul réutilise `BSPTree.childRects`, `gap`, `usableExtent` et `ratioBounds`. Il ne déduit jamais une séparation depuis une paire de fenêtres.
2. Seuls les rectangles prévus par le modèle sont garantis libres par cette géométrie. Avant `update(handles:)`, le parent doit retirer les poignées dont `hitRect` recoupe un cadre **réel** encore divergent (refus de taille, fenêtres flottantes/panneaux étrangers). Le parent possède ces cadres dans son snapshot ; aucun accès AX n’est ajouté au contrôleur. Une poignée sans bande libre est automatiquement ignorée.
3. `onBegin` doit réserver le geste, mémoriser scope, génération/topologie et arbre de départ, puis renvoyer true seulement si ce contexte est encore valide. `onUpdate` appelle `movingDivider(at: handle.divider.path, to: pointAX, ...)` et utilise le service d’écriture/persistance existant. Rejeter nil et les contextes périmés. Le callback conserve le handle initial du geste même si les frames sont rafraîchies.
4. `onEnd(handle, cancelled)` doit toujours libérer la réservation côté service. Le contrôleur libère son état **avant** ce callback ; fin/annulation sont idempotentes. Le choix de conserver/restaurer le dernier ratio lors d’une annulation appartient au parent.
5. Le parent appelle `cancel()` pour tout changement de topologie ou de génération qui conserve les mêmes chemins/orientations (échange de feuilles, par exemple). Un changement des identités/orientations est déjà détecté automatiquement. Un changement de ratio seul laisse le geste actif. Ne pas réémettre artificiellement le geste natif depuis les callbacks.
6. Appeler `stop()` lors d’une désactivation de configuration, arrêt du runtime et avant libération du contrôleur. Les moniteurs locaux/globaux, observateurs et le minuteur de perte du bouton n’existent que pendant un geste accepté ; stop les retire tous. Un changement d’espace macOS ou d’écrans pendant le geste appelle aussi stop.
7. `presentationEnabled: false` est la frontière de test. Elle désactive seulement les panels et observateurs système. `begin`, `drag`, `end`, `cancel`, `checkButton` et `update` restent le même circuit.

Aucun changement requis à la structure codée/persistée BSP ; les chemins sont temporaires et deviennent périmés quand la topologie change. Aucun fichier existant du daemon n’a été touché. Le fichier BSPTree.swift reste intact.

## Fichiers livrés

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieTiler/BSPDivider.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/SplitResizeController.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieTilerTests/Spec043DividerTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec043SplitResizeTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/043-redimensionnement-fiable/notes-poignees.md
