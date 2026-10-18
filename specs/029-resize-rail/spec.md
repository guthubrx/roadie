# Session 029 - Redimensionnement fiable et rail cohérent

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

Statut : correction complémentaire en cours après essai manuel non concluant, le 15 octobre 2026.
Derniers résultats avec récupération du callback perdu : 1 526 tests Swift dans 163 suites passent en 7,170 s.
Les scripts sont inchangés ; leurs 26 tests passaient lors de la vérification précédente.
Revue ciblée 5 terminée, sans blocage prouvé. Garde-fou de callback perdu testé. Installation finale signée et redémarrée, quatre contrôles de santé réussis. Nouvel essai utilisateur en attente ; résolution native non encore confirmée.

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
  Une nouvelle session de souris remplace l’attente précédente ; une seule
  interaction reste en attente à la fois. Le scheduler et le mainteneur bloquent
  toute reprise du tuilage tant qu’un bouton physique est pressé OU que la session
  de souris reste ouverte. Un callback de relâchement perdu peut être rattrapé
  après un seuil de 300 ms depuis le premier relâchement physique observé, sans
  timeout sur un bouton maintenu ni double consommation sur callback tardif.
  Ce repli dépend des événements ou du filet périodique existant ; le seuil ne
  garantit pas une exécution à exactement 300 ms.
  Une poignée devant un fond inéligible reste accessible ; un vrai obstacle
  au premier plan bloque la fenêtre derrière lui.
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
