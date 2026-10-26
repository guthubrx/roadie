# Recherche 088

## R1 Corpus et couverture (26 octobre 2026)
Corpus : 55 `info.plist` des dépôts publics `alfredapp/*-workflow` (BSD-3), 42 de dépôts
communautaires populaires (MIT, GPL, BSD…), 4 installés chez l'utilisateur ; gardé hors du dépôt
dans `/tmp/roadie-wf-corpus/` (licences variées). Script de mesure : `couverture.py` (même dossier).
Objets les plus utilisés (nombre de workflows) : scriptfilter 61, script 59, keyword 48,
conditional 45, argument 44, notification 39, clipboard 35, hotkey 32, automation.task 32,
openurl 24, external 21, action 16, openfile 16, junction 16, callexternaltrigger 13, fallback 12,
universalaction 12, split 11, playsound 10, transform 10. 15 workflows nomment Alfred dans leur
configuration (AppleScript vers `com.runningwithcrayons.Alfred`).
Couverture avec les briques de la 088 : 57 % avec une entrée complète, 26 % entiers. Avec un
premier découpage sans les utilitaires (conditions, découpe…), 39 % seulement : les utilitaires,
logique pure et peu coûteuse, sont donc dans cette étape.

## R2 Format `info.plist`
`objects[]` (`uid`, `type` « alfred.workflow.<famille>.<nom> », `config`), `connections` (uid →
[`destinationuid`, `modifiers` (0, ⌘ 1048576, ⌥ 524288, ⌃ 262144, ⇧ 131072, fn 8388608, sommes),
`modifiersubtext`, `vitoclose`]), `variables`, `variablesdontexport`, `userconfigurationconfig[]`
(`variable`, `type` textfield/textarea/checkbox/popupbutton/filepicker/slider, `config.default`),
`bundleid`, `name`, `description`, `version`, `disabled`. Les réglages saisis par l'utilisateur
sont dans `prefs.plist` du dossier du workflow. Un objet a parfois `config.disabled`… (rare).

## R3 Types de script (relevé du corpus)
0 bash, 1 php (absent de macOS depuis 12), 2 ruby, 3 python 2 (absent), 4 perl, 5 zsh,
6 osascript AppleScript, 7 osascript JavaScript, 8 script externe (`scriptfile`, exécutable du
dossier), 9 python3, 11 zsh `--no-rcs`. 10 non observé : traité comme inconnu (ligne d'erreur).
`scriptargtype` 1 = argv (310 objets), 0 = remplacement de `{query}` (100).

## R4 Échappement de `{query}`
Valeurs observées : 0, 68, 102, 118, 4, 127… Bits déduits des choix d'Alfred : espaces 1,
apostrophes inverses 2, guillemets 4, crochets 8, points-virgules 16, dollars 32, barres
obliques inverses 64. Le défaut bash 102 (= 2+4+32+64) et le défaut AppleScript 68 (= 4+64)
confirment. Échappement = barre oblique inverse devant chaque caractère concerné, barres obliques
inverses d'abord.

## R5 Exécution
`Process` avec `/bin/bash -c SCRIPT bash ARG` (argv) ou script seul (`{query}` remplacé) ; zsh
pareil ; osascript `-l JavaScript -e SCRIPT ARG` (le `run(argv)` reçoit l'argument) ; python3
`-c` ; externe : chemin dans le dossier. Dossier courant = dossier du workflow. Environnement =
celui du démon + `alfred_*` + variables. Sortie lue en continu, coupée à 5 Mo ; arrêt `terminate`
puis `interrupt` après 10 s ou à la frappe suivante. Aucun processus orphelin : le groupe est
arrêté avec le script (`setpgid` via `posix_spawn` n'est pas exposé par `Process` ; on arrête
le processus lancé, ce qui suffit pour les scripts simples ; limite notée).

## R6 Modificateurs
Emoji search (installé) : sous-titre ⌥ « copier `:nom:` » mais seule une connexion ⌘ existe à
côté de la connexion sans modificateur. Pour que ⌥ marche comme le dit le workflow, un
modificateur sans connexion propre suit les connexions sans modificateur, avec l'argument et les
variables de ce modificateur. C'est la règle retenue.

## R7 `autocomplete`
Dans Alfred, le texte d'`autocomplete` d'une ligne de Script Filter remplace la saisie après le
mot-clé (le mot-clé est gardé). Hypothèse retenue : saisie = `mot-clé` + espace (si l'entrée en
exige une) + `autocomplete`. Si `autocomplete` commence déjà par le mot-clé, il est pris tel quel.

## R8 Droits
Un script lancé par Roadie hérite de son autorisation Accessibilité (macOS attribue la demande au
processus responsable) ; c'est aussi le cas dans Alfred. Mesure prévue à la livraison : un script
`AXIsProcessTrusted()` lancé par un workflow. Atténuation : seuls des workflows installés par
l'utilisateur sont lus ; `alfred_workflows = false` coupe ceux d'Alfred, `workflows_enabled =
false` coupe tout.

## R9 Dossiers de données
Workflow d'Alfred : `~/Library/Application Support/Alfred/Workflow Data/<bundleid>` et
`~/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/<bundleid>` (documentés) : le même
état que dans Alfred (jetons, caches). Workflow de Roadie : `~/.roadies/workflows-data/<id>` et
`~/Library/Caches/roadie/workflows/<id>`. Dossier de préférences d'Alfred : clé `current` de
`~/Library/Application Support/Alfred/prefs.json`.
