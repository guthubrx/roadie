# Audit de l'existant 093

Statut : **OK**.

| Élément du plan | Existant trouvé | Décision |
|---|---|---|
| Détection d'Alfred | `AlfredCompatibility.mentionsAlfred` (`AlfredCompatibility.swift:65`) | REMPLACER par `AlfredBridge.orders` (même lecture de fichiers) |
| Lancement d'un déclencheur | `runWorkflowCommand` (`TargetModeRuntimeController.swift:687`), `externalTrigger` | RÉUTILISER |
| Barre rouverte | `reopenSearch` (`TargetModeRuntimeController.swift:754`) | RÉUTILISER |
| File de commandes vers le démon | `queueTargetModeRuntimeCommand` (`CLICommandRouter.swift:936`) | RÉUTILISER |
| Chemin de `roadie` | `BTTShortcutBindingService.executable` (`BTTShortcutBindingService.swift:84`) | RÉUTILISER la convention |
| Citation pour le shell | `BTTShortcutBindingService.shellQuote` | RÉUTILISER |
| Version d'Alfred | `AlfredScriptRunner.alfredVersion` | RÉUTILISER |
| Préférences du workflow | `AlfredWorkflow.load` (lecture de `prefs.plist`), cache de l'index | ÉTENDRE |
| Traduction de texte | aucun équivalent (`rg "tell application"` : services AppleScript sans réécriture) | CRÉER `AlfredBridge` |
| `osascript` de Roadie | aucun | CRÉER (petit fichier écrit à la demande) |

## Arbitrages
Aucun : pas d'équivalent proche pour la traduction.

## Dépendances
Aucune nouvelle.

## Gate avant tasks
- [x] Chaque élément du plan a une décision.
- [x] Les créations ont une justification écrite.
- [x] Aucune dépendance externe ajoutée.
