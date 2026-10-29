# Validation 121 : icône de l'application dans le sélecteur

- 5 tests `Spec121SwitcherIconTests` (défauts et bornes, taille automatique, place de l'icône et du titre, icône
  désactivée, taille choisie qui agrandit les cartes) ; comptes du catalogue et listes Spec056 mis à jour.
- Rendu contrôlé sur des cartes fictives dessinées dans une fenêtre hors écran : automatique, sans icône, 64 points,
  présentation compacte, liste. Un premier rendu sans fenêtre montrait des carrés vides : artefact du dessin
  hors fenêtre, les cadres et images relevés étant corrects.
- Suite complète : 2 257 tests / 325 suites réussis ; 28 tests de scripts réussis.
- Non vérifié à l'écran avec de vraies fenêtres : les clics et touches simulés sont refusés sur ce poste, donc pas
  de diaporama ; l'essai réel revient à l'utilisateur.
