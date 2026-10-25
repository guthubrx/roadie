# Validation 082

## Tests
- `Spec082OpenItemsTests` (4 tests) : lecture de la sortie AppleScript (ligne cassée ignorée, titre
  avec tabulation), fenêtre d'un onglet retrouvée par son cadre (2 points), script seulement pour les
  navigateurs scriptables (pas Firefox), script de sélection d'onglet, recherche par nom, titre ou
  adresse (3 lettres au moins pour l'adresse), section « Documents et onglets ».
- Suite complète : 2 028 tests / 277 suites réussis.

## Essai réel
- Document TextEdit placé dans la stage d'essai 80 puis caché (retour à la stage 2) ;
  `roadie launch --open-items` : `document:com.apple.TextEdit 1` (comptes seuls, sans titre).
- Onglets non relevés en réel : la lecture déclencherait les demandes d'autorisation
  d'automatisation de Chrome et Brave en l'absence de l'utilisateur. Elles apparaîtront à la
  première ouverture de la barre.
- Document fermé avant de quitter TextEdit, fichier supprimé ; installation signée, santé 5/5.

## Limites
- Firefox : ni document ni onglets exposés.
- Sélection d'un onglet et passage devant non essayés en réel (autorisation à donner).
- Onglets relus à chaque ouverture de la barre (2 s au plus par navigateur, en fond).
