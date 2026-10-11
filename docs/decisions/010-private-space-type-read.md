# ADR-010 : Lecture privée du type de bureau courant

## Statut

Accepté. Mis en oeuvre par la SPEC-017 (amendements A5 et A19 de `specs/017-reactive-tiling/research.md`).

## Contexte

Après une sortie de plein écran natif, macOS anime le retour au bureau pendant environ 1 s. Ranger la fenêtre pendant cette animation produit des placements faux, puis des corrections. Roadie attendait donc 2 s fixes, ce qui rendait chaque sortie de plein écran lente.

yabai attend seulement tant que le bureau actif n'est pas un bureau utilisateur (`space_is_user`, `window_manager.c:2258-2295`). Il lit pour cela le type du bureau par l'API privée SkyLight.

L'API publique `NSWorkspace.activeSpaceDidChangeNotification` ne dit ni quel écran a changé, ni si l'animation est terminée.

## Décision

- `SpaceProbe.isUserSpaceActive(displayUUID:)` lit, **en lecture seule**, le type du bureau courant d'un écran. Il appelle `SLSCopyManagedDisplaySpaces` ou `CGSCopyManagedDisplaySpaces`, avec la connexion `SLSMainConnectionID` ou `CGSMainConnectionID`, toutes résolues par `dlsym`. Il lit `Current Space` puis `type` : 0 = bureau utilisateur, 4 = plein écran.
- La sonde renvoie `nil` si un symbole manque, si la réponse est incomplète ou si l'écran est introuvable.
- Repli public quand la sonde rend `nil` : `activeSpaceDidChange` reçu après l'ouverture de la garde, puis deux lectures fraîches identiques à 50 ms d'écart.
- Plafond de 1,5 s, avec `closedBy=timeout` journalisé, distinct de `closedBy=userSpace`.
- Aucun appel privé en écriture. Aucune désactivation de SIP. Aucune scripting addition.

## Conséquences positives

- La disposition est posée dès que le bureau utilisateur est revenu, sans attente fixe.
- Le comportement est le même que celui de yabai, validé depuis des années.
- Le repli public garde Roadie fonctionnel si Apple retire le symbole.

## Conséquences négatives

- Dépendance à un symbole privé non documenté, qui peut changer sans préavis. La résolution par `dlsym` et le repli limitent le risque à une dégradation de réactivité, sans panne.
- Le décodage suppose le format actuel du dictionnaire. Il est isolé dans une fonction pure testée sur des données de test.
