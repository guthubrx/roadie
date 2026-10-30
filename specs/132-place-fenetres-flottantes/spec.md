# Session 132 - Place retenue des fenêtres flottantes

**Date** : 30 octobre 2026 · **Branche** : `132-place-fenetres-flottantes` (partie de la branche 131, non fusionnée)

## Besoin (essai du 30 octobre 2026)

La fenêtre « Lire les informations » du Finder s'ouvre à x = 10, sous le rail (150 points, bord gauche).
Roadie ne la gère pas (règle `exclude`) et ne la déplace donc pas. L'utilisateur veut aussi qu'une fenêtre
flottante choisie (infos du Finder, rappel de Thunderbird…) revienne là où il l'a laissée, avec un réglage,
car d'autres utilisateurs ne voudront pas de ce comportement.

## Décisions de l'utilisateur

1. Une fenêtre flottante qui s'ouvre sur le rail est décalée à sa droite, **par défaut**, désactivable.
2. La place retenue comprend **la position et la taille**.
3. **Aucune** fenêtre ne retient sa place par défaut : l'utilisateur coche « retenir la place » par règle.

## Exigences

- **FR-001** Une fenêtre non tuilée (standard ou dialogue, d'une autre application que Roadie) qui apparaît
  sur la bande du rail de son écran est déplacée juste à droite du rail, sans changer de taille ; une fenêtre
  trop large pour tenir à droite du rail n'est pas touchée. Réglage `[exclusions] floating_avoid_rail`
  (vrai par défaut), dans Paramètres > Règles.
- **FR-002** Une règle `[[rules]]` (action `remember_frame = true`) ou une ligne
  `[[exclusions.floating_windows]]` (`remember_frame = true`) fait retenir la place des fenêtres qu'elle vise :
  position et taille, dans `~/.roadies/floating-frames.json`, sous l'identifiant de la règle (les titres
  changent d'une fenêtre à l'autre, « X Info »).
- **FR-003** À l'apparition d'une telle fenêtre, la place retenue est rendue si elle est encore sur un écran
  branché ; sinon FR-001 s'applique.
- **FR-004** Seule l'apparition d'une fenêtre est traitée : ensuite Roadie ne fait que retenir la place après
  un déplacement ou un redimensionnement (bouton relâché). Au démarrage de Roadie, les fenêtres déjà ouvertes
  ne sont pas déplacées.
- **FR-005** Les deux réglages apparaissent dans les éditeurs de Paramètres > Règles (case « Retenir la
  place »).

## Critères de réussite

- **SC-001** Une fenêtre d'informations du Finder ouverte à x = 10 se retrouve à droite du rail.
- **SC-002** Avec la règle cochée, une fenêtre d'informations déplacée puis fermée rouvre au même endroit et à
  la même taille.
- **SC-003** Sans case cochée, aucune place n'est retenue ; avec `floating_avoid_rail = false`, rien ne bouge.

## Hors périmètre

Rattacher les fenêtres flottantes par règle à une stage et leur donner le menu de barre de titre (option A
proposée le 30 octobre, non retenue pour l'instant).
