# Spécification de fonctionnalité : Manipulation interactive de l'arbre BSP

**Branche** : `014-bsp-tree-manipulation`
**Créé le** : 2026-05-22
**Statut** : Prêt pour implémentation
**Entrée utilisateur** : "Je voudrais qu'on fasse tout de suite le spatial BSP mutable" — rendre `spatial_bsp` pleinement manipulable comme yabai (déplacer, échanger, redimensionner les fenêtres dans l'arbre).

## Contexte

SPEC-013 a livré l'arbre BSP persistant (insertion sur pane focalisé, fermeture). Mais les commandes `move`/`warp`/`swap`/`resize` ne touchent **pas** l'arbre : elles manipulent les frames/intents (conçues pour `mutableBsp`). En `spatial_bsp`, un déplacement ne « tient » pas (l'arbre reprend le dessus au tick suivant) et un resize n'est pas mémorisé.

SPEC-014 câble ces commandes sur l'arbre pour un comportement yabai complet.

**Prérequis** : SPEC-013 (arbre persistant).

## Scénarios utilisateur et tests

### Scénario 1 — Échanger deux fenêtres (swap) (P1)
Focus sur une fenêtre, commande directionnelle → la fenêtre échange sa **position dans l'arbre** avec sa voisine. La structure est préservée, seules les deux feuilles permutent.

**Acceptation** :
1. **Étant donné** deux fenêtres tilées, **Quand** l'utilisateur fait `move`/`swap` vers la voisine, **Alors** les deux fenêtres échangent leur place dans l'arbre et l'échange **persiste** (ne revient pas au tick suivant).

### Scénario 2 — Déplacer une fenêtre dans le pane voisin (warp) (P1)
Focus sur une fenêtre, `warp` directionnel → la fenêtre est **retirée** de sa position et **réinsérée** à côté de la voisine dans la direction donnée (change la structure de l'arbre).

**Acceptation** :
1. **Étant donné** une fenêtre A et une voisine B, **Quand** l'utilisateur `warp` A vers B, **Alors** A quitte son pane (le frère récupère l'espace) et divise le pane de B.

### Scénario 3 — Redimensionner (resize) (P1)
Focus sur une fenêtre, `resize` directionnel → ajuste le **ratio** du split concerné dans l'arbre. Le resize **persiste**.

**Acceptation** :
1. **Étant donné** deux fenêtres côte à côte, **Quand** l'utilisateur agrandit l'active vers la droite, **Alors** le ratio du split vertical augmente et **persiste**.

### Scénario 4 — Coexistence (P2)
Les commandes en mode non-`spatial_bsp` (`mutableBsp`, etc.) gardent leur comportement actuel.

### Cas limites
- Voisine inexistante (bord de l'écran) → comportement inchangé (envoi vers display adjacent ou no-op).
- Une seule fenêtre → swap/warp no-op.
- Resize au-delà des bornes → ratio clampé (0.05–0.95, déjà dans l'arbre).

## Exigences

**EF-001** En `spatial_bsp`, `move`/`swap` directionnel DOIT échanger les deux feuilles dans l'arbre et persister.
**EF-002** En `spatial_bsp`, `warp` directionnel DOIT retirer la fenêtre et la réinsérer à côté de la voisine.
**EF-003** En `spatial_bsp`, `resize` directionnel DOIT ajuster le ratio du split correspondant et persister.
**EF-004** Les opérations d'arbre (`swapping`, `warping`, `resizing`) DOIVENT être pures et testables dans `RoadieTiler`.
**EF-005** Les modes non-`spatial_bsp` DOIVENT conserver leur comportement.
**EF-006** La persistance de l'arbre modifié DOIT respecter `persistStateChanges` (writer uniquement).

## Critères de succès

**SC-001** Après un swap, les deux fenêtres restent échangées sur ≥ 3 ticks (mesure : pas de retour arrière).
**SC-002** Après un resize, le ratio persiste dans `stages.json`.
**SC-003** 100% des tests existants (455) restent verts ; nouveaux tests d'opérations d'arbre verts.

## Non-objectifs
- Rotation/miroir de l'arbre (itération future).
- Insertion points manuels avancés.

## Dépendances
- **SPEC-013** : prérequis (arbre + reconciliation).
- **SPEC-012/011** : persistance gated writer.

## Checklist
- [ ] swap / warp / resize couverts
- [ ] EF mesurables
- [ ] coexistence modes
- [ ] dépendance SPEC-013 documentée
