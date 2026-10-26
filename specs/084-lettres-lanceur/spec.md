# Session 084 - Lettres du lanceur

Correction demandée le 26 octobre 2026. Dans le lanceur (Capslock + F), des lettres
précédaient les noms (« FK Finder », « FL Firefox », « GA Firefox »). Maj + K ne faisait
rien et le K ne s'écrivait pas.

## Constats

1. Les lettres venaient du mode cible (SPEC-021/023) : données aux cibles à leur arrivée,
   pas dans l'ordre de la liste du lanceur. D'où un désordre « F G D F D A F ».
2. Au-delà de 9 résultats, chaque cible avait deux lettres (« FK ») : il fallait Maj + F puis
   Maj + K. La lettre déjà tapée dans la recherche ne comptait pas.
3. Maj + une lettre sans étiquette était avalée : la majuscule ne s'écrivait pas.
4. Barre vide : les lettres s'affichaient (lignes de la barre vide) sans être utilisables.
5. La lettre collée au nom gênait la lecture.
6. Après installation, essai réel (06:19 UTC) : Teams, fenêtre 19149, stage 8 du bureau 1 de
   l'écran interne, bureau non affiché. Maj + lettre a donné `targets.activate` action `focus`,
   « focused 19149 » : l'application est passée devant (barre de menus Teams) sans que son
   bureau ni sa stage s'affichent. `WindowCommandService.focus` donne seulement le focus ;
   le sélecteur et les applications du lanceur passent par `switcher.activate`.
7. Des badges verts apparaissaient pour des fenêtres invisibles : stages cachées et autres
   bureaux, à leur dernier cadre connu.

## Exigences

- **FR-001** Une seule lettre par ligne de cible montrée, prise dans `hint_characters`, dans
  l'ordre affiché. Les applications, fichiers et autres lignes n'en ont pas.
- **FR-002** La lettre est une pastille « ⇧K » à droite, au-dessus du rappel ⌘1 à ⌘9 ou de
  « ⇥ actions ↩ » ; le nom n'a plus de préfixe.
- **FR-003** Maj + une lettre affichée ouvre sa ligne, comme ⌘ + chiffre.
- **FR-004** Maj + une lettre non affichée s'écrit dans le champ.
- **FR-005** Barre vide, verbes, destinations et mode commande : aucune lettre.
- **FR-006** À l'écran, seules les cibles qui ont une lettre portent un badge, avec la même lettre.
- **FR-007** Une fenêtre Roadie ouverte depuis le lanceur (Retour, ⌘ + chiffre, Maj + lettre)
  affiche son bureau et sa stage, comme dans le sélecteur.
- **FR-008** Pas de badge à l'écran pour une fenêtre d'une stage non affichée ; sa pastille dans
  la liste reste utilisable.

## Hors périmètre

Les étiquettes du mode cible hors lanceur (`roadie targets`, grille) ne changent pas.
