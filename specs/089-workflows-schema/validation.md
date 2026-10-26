# Validation 089

## Tests
- `Spec089WorkflowsTests` (5) : appel externe vers soi et vers un autre workflow, `run` depuis un
  déclencheur et `start` sur un objet ; déclencheurs indexés (touches « ⌥⌘G », argument, types UTI
  acceptés, repli) ; filtre de liste ; requête et réponse du filtre de fichiers ; tâche
  d'automatisation d'essai (défauts, réglages `{var:}`, case à cocher « 1 », entrée remplacée,
  dossier de la tâche) et tâche absente ; dialogue (branches `_button1`, `_button2`), grand texte,
  Terminal (échappement), Raccourci Apple, touches simulées, barre rouverte sur un chemin.
- `Spec074VerbsTests` adapté (ligne de verbe de workflow).
- Suite complète : 2 075 tests / 288 suites réussis.

## Mesures
- `roadie workflow tasks update` : 232 tâches dans `~/.roadies/alfred-tasks` (licence gardée).
- Corpus de 102 (`/tmp/roadie-wf-corpus/mixed2`) : 92 avec une entrée complète (90 %), 79 entiers
  (77 %), 70 entiers sans mention d'Alfred. Sans les 5 workflows en php ou python 2 (absents de
  macOS) : 79/97 entiers (81 %). Restent : vues Texte 9, Remote 4, snippets 3, Grille 2, PDF 2,
  Image 1, tampon 1 (écartés) et 1 tâche d'un groupe absent du dépôt public.
- Ce Mac : Reminders for Alfred devient complet ; Emoji search et Audio Switcher partiels (snippet,
  Remote) ; System Settings Explorer inutilisable (vue Grille).
- R8 (088) mesuré : un script lancé par `roadie workflow trigger` (PPID = roadied 14525) obtient
  `AXIsProcessTrusted() = true` ; le même appel depuis le Terminal : `false`. Le journal du démon
  (`launcher.workflow.run`) ne contient ni l'argument ni la sortie. Workflow d'essai retiré.

## Installation
PID 14525, santé 5/5, signature conservée.

## Limites
- Audio Switcher non lancé pour de vrai : sa commande changerait la sortie audio de l'utilisateur.
- Verbes « Workflow : … », repli et filtres non essayés au clavier (tests seulement).
- Sous-titre ⇧ d'une ligne : affiché ; ⌘⇧ et autres combinaisons : Retour seulement.
- Contre-revue Bridget : refusée (`project_mapping_unknown`).
