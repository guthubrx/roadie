# Spécification 093 - Ordres à Alfred traduits par Roadie

Demande du 27 octobre 2026 (`/my.specify-all 092 093`). Demande initiale : « et maintenant les appels à
Alfred dans les workflows c'est quoi » ; après l'explication, session proposée : Roadie fait lui-même
ce qu'un script de workflow demande à Alfred.

## Demande reformulée
Quand un script de workflow lancé par Roadie s'adresse à Alfred (AppleScript `tell application id
"com.runningwithcrayons.Alfred"` ou `tell application "Alfred…"`, JavaScript
`Application("com.runningwithcrayons.Alfred")`), Roadie exécute l'ordre sans ouvrir Alfred :
`search` ouvre la barre avec le texte, `run trigger` lance le déclencheur externe, `set configuration`
et `remove configuration` enregistrent ou effacent le réglage dans un fichier de Roadie (jamais dans le
dossier d'Alfred), `reload workflow` relit le workflow, `reveal workflow` montre son dossier,
`version` rend la version, `activate` et `quit` ne font rien. L'interception couvre les scripts
AppleScript et JavaScript que Roadie lance lui-même et les appels `osascript` des scripts shell. La fiche
de compatibilité liste les ordres trouvés et ceux que Roadie ne traduit pas ; une simple mention
d'Alfred (chemin de cache, identifiant cité) ne compte plus.

## Ce que cela apporte
La mention « parle à Alfred » devient une information exacte et, pour les ordres traduits, un défaut
supprimé : la suite du workflow reste dans Roadie au lieu d'ouvrir Alfred, ou d'échouer sans Alfred.

## Mesure de départ (relevé du 27 octobre 2026, corpus de 102)
16 workflows mentionnent Alfred ; 12 lui donnent des ordres exécutés par leurs scripts (correction après
mesure : deux mentions comptées d'abord ne sont jamais exécutées, l'aide d'Alias Homebrew Apps et un
agent `launchd` écrit par 1Password) : `setConfiguration` (2 workflows,
15 appels), `removeConfiguration` (2), `search` (4), `runTrigger` / `run trigger` (4),
`reloadWorkflow` / `reload workflow` (4), `revealWorkflow` (1), `version` (2), `activate`/`quit` (1).
3 ne font que le citer (Clean Workflow Data, Snippet Transformer, Google Drive pour une autorisation).
Tous les appels sont dans `info.plist` (scripts en ligne), aucun dans un fichier de script séparé.

## Dépendances
SPEC-088 (exécution des scripts, fiche), SPEC-089 (déclencheurs externes, `roadie workflow trigger`),
SPEC-092 (déclencheur sur une brique par `externalid`).

## Exigences
- **FR-001 Traduction AppleScript.** Les formes `tell application [id] "<Alfred>" to <ordre>` et les
  blocs `tell application [id] "<Alfred>"` … `end tell` sont traduites ; `<Alfred>` vaut
  `com.runningwithcrayons.Alfred`, `Alfred`, `Alfred 2` à `Alfred 5`. Les expressions des arguments
  sont gardées telles quelles.
- **FR-002 Traduction JavaScript.** `Application("<Alfred>")` (guillemets simples ou doubles) devient un
  objet de Roadie aux méthodes `search`, `runTrigger`, `setConfiguration`, `removeConfiguration`,
  `reloadWorkflow`, `revealWorkflow`, `version`, `activate`, `quit`.
- **FR-003 Interception.** Scripts AppleScript (6) et JavaScript (7) : texte traduit avant lancement.
  Scripts shell et autres langages : un `osascript` de Roadie est placé en tête du `PATH`, et
  `/usr/bin/osascript` suivi d'une espace est remplacé par lui dans le texte du script quand il cite
  Alfred. Cet `osascript` traduit le texte reçu (`-e` ou fichier texte) puis appelle le vrai ; sans ordre
  à Alfred, il passe la main sans rien changer.
- **FR-004 Ordres.** `search` : barre rouverte avec le texte. `run trigger N in workflow W [with
  argument A]` : déclencheur externe (ou brique `externalid`) du workflow W avec A. `set configuration
  K to value V in workflow W` : réglage gardé par Roadie, lu ensuite comme une valeur de `prefs.plist`.
  `remove configuration K in workflow W` : réglage retiré. `reload workflow W` : relu à la prochaine
  lecture. `reveal workflow W` : dossier montré dans le Finder. `version` : version d'Alfred annoncée aux
  scripts (5.5 sans Alfred). `activate`, `quit` : sans effet.
- **FR-005 Réglages gardés.** Fichier par workflow dans `~/.roadies/workflows-settings/`, jamais dans le
  dossier d'Alfred ; une modification de ce fichier fait relire le workflow.
- **FR-006 Fiche.** `roadie workflow list` / `check` : « ordres à Alfred : … » avec les ordres trouvés,
  et « non traduits : … » s'il y en a ; plus de mention pour une simple citation. Le total
  « sans mention d'Alfred et complets » devient « complets sans ordre non traduit ».
- **FR-007 Journal.** Chaque ordre traduit qui lance une commande est noté (`launcher.alfred_call`,
  ordre et workflow, sans texte de l'utilisateur) ; `version`, `activate` et `quit`, traduits en
  valeurs fixes dans le script, ne lancent rien et ne sont pas notés (précision de Converge).

## Critères de réussite
- SC-001 : Tests de traduction sur les formes du corpus (une par ordre, AppleScript et JavaScript,
  dans un `-e` de shell avec guillemets échappés) ; texte sans Alfred inchangé octet pour octet.
- SC-002 : Un script d'essai qui appelle `tell application id "com.runningwithcrayons.Alfred" to run
  trigger …` par `/usr/bin/osascript` déclenche le workflow d'essai dans Roadie (mesure réelle) ;
  Alfred ne reçoit rien (aucun lancement d'Alfred observé).
- SC-003 : Corpus : les 12 workflows à ordres listés avec leurs ordres, les 3 citations sans mention ;
  aucun ordre du corpus « non traduit ».

## Hors périmètre
Scripts AppleScript compilés (`.scpt`) ; `action` et `browse` (absents du corpus) signalés « non
traduits » ; scripts externes qui appellent `/usr/bin/osascript` par son chemin complet (seul le `PATH`
s'applique) ; tout envoi d'événement à Alfred.
