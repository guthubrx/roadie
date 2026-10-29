# Audit de reutilisation de l'existant — 131 actions Alfred et Alfred 6

## Decision

Statut: PASS
Date: 2026-10-29
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/131-actions-alfred

Conclusion courte: aucune duplication evidente. Le plan etend la grammaire du lanceur, le moteur de workflows,
les commandes systeme et les themes existants ; les six fichiers nouveaux portent des responsabilites absentes du
code (operations de fichier, texte, menus AX, SF Symbols, Apps, briques systeme d'Alfred). Les existants proches
sont reutilises et listes ci-dessous.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 16 |
| Items audites | 16 |
| Reutilisations deja prevues | 10 |
| Existants potentiellement pertinents | 7 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 6 |
| Specs existantes applicables | 10 |

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Verbes et destinations | `LauncherVerb`, `LauncherDestination`, `LauncherSubject` | `Sources/RoadieDaemon/LauncherActions.swift:7`, `:71`, `:223` | etendus, pas recrees |
| Execution des verbes | `perform(_:)`, `performFile`, `performURL` | `Sources/RoadieDaemon/TargetModeRuntimeController.swift:1013` | branchement des nouveaux cas |
| Selection multiple | verbes de selection (SPEC-091) | `Sources/RoadieDaemon/LauncherSelection.swift:78` | verbes de fichier aussi en lot |
| Commandes systeme | `LauncherSystemCommand` (105, 129) | `Sources/RoadieDaemon/LauncherSystemCommands.swift:7` | ajout de commandes et brique `action.systemcommand` |
| Themes de barre | `LauncherTheme.builtIn` | `Sources/RoadieDaemon/LauncherTheme.swift:104` | deux themes ajoutes |
| Markdown de la vue Texte | `AlfredMarkdown` | `Sources/RoadieDaemon/AlfredTextView.swift:140` | bloc tableau ajoute |
| Raccourcis Apple | `shortcut(_:input:)` | `Sources/RoadieDaemon/AlfredLiveEffects.swift:191` | lancement depuis la barre |
| Taches d'automatisation | `AlfredAutomationTasks.update` | `Sources/RoadieDaemon/AlfredAutomationTasks.swift:65` | appelee a la premiere absence |
| Catalogue d'applications | `LauncherAppCatalog` | `Sources/RoadieDaemon/LauncherAppCatalog.swift:18` | source de la grille Apps et de « Ouvrir avec » |
| Texte selectionne | `selectedText()` | `Sources/RoadieDaemon/TargetModeRuntimeController.swift:904` | rendu accessible pour `targets.actions` |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Afficher en grand | `LargeTypePanel` | `Sources/RoadieDaemon/AlfredLiveEffects.swift:228` | reutiliser (aucun nouveau panneau) |
| Ouvrir un terminal ici | `terminal(folder:)` | `Sources/RoadieDaemon/AlfredLiveEffects.swift:183` | reutiliser |
| Parcourir dans la barre | `LauncherPathRules` (`~/dossier`) | `Sources/RoadieDaemon/LauncherPath.swift:16` | reutiliser : le verbe remplit la saisie |
| Choix d'un onglet Firefox | `FirefoxTabSelector` | `Sources/RoadieDaemon/LauncherOpenItems.swift:152` | reutiliser pour fermer l'onglet |
| Grille de la barre | `presentGrid` (092, 099) | `Sources/RoadieDaemon/TargetModeRuntimeController.swift:937` | reutiliser pour Apps |
| Lancement osascript borne | `LauncherBrowsers.run` | `Sources/RoadieDaemon/LauncherOpenItems.swift:129` | reutiliser (Musique, onglets, mode sombre) |
| Remplacement atomique | `StagedFileReplacement` | `Sources/RoadieDaemon/StagedFileReplacement.swift:18` | non retenu : « en remplaçant » d'Alfred met l'ancien a la corbeille, pas un echange |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| aucune | - | recherches ci-dessous | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| `~/.speckit/constitution.md` XVIII | complexite annotee, pas de recherche lineaire repetee | listes de symboles et d'apps preparees une fois |
| `~/.speckit/constitution.md` XIX | extension avant creation | fichiers nouveaux limites a des responsabilites absentes |
| `AGENTS.md` (sessions 126, 127) | textes FR/EN par `tr`, tests en francais | toutes les chaines ajoutees |
| memoire `roadie-ui-language` | Roadie en anglais chez l'utilisateur | captures et essais en anglais |
| memoire `roadie-install-signing` | installation signee `roadied-cert` | livraison par `make install` |
| memoire `roadie-stale-test-build` | signal 11 : supprimer le `.build` des tests | procedure connue |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 074 | objet → verbe → destination | grammaire etendue |
| 075 | variantes ⌘ ⌥ ⌃ + Retour | rendues reglables |
| 077 | fichiers par Spotlight, verbes Finder/Quick Look/chemin | verbes ajoutes |
| 082, 104 | onglets ouverts, Firefox par sa session | verbes d'onglet |
| 088-093 | moteur de workflows, actions universelles | briques et actions texte/adresse |
| 091 | selection multiple | verbes en lot |
| 101 | themes d'Alfred | themes en verre |
| 105, 129 | commandes systeme, echecs signales | commandes ajoutees |
| 117, 118 | vues Texte, Image, PDF | tableaux, styles |
| 126, 127 | langue | FR/EN |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `rg -n 'trashItem\|writeBookmarkData\|tagNames\|SHA256'` | `Sources/` | aucun |
| `rg -n 'NSDataDetector\|composeEmail\|NSSharingService'` | `Sources/` | aucun |
| `rg -n 'AXMenuBar\|kAXMenuBarAttribute'` | `Sources/` | aucun |
| `rg -n 'LSApplicationCategoryType\|screencapture\|DCSCopyTextDefinition\|NSTextTable'` | `Sources/` | aucun |
| `rg -n 'systemSymbolName'` | `Sources/` | icones d'interface seulement, pas de navigateur |
| `rg -n '/usr/bin/shortcuts'` | `Sources/` | `AlfredLiveEffects.swift:204` (reutilise) |
| `rg -n 'func largeType\|func terminal\(folder\|LauncherPathRules\|static func update'` | `Sources/RoadieDaemon` | reutilisations listees |
| `rg -n 'copyItem\(at\|moveItem'` | `Sources/` | persistance et workflows seulement |
| `rg -n 'pinned\|Pinned'` | `Sources/` | rail seulement, pas d'epinglage d'applications |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| Panneau SF Symbols | creer nouveau | aperçu a droite et versions par systeme absents de la barre | 2026-10-29 |
| « En remplaçant » | creer (corbeille puis copie) | comportement d'Alfred ; `StagedFileReplacement` est un echange de dossier interne | 2026-10-29 |

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees
