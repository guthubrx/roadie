# Session 031 — Numéro et nom temporaires des stages

## Fiche Synthèse

Spec: 031-libelles-temporaires
Titre: Numéro et nom temporaires des stages
Statut: Implemented
Priorité: P1
Tâches: 5/5 (100%)
Tests: 1540/1540 (100%)

Validation utilisateur : 2026-10-15, avec séparation des deux touches Alt.

## Besoin

Les badges de position permanents encombrent le rail. Un double appui sur
Alt droite déclenche deux actions : la grille dans BetterTouchTool et les
noms des stages dans Karabiner.

## Critères d'acceptation

- Aucun badge de numéro permanent dans les cartes du rail.
- Le libellé temporaire présente la position visible puis le nom : « 1 — Work ».
- Le numéro suit l'ordre affiché, y compris après parking ou réorganisation.
- Alt droite deux fois affiche les libellés pendant cinq secondes, puis leur fondu.
- Alt gauche deux fois conserve la grille de placement à l'échelle de l'écran.
- Alt droite ne déclenche plus la grille. Les raccourcis sans rapport restent intacts.
- Les groupes, le tiling et la récupération au démarrage restent fonctionnels.
- Les traits des stages vides suivent la visibilité des noms : cachés au repos,
  visibles pendant la révélation, puis disparus après le même fondu.

Complément validé le 2026-10-15 : masquer aussi les repères vides persistants.

## Périmètre

Réutiliser le rendu des noms et son minuteur. Retirer la bande permanente
ajoutée dans la version installée par la session parallèle. Préserver les
autres changements de cette session lors de la livraison, sans modifier son worktree.

## Validation

Tests de rendu des quatre modes : aucun numéro au repos, numéro et nom après
révélation, disparition complète à expiration et géométrie stable. Tests du rail
et de récupération au démarrage. Vérification des configurations BTT/Karabiner,
installation signée et redémarrage avec contrôles santé.
