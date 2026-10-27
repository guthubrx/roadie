# Recherche 093 - Ordres à Alfred

## R1 Formes relevées (corpus de 102, 27 octobre 2026)
AppleScript : `tell application id "com.runningwithcrayons.Alfred" to return version` (1Password,
Google Drive), `… to run trigger "build" in workflow "…"` (Alias Homebrew, dans un `-e "…"` avec
`\"`), `… to reload workflow (system attribute "alfred_workflow_bundleid")` (AppleScript
Dictionaries, Clipboard History Extender, Notes), `tell application "Alfred" to search "hue $action"`
(Hue), `tell application "Alfred 2" to search "|f "` (Funnel), `tell application "Alfred 4" to run
trigger "remind" in workflow "…" with argument "…"` (Reminders, texte d'aide).
JavaScript : `Application("com.runningwithcrayons.Alfred").runTrigger(n, { inWorkflow, withArgument })`
(1Password, Backup Preferences, System Settings Explorer), `.setConfiguration(k, { toValue, inWorkflow,
exportable })` (Obsidian, Calculate Anything), `.removeConfiguration(k, { inWorkflow })`,
`.search(t)` (System Settings Explorer), `.reloadWorkflow(id)`, `.revealWorkflow(id[, options])`
(Workflow Actions), `.activate()`, `.quit()` (Backup Preferences), objet gardé dans une constante
(`const alfred = Application("…")`).
Tous dans `info.plist` ; aucun dans un fichier séparé. Les `osascript` sont appelés par leur nom ou
par `/usr/bin/osascript`.

## R2 Mécanisme
Options examinées :
- Faire de Roadie une application scriptable au dictionnaire d'Alfred (sdef, commandes Cocoa) et
  réécrire l'identifiant : fidèle, mais lourd (dictionnaire, classes de commande, consentement
  Automatisation) ; écarté.
- Gestionnaires d'événements bruts aux codes d'Alfred : la compilation des termes exige Alfred
  installé ; écarté.
- **Retenu** : traduction de texte. AppleScript : l'ordre devient `do shell script "<roadie> workflow
  alfred …" & quoted form of (<expression>)` ; les expressions restent évaluées par AppleScript.
  JavaScript : `Application("<Alfred>")` devient `__roadieAlfred`, objet défini en tête du script, dont
  les méthodes appellent `doShellScript` de l'application courante (ajouts standard). La commande
  `roadie workflow alfred` exécute l'ordre (barre et déclencheur par le démon, réglages et dossier
  directement).
- Shell : un exécutable `osascript` de Roadie, en tête du `PATH`, appelle `roadie workflow osascript`
  qui traduit puis lance `/usr/bin/osascript` avec les mêmes options. `/usr/bin/osascript` suivi d'une
  espace est remplacé dans le texte du script quand il cite Alfred ; la condition « suivi d'une espace »
  évite les chemins écrits dans des fichiers (1Password écrit un plist d'agent avec
  `<string>/usr/bin/osascript</string>`).

## R3 Chemin de la commande
`BTTShortcutBindingService.executable` : `~/.local/bin/roadie` (installé par `make install`).
Repris tel quel. L'exécutable `osascript` est écrit une fois par processus dans
`~/Library/Caches/roadie/alfred-bridge/` (mode 755).

## R4 Réglages gardés
Alfred écrit `set configuration` dans la configuration du workflow (`prefs.plist` ou variables).
Roadie ne modifie jamais le dossier d'Alfred : `~/.roadies/workflows-settings/<identifiant>.json`,
fusionné après `prefs.plist` au chargement ; sa date entre dans le cache de l'index, donc
`reload workflow` n'a rien d'autre à faire que toucher ce fichier ou rien (relu si changé).

## R5 Version
`AlfredScriptRunner.alfredVersion` (Alfred installé, sinon 5.5) : même valeur que `alfred_version`.

## R6 Fiche
Détection des ordres par les mêmes motifs que la traduction (une seule source de vérité) : un ordre
reconnu est « traduit », une forme `tell application "<Alfred>"` ou `Application("<Alfred>")` dont
l'ordre n'est pas reconnu est « non traduit ». Une mention sans ces formes n'est rien.
