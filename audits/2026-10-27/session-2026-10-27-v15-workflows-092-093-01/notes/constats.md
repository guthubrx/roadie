# Constats

## F1 MEDIUM, corrigé - fichier JavaScript traduit lu comme de l'AppleScript
`AlfredBridge.OsascriptCall.rebuilt` remplaçait le fichier par `-e` sans `-l` : `osascript fichier.js`
qui donne un ordre à Alfred échouait (erreur -2740) alors que l'appel direct réussissait.
Reproduction avant correction : `notes/avant-F1-reproduction.txt`, code : `notes/avant-F1-rebuilt.swift.txt`.
Correction : `-l JavaScript` ajouté quand le fichier est `.js`/`.jxa` sans `-l`. Test
`auditFixesKeepJavaScriptFilesAndRunning` (reconstruction et exécution réelle).

## F2 LOW, corrigé - réglage gardé sans workflow
`AlfredKeptSettings.set/remove` avec un identifiant vide (`inWorkflow` absent d'un workflow sans
`bundleid`) écrivait `~/.roadies/workflows-settings/.json`. Correction : erreur `MissingWorkflow`, rien
n'est écrit. Test `keptSettingsNeedAWorkflow`. Preuve par lecture du code (chemin `file("")`) et test.

## F3 LOW, corrigé - `running()` absent de l'objet JavaScript
Un script `Application("com.runningwithcrayons.Alfred").running()` s'arrêtait sur une TypeError après
traduction (appel direct : `true`). Reproduction : `notes/avant-F3-reproduction.txt`. Correction :
`running()` rend vrai (Roadie sert les ordres) ; compté « traduit » dans la fiche. Test réel.

## Écarts relevés et tranchés pendant les sessions (hors findings)
- Converge 092 : fiche muette sur une source de grille inconnue (T013, corrigé avant l'audit).
- Converge 093 : FR-007 précisé pour `version`/`activate`/`quit` (aucune commande lancée).
- Mesure 093 corrigée : 12 workflows à ordres exécutés, non 13 (aide et agent `launchd` exclus).
