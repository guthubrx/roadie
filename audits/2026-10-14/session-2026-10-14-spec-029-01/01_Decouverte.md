# Découverte — SPEC-029

Le dépôt contient 250 fichiers source. Le mode détecté est `STANDARD`.
L’audit reste limité aux cinq fichiers Swift modifiés par la feature.

## Chemins chauds

- `Sources/RoadieDaemon/DaemonSnapshot.swift:230` : relevé et réconciliation des fenêtres.
- `Sources/RoadieDaemon/LayoutMaintainer.swift:557` : calcul de la prochaine échéance.
- `Sources/RoadieDaemon/RailController.swift:165` : détection du changement persistant et reconstruction du rail.
- `Sources/RoadieDaemon/StageStore.swift:744` : mutation de l’état de stage.

## Modèle de menace

Les risques sont locaux. Ils concernent l’ordre des notifications Accessibility, le retard de CoreGraphics, les courses entre un relevé et une fermeture, et la compatibilité de l’état JSON existant. Le périmètre ne contient ni réseau, ni authentification, ni paiement, ni PII, ni intégration LLM.

## Périmètre contrôlé

- Sécurité et persistance du nouveau marqueur.
- Complexité des boucles ajoutées.
- Bornes et arrêt des reprises.
- Courses entre notification et relevé.
- Compatibilité du remappage.
- Tests de fermeture, de stage vide, d’ordre, de délai, de limite et de course.
