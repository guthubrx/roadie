# Validation 124 : documentation du lanceur

- Neuf captures produites par `ROADIE_DOC_SHOTS_DIR=… scripts/test --no-parallel --filter Spec124` (4 tests), relues
  une à une ; compressées avec pngquant (12 Mo → 2,1 Mo), métadonnées retirées. Contenu : applications d'Apple,
  titres et fichiers inventés, fond synthétique. Aucune capture de l'écran, du fond d'écran ni des fenêtres réelles.
- Liens, images et ancres des README et des guides vérifiés par script : 0 problème.
- Faits vérifiés dans le code : raccourci par défaut ⌘⌃⌥F, mots de position `gauche`/`left`, verbes d'une
  application, libellés des sections ; corpus de workflows 92 complets sur 102 (specs/120-remote-cache).
- Seul changement de code : `WindowSwitcherPanel.appIcons` réglable (icônes d'exemple dans le rendu hors écran).
- Suite complète : 2 268 tests / 330 suites réussis.
- Pas de diaporama : documentation seulement, aucun comportement visible modifié.

## Complément du 29 octobre 2026
- Demande : la capture « note » montrait « 6 » sans la pastille de présentation de la vraie barre ; ajouter une
  capture en liste et une en grille, avec des émojis.
- `launcher-search.png` montre maintenant « ☰ Liste 6 », comme la barre réelle (source `files`, session 099).
- Nouvelles captures : `launcher-files-grid.png` (même recherche après ⌘G, fichiers seuls) et
  `launcher-emoji-grid.png` (workflow d'émojis en grille, nom en pied). La grille des Réglages Système
  (`launcher-grid.png`) est retirée.
- Provenance : rendu de Roadie, fichiers vides de types courants, émojis dessinés par la police du système.
  Aucune image d'Alfred. Les seuls éléments repris d'Alfred sont les valeurs de ses thèmes (couleurs, tailles),
  sous leurs noms d'origine, dans `launcher-themes.png`.
- Contrôle : chaque image relue à l'écran ; aucune icône ne trahit une application par défaut de ce Mac.
