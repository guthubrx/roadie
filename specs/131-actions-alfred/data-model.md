# Modèle de données 131

- **LauncherSubject.text(String)** : texte tapé ou sélectionné. Adresses dérivées à la demande (non stockées).
- **LauncherVerb** (ajouts) : fichier `copyFile`, `copyTo`, `moveTo`, `copyReplace`, `moveReplace`, `openWith`,
  `email`, `trash`, `makeAlias`, `info`, `tag`, `browse`, `terminalHere`, `packageContents` ; texte `copyText`,
  `webSearch`, `openURL`, `extractURLs`, `emailText`, `largeType` ; onglet `closeTab`, `copyURL`, `newWindowTab` ;
  application `relaunch`, `quitOthers` ; workflow `universal(entry)` (actions universelles).
- **LauncherDestination.Kind** (ajouts) : `.folder(path)`, `.application(path)`, `.tag(name)`.
- **ReturnModifiers** : effet de ⌘, ⌥, ⌃ (`new-stage`, `here`, `send`, `web`, `copy`, `reveal`, `quicklook`,
  `verbs`).
- **AlfredSystemCommand** : numéro → commande (table R2) ; **AlfredMusicCommand** : numéro → commande (table R3).
- **MenuItemEntry** : chemin (titres), élément AX, activé.
- **SymbolEntry** : nom, catégories, mots-clés, année ; versions par système issues de `year_to_release`.
- **AppsPins** : identifiants d'applications épinglées, dans l'ordre.
- **WorkflowViewStyle** : `theme`, `glassy-dark`, `flat-dark`, `glassy-light`.
- **AlfredMarkdown.Block.table** : en-têtes, alignements, lignes.
