# Contrat : Interface Menu Pin

## Bouton de Fenêtre Pinée

### Conditions d'Affichage

- La fenêtre est pinée.
- La fonctionnalité `experimental.pin_popover.enabled` est active.
- La fenêtre est visible dans son scope courant.
- La fenêtre n'est pas en plein écran natif.
- Le placement calculé est sûr.

### Comportement

- Clic gauche : ouvre le menu Roadie de pin.
- Clic sur une autre fenêtre ou disparition de la fenêtre cible : le menu se ferme sans mutation.
- Si la fenêtre devient inéligible entre affichage et clic, aucune action destructive n'est exécutée.

## Menu Compact

### Sections attendues

1. **Pin** : état courant, changer de scope, retirer le pin.
2. **Fenêtre** : replier ou restaurer selon l'état courant.
3. **Déplacer** : stage, desktop, desktop/stage, écran, avec les mêmes destinations que le menu de barre de titre.

### Règles

- Les actions indisponibles sont absentes ou désactivées.
- Les libellés reprennent le vocabulaire utilisateur existant.
- Les modes de pin sont regroupés ensemble.
- Le menu ne contient pas d'explication longue.

## Proxy Replié

### Conditions d'Affichage

- La fenêtre est pinée.
- Son état de présentation est `collapsed`.
- Le scope du pin rend ce proxy visible dans le contexte actif.

### Comportement

- Clic gauche ou action "Restaurer" : restaure la vraie fenêtre au frame mémorisé.
- Menu secondaire : permet au minimum de restaurer ou retirer le pin.
- Si la fenêtre live a disparu, le proxy disparaît au prochain refresh normal.
