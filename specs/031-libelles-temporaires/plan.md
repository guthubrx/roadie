# Plan

1. Conserver la position issue de l'énumération des cartes dans RailPanel.
   La transmettre à StageCardView pour préfixer le libellé existant.
2. Utiliser le même rendu, la même opacité et le même minuteur pour numéro et nom.
   Aucune hauteur réservée ni dessin de badge permanent.
3. Sauvegarder la configuration BTT, puis désactiver uniquement l'ancien trigger
   de grille Alt droite via l'API officielle. Garder Alt gauche dans BTT et
   Alt droite dans Karabiner. Ne pas ajouter de deuxième gestionnaire par touche.
4. Tester dans le worktree isolé, puis combiner dans une copie de livraison
   les modifications actuellement installées de la session parallèle.
   Remplacer exclusivement son ancien rendu du badge par le rendu temporaire.
5. Installer avec l'identité de signature stable, redémarrer proprement et
   vérifier le rail, les scopes et les actions grille/libellés.

Diagnostic : UUID installé F054DC5A-138B-397B-A44B-F6033F87C9A9 identique
au build de la session parallèle. Le dessin drawPosition ignore l'expiration
des libellés. Les deux actions concurrentes Alt droite sont confirmées dans
l'API BTT et le profil Karabiner sélectionné.

Complexité : préfixage O(longueur du nom), aucun scan ou minuteur supplémentaire.
Minimalisme : réemploi des services et de la configuration existants, aucune dépendance.
