# Plan - Session 132

- **Où** : une pièce `FloatingPlacement` (`Sources/RoadieDaemon/FloatingPlacement.swift`) appelée par
  `LayoutMaintainer.tick` après la garde « bouton enfoncé » : jamais pendant un glisser, et une seule écriture
  par fenêtre apparue (`SnapshotService.setFrame`, budget d'écriture habituel).
- **Fenêtres concernées** : sans stage (`scope == nil`), non tuilables, sous-rôle `AXStandardWindow` ou
  `AXDialog`, d'un autre processus que Roadie.
- **Décision** : fonction pure `placement(for:displays:railWidth:avoidRail:remembered:)`. Place retenue si
  son point haut-centre est sur un écran branché ; sinon décalage à `écran.minX + largeur du rail + 8` si la
  fenêtre commence sur la bande du rail et tient à droite. Rail : bord gauche de chaque écran, largeur de
  `[fx.rail] width` (lue seulement à l'apparition d'une fenêtre).
- **Mémoire** : `~/.roadies/floating-frames.json`, identifiant de règle → cadre ; clé = première règle
  trouvée (`WindowRuleMatcher.firstMatch`) si son action a `remember_frame = true`. Les lignes
  `[[exclusions.floating_windows]]` deviennent des règles `float-title-…` qui portent l'option.
- **Démarrage** : premier appel = relevé sans déplacement.
- **Réglages** : `[exclusions] floating_avoid_rail` (vrai), `remember_frame` dans les lignes et les règles ;
  éditeurs génériques de Paramètres > Règles (champ booléen).
- **Complexité** : O(n) par passe (n fenêtres flottantes) ; O(r log r) par fenêtre apparue.
- **Dépendances** : aucune nouvelle.
