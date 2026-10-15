# Contrat : projection commune du rail (R2)

Source : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StagePresentationOrder.swift. Le nom historique de ce contrat ne dicte pas le nom du type.

## Projection

`StagePresentationOrder` fournit le même ordre et les mêmes positions aux cartes, menus d’envoi, actions de contexte et commandes par position.

- Inclure les stages ayant un membre vivant ou représenté sous la grâce existante de 15 s.
- Inclure aussi les stages vides nommés par l’utilisateur, pour qu’ils restent accessibles.
- Conserver l’ordre du scope et les noms personnels. Ne jamais renuméroter les `StageID` utilisés par la CLI.
- Placer les vides automatiques après la projection visible pour le repli d’affectation. Un stage vide nommé ne doit pas créer une seconde destination fantôme.
- Ne dépendre ni de l’opacité ni du fondu des libellés.
- Pour un autre bureau, conserver les destinations persistées non vides ou nommées : le relevé vivant porte sur le bureau courant seulement.

## Présentation

Le badge de position est toujours lisible, y compris quand le nom est pleinement visible. Il reste présent après le fondu. Un menu affiche par exemple « 2 · Perso ». La carte, le menu et la commande par position désignent le même stage pour ce numéro. Aucun réglage nouveau.

Le type est pur et ne persiste aucun état. La règle de membre représenté doit être réutilisée, sans copie concurrente. Coût attendu O(s + m), pour s stages et m membres.

## Consommateurs et preuves

Intégration dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailController.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailPanel.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCommands.swift et /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/WindowContextActions.swift. Le lot rail modifie aussi /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCardView.swift : une zone réservée au numéro évite superposition et coupure aux polices 8/16/48 et à la largeur 90.

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029RailTests.swift vérifie positions identiques, grâce de 15 s, vides nommés, repli automatique, autres bureaux et identifiants inchangés. Adapter les assertions de /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift aux libellés numérotés. Le rendu lisible du badge est vérifié sur l’installation réelle.
