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
