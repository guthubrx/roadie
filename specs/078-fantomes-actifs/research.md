# Recherche 078

## R1 Fenêtre fantôme gérée : écartée
Roadie s'exclut à trois niveaux (liste CG `pid != currentPID`, nom `roadied`, écriture AX). Faire
gérer une fenêtre de Roadie par le tuilage toucherait le relevé, l'audit d'état et l'écriture.

## R2 Calcul pur de la disposition future
`BSPTree.inserting(_:at:side:in:innerGap:excluding:)` et `LayoutPlanner.plan` sont purs. L'ancre est
celle de `reconciledTree` (`bspInsertionAnchor` : focus global, focus de la stage, focus précédent),
le côté `windowPlacement.newWindowSide`. Une extension de `SnapshotService` dans
`DaemonSnapshot.swift` accède à `treePlacedWindowIDs`, `orderedWindowIDs` et `outerGaps`. Un
identifiant fantôme (`0xFFFF_FFF0`) tient la place de la fenêtre à venir.

## R3 Suspension de la disposition
La pause Mission Control (SPEC-062) montre le modèle : la passe sort tôt, sans relevé ni écriture.
Un maintien partagé (`LayoutPreviewHold`, verrou, échéance) est lu au début de `tick(cause:)`.
Échéance 1,5 s renouvelée toutes les 0,5 s par le contrôleur : si la barre disparaît sans fin
d'aperçu, la disposition reprend seule. Démon multi-processus (SPEC-011) : le maintien ne traverse
pas les processus (limite, mode non utilisé par défaut).

## R4 Écritures prises pour un geste ?
`SnapshotService.apply` passe par le registre des cadres écrits : ces cadres sont connus comme
écrits par Roadie et ne sont pas adoptés comme déplacement de l'utilisateur à la reprise.

## R5 Stage cachée
`StageCommandService.switchTo(_:displayID:)` change la stage active ; la passe suivante montre ses
fenêtres. L'aperçu attend 300 ms après la bascule avant de se poser, puis suspend la disposition.
