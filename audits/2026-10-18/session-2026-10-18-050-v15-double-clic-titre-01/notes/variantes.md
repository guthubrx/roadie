# Recherche de variantes - session 050 readonly

Racine : `/private/tmp/roadie-audit-050`.

## Commentaire `///` séparé de sa déclaration (F2)
Motif : lignes `///` suivies d'une autre déclaration documentée dans les fichiers du diff
(`DaemonHealth.swift`, `TitlebarContextMenuController.swift`, `Config.swift`, `SettingsCatalog.swift`),
relecture des hunks ajoutés. Seul site : `DaemonHealth.swift:61-63`.

## Défaut d'une option qui change un diagnostic existant (F1)
`git diff 3dd5563b..8c207d67 -- Sources` : seule `doubleClickMaximize` (défaut `true`) alimente un
contrôle de santé. Les autres options ajoutées : aucune.

## Validation non consignée (F3)
`ls specs/05*/validation.md specs/04[89]*/validation.md` : 048 et 051 en ont un ; 049 et 050 non.

## Action Roadie pendant une session de geste ouverte (H1)
Autres actions déclenchées par un appui gauche pendant une session : glisser de dépôt du rail
(consomme le geste, `RailController.swift:882`, `DropPreviewController.swift:623`). Le double-clic ne
consomme pas le geste ; la reproduction montre que la maximisation n'est pas adoptée.
