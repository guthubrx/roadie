# Quickstart : Menu Pin et Repliage

## Préconditions

1. Compiler Roadie.
2. Activer le menu clic droit de barre de titre si l'on veut comparer les deux points d'entrée.
3. Activer le menu pin expérimental :

```toml
[experimental.pin_popover]
enabled = true
show_on_unpinned = true
collapse_enabled = true
```

4. Relancer `roadied`.

## Scénario 1 : bouton visible

1. Choisir une fenêtre gérée visible.
2. Vérifier qu'un petit bouton circulaire bleu apparaît dans la zone de titre.
3. Vérifier qu'il ne couvre pas les boutons fermer/minimiser/plein écran.
4. Cliquer le bouton.
5. Vérifier que le menu compact apparaît près du bouton.

Résultat attendu : le menu s'ouvre en moins de 2 secondes et propose les actions de pin/déplacement pertinentes.

## Scénario 2 : cohérence avec le clic droit

1. Ouvrir le menu clic droit de barre de titre sur la même fenêtre.
2. Noter les destinations disponibles.
3. Ouvrir le menu depuis le bouton bleu.
4. Comparer les destinations stage, desktop, desktop/stage et écran.

Résultat attendu : les destinations sont cohérentes, les actions indisponibles ne sont pas proposées.

## Scénario 3 : repliage

1. Placer une fenêtre pinée au-dessus d'une autre fenêtre.
2. Ouvrir le menu depuis le bouton bleu.
3. Choisir `Replier la fenêtre`.
4. Vérifier que la fenêtre dessous redevient visible et interactable.
5. Cliquer le proxy replié.
6. Vérifier que la fenêtre revient à sa taille et position précédentes.

Résultat attendu : 20 cycles replier/restaurer ne changent pas la position ou taille perçue de la fenêtre.

## Scénario 4 : changements de stage et desktop

1. Replier une fenêtre pinée.
2. Changer de stage plusieurs fois dans le scope du pin.
3. Changer de desktop selon le scope du pin.
4. Restaurer depuis le proxy.

Résultat attendu : aucun saut de layout, aucune boucle de focus, aucun changement de stage inattendu.

## Régressions à Vérifier

- Une fenêtre non pinée reçoit le bouton si `show_on_unpinned = true`, mais ne reçoit aucun état de présentation tant qu'elle n'est pas pinée.
- Le menu clic droit de barre de titre continue à fonctionner.
- Les bordures de focus restent réactives.
- Les popups, dialogues de sauvegarde et panneaux système ne reçoivent pas le bouton.
- Désactiver `experimental.pin_popover.enabled` retire bouton et proxy sans casser les pins existants.
