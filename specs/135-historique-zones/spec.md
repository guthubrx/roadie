# Session 135 - Historique des zones (⌥Tab)

**Date** : 30 octobre 2026 · **Branche** : `135-historique-zones`

## Besoin

Revenir aux zones trouvées par la recherche à l'écran (Capslock + F), même depuis une autre stage ou un autre
bureau, à la manière de ⌘Tab pour les fenêtres. Choix de l'utilisateur : ⌥ tenu, chaque Tab avance dans une liste
visible ; relâcher ⌥ y va et clique la zone.

## Exigences

- **FR-001** Chaque zone cliquée par la barre (clic, double-clic, clic droit, ⌘-clic réussis) entre dans un
  historique : application, fenêtre, texte, position relative dans la fenêtre et taille de celle-ci, élément
  d'accessibilité en mémoire. 20 zones au plus, une par fenêtre et texte, la plus récente en tête ; gardé dans
  `~/.roadies/zone-history.json`.
- **FR-002** `zone_history_hotkey` (vide par défaut ; `alt+tab` chez l'utilisateur), Paramètres > Raccourcis. La même
  touche avec Maj recule. ⌥ tenu : chaque appui avance ; la liste paraît après 0,15 s ; relâcher ⌥ valide.
- **FR-003** Premier choix : la zone la plus récente, ou la suivante si sa fenêtre est déjà au premier plan.
- **FR-004** Validation : la fenêtre revient par le sélecteur de fenêtres (stage et bureau compris) ; après le premier
  plan, clic au centre de l'élément s'il se lit encore dans la fenêtre, sinon à la position relative si la fenêtre a
  gardé sa taille (4 points près), sinon aucun clic. Clic sans touche, attente hors du fil principal.
- **FR-005** Fenêtre disparue : la zone est retirée de l'historique.

## Critères

- **SC-001** Zone cliquée dans une stage, passage à une autre stage, ⌥Tab : retour et clic sur la zone.
- **SC-002** ⌥ tenu + plusieurs Tab : la liste avance ; ⌥⇧Tab recule.
