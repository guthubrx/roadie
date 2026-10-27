# Validation 093

## Tests
- `Spec093BridgeTests` (11) : formes AppleScript du corpus (ligne, bloc, `search`, `run trigger` avec et
  sans argument, `reload`, `version`, `set`/`remove configuration`), texte sans Alfred inchangé, objet
  JavaScript (constante, chaîne, `#!` gardé), exécution réelle par `osascript` de l'AppleScript et du
  JavaScript traduits (commande remplacée par `/bin/echo`, apostrophe comprise), ordres de la fiche
  (citation de cache exclue, `action` non traduit), guillemets échappés `\"`, options d'`osascript`,
  `/usr/bin/osascript` redirigé sauf dans `</string>`, scripts préparés avant lancement et `PATH`,
  réglages gardés fusionnés après `prefs.plist`, fiche d'un workflow.
- Suite complète : 2 108 tests / 294 suites réussis.

## Mesure réelle (SC-002), 27 octobre 2026, 05:46 UTC
Roadie installé (PID 86689, santé 5/5). Workflow d'essai `test.roadie.bridge093` dans
`~/.config/roadies/workflows` : un script bash donne deux ordres, `run trigger` par
`/usr/bin/osascript -e '… AppleScript …'` et `runTrigger` par `osascript -l JavaScript` (`PATH`).
`roadie workflow run test.roadie.bridge093 S` : le déclencheur externe de Roadie a écrit « absolu »
puis « path » dans le fichier d'essai ; deux `launcher.alfred_call` (ordre `trigger`) au journal.
Ce workflow n'existe pas dans Alfred : aucun ordre n'y est parti. Workflow et fichier retirés ensuite.

## Corpus (SC-003)
`roadie workflow check /tmp/roadie-wf-corpus/mixed2` : 12 workflows « ordres à Alfred » (Funnel,
Obsidian, 1Password, Clipboard History Extender, Philips Hue, System Settings Explorer, AppleScript
Dictionaries, Notes, Calculate Anything, Workflow Actions, Backup Preferences, Google Drive), aucun
« non traduit » ; Clean Workflow Data, Snippet Transformer et le contrôle d'autorisation de Google
Drive ne sont plus comptés. 80 complets (78 %), 93 avec une entrée complète (91 %), inchangé par la 093.
Deux ordres restent hors d'atteinte, et non comptés : l'agent `launchd` écrit par 1Password (lancé par
macOS, pas par Roadie) et l'alias d'aide d'Alias Homebrew Apps (texte à copier par l'utilisateur).

## Limites
- Scripts AppleScript compilés (`.scpt`), et scripts externes qui appellent `/usr/bin/osascript` par
  son chemin complet ou par `#!` : seul le `PATH` s'applique.
- `action` et `browse` : signalés « non traduits » (absents du corpus).
- Une expression qui contient ` in workflow ` dans une chaîne serait mal découpée (non observé).
- Preuves : correction sans effet visible propre (barre et déclencheur déjà existants) ; pas de diaporama.
