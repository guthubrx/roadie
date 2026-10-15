# Session 029 - Redimensionnement fiable et rail cohérent

Statut : validée le 15 octobre 2026, en cours.
Tests : en préparation.

## Besoin utilisateur

À deux ou quatre fenêtres, une taille modifiée à la souris peut revenir à sa
valeur précédente. Le rail identifie mal les stages et peut proposer des
destinations incohérentes. Après un changement d’écran, leur ordre peut changer
et des restaurations répétées perturbent l’affichage.

## Exigences

- R1 : conserver un geste valide jusqu’à sa prise en compte, y compris pendant
  une garde temporaire ou si la taille finale arrive après le relâchement.
  Respecter les tailles minimales réelles et le partage en tuiles ; un bord
  extérieur ne crée pas une disposition libre implicite.
- R2 : utiliser le même ordre visible pour les cartes du rail, les menus d’envoi
  et les commandes par position. Conserver les identifiants et noms personnels.
  Garder un repère lisible même lorsque les noms temporaires sont masqués.
- R3 : retrouver l’ordre d’origine après déconnexion et reconnexion d’un écran,
  sans fusion de membres, perte de stage ou suppression d’une modification faite
  entre-temps par l’utilisateur.
- R4 : borner les reprises de restauration et de masquage après un échec. Ne pas
  lancer une boucle de stabilité sur une fenêtre inchangée qui refuse l’action.
  Une nouvelle géométrie ou une nouvelle action permet une nouvelle tentative.
- R5 : préserver les réglages, les stages, leurs fenêtres et les garanties du
  focus, du plein écran, des gestes, des échos AX et de la fermeture de recherche.

## Critères de validation

Reproductions ciblées des défauts avant correction, tests Swift déterministes
des gestes tardifs/suspendus, positions avec membres absents, parking aller-retour
et échecs répétés. Suite complète, revue indépendante, installation signée,
santé et essai réel des redimensionnements et du rail.

## Limites

Aucune remise à zéro de l’état ni réorganisation automatique des stages existants.
Aucune nouvelle dépendance ni publication de version. La configuration personnelle
reste intacte ; les migrations éventuelles conservent les champs existants.
