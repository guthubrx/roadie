# Session 105 - Fin des fonctions en partie reprises d'Alfred

## Demande

« Finir toutes les fonctionnalités qui sont en partie développées » (tableau des priorités de
`docs/analyses/2026-10-25-reference-alfred.html`, état « en partie »).

## Exigences

- FR-001 Commandes système : verrouiller, suspendre les écrans, suspendre l'activité, économiseur,
  tout quitter (sauf le Finder et Roadie), afficher et vider la corbeille, tout éjecter, son plus fort,
  moins fort, muet, fermer la session, redémarrer, éteindre. Section « Système » dès deux lettres ;
  second Retour pour les commandes lourdes (`confirm_quit_all` pour Tout quitter).
- FR-002 Verbe « Forcer à quitter » d'une application.
- FR-003 Portée des applications : `app_search_paths`, dossiers ajoutés aux dossiers de macOS.
- FR-004 Navigation dans les dossiers : ⌫ en fin de `…/` remonte d'un dossier ; `path_sort` trie par nom,
  date de modification ou de création, dossiers en tête. (Fichiers cachés : déjà montrés dès `.`.)
- FR-005 Grand texte : ⌘L montre la ligne choisie en très grands caractères et ferme la barre.
- FR-006 Apprentissage : `learning_enabled` ; `roadie launcher reset` efface le classement appris.
- FR-007 Thème, flou et nombre de résultats (session 101) ; écran et place de la barre (session 102).
- FR-008 Calculatrice : sinh, cosh, tanh, asinh, acosh, atanh, trunc, rint, near, dtor, rtod.
- FR-009 ⌘⎋ ferme la barre d'un coup ; ⎋ revient toujours d'une étape.
