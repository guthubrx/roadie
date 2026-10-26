# Recherche 089

## R1 Couverture visée
Corpus de la 088 (101 workflows, `/tmp/roadie-wf-corpus/couverture.py`) : avec les briques de
cette étape, 93 % ont une entrée complète, 82 % sont entiers, 71 % entiers sans mention d'Alfred.
Briques restantes : vues Texte 9, Remote 4, snippets 3, PDF 2, Grille 2, tampon 1, Image 1.

## R2 Raccourcis
`trigger.hotkey.config` : `argument` (relevé : 0 sélection macOS, 3 texte fixe `argumenttext` ;
1 presse-papiers, 2 « find pasteboard », 4 aucun d'après l'ordre de l'interface d'Alfred, à
confirmer à l'usage), `action` (0 passer à la suite), `modsmode`, `leftcursor`. Les touches ne
sont pas dans `info.plist` (Alfred les garde par Mac ; non attribuées chez l'utilisateur : les 5
raccourcis d'Audio Switcher n'ont que leur argument). Décision : Roadie ne capture pas de touches
(conflits avec Karabiner et BetterTouchTool) ; il liste les raccourcis avec la commande
`roadie workflow run <id> <uid>` à lier dans BetterTouchTool (skill `bettertouch`).
Sélection macOS : attribut AX `kAXSelectedTextAttribute` de l'élément actif, sinon ⌘C simulé avec
presse-papiers sauvé puis remis.

## R3 Déclencheurs
`trigger.external` : `triggerid`. `output.callexternaltrigger` : `externaltriggerid`,
`workflowbundleid` (`self` ou identifiant), `passinputasargument`, `passvariables`.
`trigger.action` : `acceptsmulti`, `filetypes` (UTI, vide = tous), `name`.
`trigger.universalaction` : `acceptsfiles`, `acceptstext`, `acceptsurls`, `acceptsmulti`, `name`.
`trigger.fallback` : `text` avec `{query}`.

## R4 Filtres
`input.listfilter.config.items` : chaîne JSON `[{title, subtitle?, arg, ...}]`, `matchmode`,
`fixedorder`, mot-clé comme un Script Filter. `input.filefilter` : `scopes`, `types` (UTI),
`fields` (`field`, `value` avec `{query}`, `not`, `split`, `words`), `anchorfields`,
`includesystem`, `limit` (0 = défaut), `daterange`, `sortmode`. Traduction en prédicat
`NSMetadataQuery` ; la recherche 077 (`LauncherFileSearch`) est généralisée par ses paramètres.

## R5 Tâches d'automatisation
Dépôt public `alfredapp/automation-tasks` (BSD-3), 563 entrées sous `Tasks/` ; une tâche =
`alfredtask.json` : `script`, `scriptType` (mêmes numéros que R3 de la 088), `configurableConfig`
(variables et défauts), `inputType`, `inputMulti`, `inputOverride`, `outputType`. Le script
appelle des aides communes (`../.common/…`) : dossier courant = dossier de la tâche. Dans un
workflow, `automation.task.config` = `taskuid` (« groupe/sous-groupe/nom ») + `tasksettings`
(valeurs, `{var:…}` permis). Alfred télécharge l'archive signée à la demande ; Roadie télécharge
l'archive publique de la branche `main` dans `~/.roadies/alfred-tasks/` par une commande
explicite, avec la licence BSD gardée à côté.

## R6 Autres briques
`output.dispatchkeycombo` : `keycode` (-1 → `keychar`), `keymod`, `count`,
`overridewithargument` → `CGEvent`. `output.largetype` : `largetypetext`, `font`, `wrapat` →
panneau plein écran simple. `action.terminalcommand` : `script` (+ échappement) → Terminal par
AppleScript `do script`. `action.browseinterminal` : `path`. `automation.runshortcut` :
`shortcut`, `inputmode`, `outputmode` → `/usr/bin/shortcuts run`. `utility.dialog` : `title`,
`description`, `button1..3` → `display dialog` (bouton choisi = sortie). `utility.file` (sortie
UTI) ; `action.browseinalfred` / `action.actioninalfred` (`path`, `jumpto`) → barre rouverte sur
le chemin (mode chemin de la 087) ou sur ses verbes.
