# Constats confirmés et reproductions

Copie de laboratoire `/tmp/roadie-audit-129-lab` (même commit 3c9d66d9) ; fichier de reproduction
conservé dans `notes/repro-audit129.swift` (jamais commité, jamais dans la copie auditée).
Exécutions : `runs/20261029T181537082575Z` (reproductions et test différentiel) et
`runs/20261029T181646448678Z` (isolement de la cause de l'index). Les essais
`20261029T181112797495Z` et `20261029T181130085723Z` ont échoué à la compilation (dossier de
compilation cloné incompatible, puis fichier modifié pendant la compilation) : ils ne prouvent rien.

## F-RUNSCRIPT - action Run Script arrêtée après 10 s (MEDIUM, confirmé)

`AlfredWorkflowEngine.swift:169` appelle `AlfredScriptRunner.run` sans délai : le défaut de 10 s
(`AlfredScriptRunner.defaultTimeout`) s'applique. La spec 088 fixe ce délai aux Script Filters
seulement (FR-004) ; FR-008 (Run Script) n'en fixe aucun. Reproduction sur le vrai moteur :
`sleep 11; printf fini` relié à une copie → arrêt à 10,67 s, notification « Script : délai
dépassé », erreur `timeout`, la copie n'a pas lieu. Témoin : `sleep 1; printf fini` → `copy:fini`.
Variantes de la même cause (voir `variantes-delais.md`) : Run NSAppleScript
(`AlfredWorkflowEngine.swift:180`) et tâches d'automatisation (`AlfredAutomationTasks.swift:58`),
lues dans le code, même appel sans délai. Correction suggérée : délai propre aux filtres ; aucun délai
(ou un délai long réglable) pour Run Script, NSAppleScript et tâches, l'annulation explicite restant
possible.

## F-SPOTLIGHT - reconstruction Spotlight interrompue avant la saisie du mot de passe (LOW, confirmé)

`LauncherSystemCommands.swift:109` lance `do shell script "/usr/bin/mdutil -E /" with administrator
privileges` par `script(_:)` (ligne 125), donc `LauncherBrowsers.run(source, timeout: 10)`. Reproduction
du lanceur réel : un script `delay 12` est arrêté à 10,67 s, résultat nil. Une saisie du mot de passe
au-delà de 10 s ne lance donc pas `mdutil`, sans message. La boîte d'authentification n'a pas été
ouverte sur le poste de l'utilisateur : sa fermeture exacte à l'arrêt d'osascript n'est pas observée.

## F-LITERAL-EMPTY - index des littéraux : doublon non refusé après une valeur vide (LOW, confirmé)

`ConfigFileEditor.literalIndex` promet « mêmes refus que `readLiteral` ». Une ligne `y =` (ou
`y = # commentaire`) sort par `guard end > start else { continue }` sans noter la clé ; une seconde
ligne `y = 8` est alors indexée au lieu d'être refusée comme doublon. Test différentiel à graine fixe :
3 000 fichiers × 25 sondes, écarts tous de cette forme ; sans la ligne `y =`, 5 000 fichiers donnent
71 écarts, tous avec `y = # vide`, aucun autre. Effet : la fenêtre Paramètres affiche une valeur d'un
fichier invalide que Roadie n'applique pas. Les écritures restent refusées sur un fichier invalide.

## F-FIREFOX-BFS - parcours en largeur quadratique (LOW, confirmé par lecture)

`FirefoxTabSelector.select` (`LauncherOpenItems.swift:159-170`) retire la tête d'un tableau par
`removeFirst()`, O(n) à chaque retrait : O(n²) pour n ≤ 4 000 éléments par fenêtre, soit environ
8 millions de déplacements au pire. La borne est écrite, la complexité ne l'est pas (Article XVIII).
Aucune mesure de durée réelle. Correction : indice de lecture dans le tableau.

## Signaux examinés et non retenus

- Socket, workflow : `workflowDirectoryName`, `AlfredKeptSettings` (« / » remplacé, `..` refusé) : protégés.
- `AlfredFileFilter` : saisie échappée dans la requête Spotlight puis citée pour le shell : protégée.
- `LauncherTerminal` : la commande vient de l'utilisateur et part dans son propre terminal : voulu.
- `LauncherRecentDocuments` : `requiresSecureCoding = false` sur une archive écrite par macOS dans le
  dossier de l'utilisateur ; un attaquant capable de l'écrire agit déjà avec ses droits. Observation.
- `focusOnOtherSpace` : jusqu'à 1,8 s d'attente bloquante pour une bascule d'espace (session 106,
  ADR 020) : compromis documenté, pas un constat.
- `LauncherRecentFiles` : requête Spotlight sans plafond (fichiers ouverts depuis dix ans), en fond ;
  mémoire non mesurée. Observation.
- `UILanguage.current` en `nonisolated(unsafe)` : écrite au démarrage et par les rendus de captures en
  test séquentiel seulement. Observation.
- Textes français hors `tr` : messages de `SlashCommandRunner.translated` gardés par la langue
  française ; deux messages `launcher batch: … chemins copiés / dans le Finder` restent en français dans
  le résultat de commande (INFO, non affiché comme constat).
