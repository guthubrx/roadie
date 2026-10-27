# Spécification 094 - Recherche web : `^` retiré et navigateur au premier plan ; ordre appris en grille

Demande du 27 octobre 2026, après essai : « on doit enlever le ^ avant d'envoyer la recherche. Par
ailleurs il faudrait qu'on bascule vers le navigateur qui reçoit la recherche, là je suis resté sur la
même stage » ; « ordre appris : oui aussi en grille ». Corrections de la 090 (validation automatique)
et réglage « Sorting » de la grille d'Alfred (accord explicite).

## Constat
- `^claude` a cherché « ^claude » sur Google. La barre affiche « ⌃ ↩ Rechercher … sur le web » ; ⌃
  (Contrôle) se lit `^`. Rien dans Roadie ne traitait ce caractère.
- Après une recherche web, le navigateur prend l'onglet dans sa fenêtre, rangée dans une autre stage :
  Roadie restait sur la stage affichée.
- La grille gardait toujours l'ordre du script, même quand le workflow demande l'ordre appris
  (`fixedorder` faux, « Alfred learns result order based on usage »).

## Exigences
- **FR-001** Un `^` en tête de saisie est retiré du texte envoyé au moteur (lignes « Web », ⌃ Retour) ;
  `^texte` place les recherches web en tête de la liste, la première choisie. Un `^` ailleurs reste.
- **FR-002** Après l'ouverture d'une adresse ou d'une recherche depuis la barre (ligne Web, adresse
  tapée, ⌃ Retour), Roadie va à la fenêtre du navigateur qui l'a reçue, dans sa stage et son bureau :
  fenêtre active du navigateur passé au premier plan, sinon sa fenêtre préférée (règle de lancement).
- **FR-003** Grille : si `fixedorder` est faux et que la réponse ne demande pas `skipknowledge`, les
  tuiles à `uid` sont classées par les choix après cette saisie, ou sans saisie par fréquence-récence ;
  sinon, et pour les tuiles sans `uid`, l'ordre du script (comme Alfred). La présélection reste prioritaire
  à l'ouverture.

## Critères de réussite
- SC-001 `^claude` puis Retour : Google cherche « claude » et Roadie montre la fenêtre du navigateur.
- SC-002 Tests : texte sans `^`, URL encodée, ⌃ Retour, section en tête, ordre appris et réglage lu.

## Hors périmètre
Ouvertures d'adresse par les workflows (brique Open URL) ; forme des images (`imageaspect`) ; texte
d'attente de la grille ; ordre des listes de Script Filters (inchangé).
