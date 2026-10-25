# Session 065 - Fenêtres fermées mais conservées absentes du sélecteur

## Problème

Le sélecteur proposait la fenêtre de réglages d'AlDente (identifiant 781) après sa fermeture.
AlDente garde cette fenêtre en mémoire sans l'afficher. L'inventaire CoreGraphics la liste
encore avec le bon pid. Roadie la considérait donc ouverte. Son activation échouait avec
« Action refusée par l'application » (`switcher activate: restore failed`), dans le sélecteur
et dans la vue d'ensemble.

## Comportement attendu

Une fenêtre absente de l'écran est écartée du sélecteur et de la vue d'ensemble si :
- son application répond à l'accessibilité sans la lister ;
- son application n'est pas cachée ;
- SkyLight ne la rattache à aucun bureau.

Restent listées : fenêtres d'un autre bureau, fenêtres réduites, applications cachées,
applications sans réponse d'accessibilité, et toutes les fenêtres si SkyLight ne répond pas.
