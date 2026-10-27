# Variantes

## F1 (langue perdue à la reconstruction)
Motifs : `"-l"`, `-l JavaScript`, `isJavaScript`, appels à `osascript` dans `Sources/RoadieDaemon`.
Témoins : `AlfredScriptRunner.argv` types 6 et 7 passent `-l` explicitement (sain) ; passage sans
traduction de l'`osascript` de Roadie : arguments d'origine (sain, vérifié : fichier .js -> `p+q`).
Ligne `#!` gardée en tête d'un `-e` : valide en JavaScript et en AppleScript (vérifié par osascript).
Aucune autre variante.

## F3 (méthode d'Alfred absente de l'objet)
Dictionnaire relevé dans le corpus : search, runTrigger, setConfiguration, removeConfiguration,
reloadWorkflow, revealWorkflow, version, activate, quit, running (agent launchd de 1Password, non lancé
par Roadie). `action` et `browse` : absents du corpus, signalés « non traduits » par la fiche (choix
écrit : une erreur visible plutôt qu'un ordre ignoré en silence). AppleScript `application "Alfred"
is running` : lecture seule vers Alfred, non traduite (sans effet).

## F2 (identifiant vide)
Autres écritures par identifiant : `AlfredKeptSettings.write` seul ; `values(for: "")` rendait déjà
vide. Aucune autre variante.
