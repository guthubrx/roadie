# Session 053 - Dépôt fidèle dans le rail

Correction demandée le 21 octobre 2026. Une fenêtre change d'écran mais n'arrive
pas à l'emplacement visé dans le rail ; le même défaut est signalé sur un écran.

## Résultat attendu

- Une carte visée reçoit la fenêtre ; un interstice crée une stage à cet endroit.
- Les cartes et leurs cibles restent fixes entre l'appui et le relâchement.
- La fenêtre est affectée une seule fois, au même écran et à la même destination
  que ceux montrés par l'aperçu. Le défilement conserve des coordonnées correctes.
- Le dépôt sur une stage existante conserve ses autres fenêtres et leur ordre.
- La position d'une nouvelle stage est persistée dans la transaction d'affectation.
- L'ordre reste celui choisi par l'utilisateur. Aucun tri automatique ne déplace
  une carte lorsqu'elle reçoit ou perd une fenêtre. L'utilisateur confirme que
  tous les interstices, le haut et le bas sont des emplacements explicites.

## Hors périmètre

Pas de changement du tuilage, du parking, des raccourcis ou du geste de resize.
Pas de benchmark sur une machine chargée. Ne pas modifier les données utilisateur
pour simuler un dépôt. Preuves visibles uniquement si le bureau est accessible.

## Retour du parcours réel

L'utilisateur confirme plusieurs dépôts corrects puis fournit une capture avec un trou.
La capture (06:29:19Z) suit le départ de X de la stage « Perso » (06:28:51Z) et
précède son remplissage par Firefox (06:29:24Z). La carte nommée vide reste à sa place,
mais `drawEmpty` devient transparent après expiration des libellés.
Une stage vide représentée garde désormais un contour discret, son nom et la mention
« Vide », indépendamment de la temporisation des libellés des stages occupées.
Aucune suppression de stage nommée, aucun changement d'ordre ou de destination.
