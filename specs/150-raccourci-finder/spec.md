# 150 — Rétablir ⌘E pour Finder

⌘E ouvre une fenêtre Finder si aucune n’existe. Sinon il ramène une fenêtre Finder existante dans la stage active du bureau affiché sur l’écran où se trouve la souris. Un nouvel appui réutilise cette fenêtre. Le raccourci est global, sans dépendre de l’application qui a le clavier.
L’ancien raccourci BetterTouchTool appelle seulement Open Finder dans le groupe « Tout sauf photoshop ». Le correctif réutilise launch --here et ajoute --mouse pour figer la destination sans dépendre du focus. Le daemon ne change ni les règles ni les proportions de tuilage.
