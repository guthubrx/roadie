# 047 - Fenêtre flottante dans sa stage

Demande validée le 18 octobre 2026, après comparaison avec TrellisWM 0.9.5
(« Docks and floats windows »). La commande `roadie toggle floating` existe
dans l'aide mais renvoie « not implemented ».

## Besoin

L'utilisateur veut sortir une seule fenêtre du tuilage, la placer à la main,
puis la remettre dans le tuilage, sans règle de configuration et sans passer
toute la stage en mode `float`.

## Exigences

- R1 `roadie toggle floating` agit sur la fenêtre active gérée. Si elle est
  tuilée, elle devient flottante. Si elle flotte déjà, elle revient au tuilage.
- R2 Une fenêtre flottante sort de l'arbre : les autres fenêtres de la stage
  reprennent sa place. Sa taille et sa position ne sont plus imposées.
- R3 Elle reste rattachée à sa stage : visible quand sa stage est active,
  masquée quand on passe à une autre stage, au même cadre au retour.
- R4 L'état survit au redémarrage du daemon. Il disparaît avec la fenêtre,
  après le délai de grâce déjà appliqué aux épinglages.
- R5 Le menu « Fenêtre » de la barre de titre propose « Flotter dans cette stage »
  et indique l'état courant. Les épinglages existants restent inchangés.
- R6 Sur une fenêtre déjà épinglée sur un desktop ou sur tous les desktops,
  `toggle floating` retire l'épinglage et la rend au tuilage.
- R7 Sans fenêtre active gérée, la commande ne change rien et le dit.

## Hors périmètre

Zone « Desktop » de Trellis, mode flottant global, raccourci par défaut,
`window close`. Le raccourci reste à poser dans BTT ou Karabiner.

## Critères de réussite

- Les tests couvrent R1 à R7 sans régression des épinglages existants.
- `roadie toggle floating` n'apparaît plus comme non implémentée.
- Guides FR/EN et changelog décrivent la commande.
