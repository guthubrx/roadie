# Contexte - audit V15 des sessions 092 et 093

Racine d'audit : copie propre `/tmp/roadie-audit-092-093` (détachée, hors `.worktrees` pour OSV), même
dépôt que `/Users/moi/Nextcloud/10.Scripts/39.roadie`. Base `5ed75b05`, révision 0 `2d81ec04`,
révision 1 (après corrections) `b90f53d7`. Le checkout principal est occupé par une autre session
(`session-093-audit-codebase`, modifications non commitées) : non utilisé, non modifié.

## Biens à protéger
Configuration et dossiers de l'utilisateur (le dossier d'Alfred n'est jamais écrit), presse-papiers,
fenêtres, sortie des scripts (JSON des Script Filters), réglages gardés des workflows.

## Acteurs et points d'entrée
- Workflows installés par l'utilisateur (Alfred ou `~/.config/roadies/workflows`) : code tiers lancé
  avec les droits du démon (constat INFO de l'audit 087-091, inchangé).
- Barre Capslock + F : saisie de l'utilisateur, grille (`TargetOverlayPresenter.refreshGrid`,
  `moveInGrid`, `navigate`), dessin (`SearchBarRenderer.makeGrid`, `drawTile`).
- Moteur (`AlfredWorkflowEngine` : `userinterface.grid`, surcharge `config`, `externalTrigger`).
- Commandes `roadie workflow alfred …` et `roadie workflow osascript …` ; `osascript` de Roadie dans
  `~/Library/Caches/roadie/alfred-bridge/`, en tête du `PATH` des scripts.

## Invariants lus
- Une grille ouvre la barre une fois ; Retour repart de la brique avec les variables du schéma.
- Un texte sans ordre à Alfred est exécuté octet pour octet comme avant (traduction nil, `osascript`
  de Roadie passe les mêmes arguments ; sortie vérifiée identique, code de retour conservé).
- Les réglages gardés ne sont écrits que dans `~/.roadies/workflows-settings/`, un fichier par
  identifiant (« / » remplacé : pas de sortie du dossier).

## Lecture
Diff complet 092 + 093 + correctifs lu ; appelants lus : `confirmWorkflow`, `finishWorkflow`,
`runWorkflow` du contexte, `runWorkflowCommand`, `reopenSearch`, `AlfredScriptRunner.start`,
`AlfredCompatibility.report`, `AlfredWorkflowIndex.workflows(in:)`. Non lus en détail : rendu AppKit
au-delà des fonctions modifiées.

## Inconnues
Rendu réel des tuiles non capturé (essai concurrent de l'utilisateur) ; latence non mesurée ;
scripts compilés et scripts externes à chemin complet non couverts (limites écrites).
Revue indépendante : aucune (Bridget `origin_request_invalid`, aucun agent d'un autre fournisseur).
