# Contrat comportemental : transitions de topologie d'écrans

## Entrées

Le service de parking reçoit :

- snapshot d'écrans live après stabilisation ;
- état persistant courant des stages ;
- snapshot de fenêtres live ;
- date de transition ;
- écran actif ou écran principal comme préférence de destination.

## Sorties

Le service retourne un rapport :

```text
displayParking.transition
  kind=park|restore|noop|ambiguous
  originDisplayID=<id?>
  originLogicalDisplayID=<id?>
  hostDisplayID=<id?>
  restoredDisplayID=<id?>
  parkedStageCount=<n>
  restoredStageCount=<n>
  skippedStageCount=<n>
  reason=<stable_reason>
```

## Cas : écran disparu

Préconditions :

- un écran présent dans l'état précédent n'est plus dans les écrans live ;
- cet écran contient au moins une stage non vide ou une origine utile ;
- au moins un écran live reste disponible.

Comportement :

1. Choisir un écran hôte : écran actif si présent, sinon écran principal, sinon premier écran live stable.
2. Pour chaque stage non vide de l'écran disparu, créer ou déplacer une stage distincte sur l'écran hôte.
3. Marquer chaque stage comme `parked` avec son origine.
4. Préserver nom, mode, membres, groupes, focus et ordre relatif.
5. Conserver les stages vides comme information restaurable sans les afficher inutilement.

Interdits :

- fusionner plusieurs stages non vides en une seule ;
- supprimer le scope d'origine ;
- changer l'ordre des stages natives de l'écran hôte sauf ajout contrôlé des stages rapatriées.

## Cas : écran revenu

Préconditions :

- une ou plusieurs stages `parked` ont une origine dont l'écran logique semble correspondre à un écran live ;
- le match est non ambigu.

Comportement :

1. Déplacer les stages parkées courantes vers le scope de l'écran revenu.
2. Restaurer leur ordre relatif d'origine autant que possible.
3. Préserver tous les changements faits pendant le parking.
4. Marquer les stages comme `restored` ou `native` selon la décision d'implémentation retenue pour le diagnostic.

Interdits :

- restaurer depuis un snapshot ancien ;
- déplacer vers un écran ambigu ;
- écraser une stage native existante sans conflit explicitement résolu.

## Cas : écran revenu ambigu

Comportement :

- Ne rien déplacer automatiquement.
- Garder les stages parkées sur l'écran hôte.
- Émettre un diagnostic `ambiguous`.

## Cas : rafale de changements

Comportement :

- Annuler la transition en attente à chaque nouvel événement.
- Redémarrer une période de stabilisation.
- Appliquer uniquement la transition correspondant au dernier état stable.

## Raisons stables attendues

- `display_removed`
- `display_restored`
- `ambiguous_match`
- `no_live_host`
- `no_parked_stages`
- `already_stable`
- `deferred_until_stable`
- `window_move_failed_visible`
