# Session 108 - Raccourcis réunis, réglables par appui, Roadie ou BetterTouchTool

## Demande

« ⌘L ne fait rien, intercepté par Karabiner ou BTT ? » ; une catégorie des paramètres qui réunit tous les
raccourcis, chacun réglable par appui sur les touches, avec le choix de qui les prend (Roadie ou BTT) ; les
raccourcis de BTT inclus seulement si BTT est installé ; pour chaque conflit, le choix entre mettre BTT en
pause et changer la touche de Roadie.

## Diagnostic

BTT a un raccourci global ⌘L (`roadie focus right`, série ⌘H/J/K/L) qui prend la touche avant la barre ;
l'interception de la barre, en tête de session, ne la reçoit jamais. ⌥↑ et ⌥↓ (sélection multiple) sont
aussi pris par BTT (`stage switch-visible`). Le journal de Roadie n'avait aucun événement de grand texte.

## Exigences

- FR-001 Catégorie « Raccourcis » : raccourcis globaux de Roadie (recherche, verbes, vue d'ensemble), touches
  de la barre, touche des présentations, touche des chiffres, touches de la grille, profils du sélecteur et
  commandes Roadie. Ils quittent Recherche, Vue d'ensemble et Grille.
- FR-002 Toute touche se règle par appui (`ShortcutRecorderControl`) ; celles de la grille acceptent une touche seule.
- FR-003 Douze touches de la barre réglables (`<action>_key` dans `experimental.target_mode`) : grand texte,
  copier, aperçu, garder l'action, règle, fermer, tout fermer et les cinq touches de la sélection multiple.
  Vide : désactivée. ⌘C copie le texte sélectionné s'il y en a un.
- FR-004 Conflits : chaque touche de Roadie prise par un raccourci BTT actif est signalée, avec le raccourci
  BTT et son dossier. Pour une touche de la barre, l'interrupteur « BTT en pause tant que la barre est ouverte »
  l'ajoute à `btt_pause_keys`.
- FR-005 Pause : à l'ouverture de la barre, Roadie désactive les raccourcis BTT actifs de ces combinaisons ;
  à la fermeture, il les réactive. Les identifiants en pause sont écrits dans `~/.roadies/btt-paused.json` et
  réactivés au démarrage suivant si Roadie s'est arrêté barre ouverte.
- FR-006 Commandes Roadie : les raccourcis BTT qui lancent `roadie …` (sauf le sélecteur, géré par ses profils)
  et les entrées `[[shortcuts]]`, avec combinaison et gestionnaire : BetterTouchTool, Roadie ou personne.
  Roadie : entrée `[[shortcuts]]` (clé `btt_uuid`) enregistrée par Carbon, commande exécutée par le routeur du
  socket, raccourci BTT désactivé. Retour à BTT : raccourci BTT réactivé ou créé. Nouveau raccourci de commande
  ajoutable. Liste affichée seulement si BTT est installé ; ouvrir BTT est demandé s'il ne tourne pas.
- FR-007 La recherche des paramètres trouve aussi les commandes (« focus right »).

## Limites

- Une combinaison prise par BTT ne peut pas être enregistrée par appui tant que BTT la prend (même cause que ⌘L).
- Réactivation à la fermeture : un raccourci BTT désactivé à la main pendant que la barre était ouverte est réactivé.
- Les raccourcis de Karabiner (Hyper, Contrôle droit) ne sont pas lus.
