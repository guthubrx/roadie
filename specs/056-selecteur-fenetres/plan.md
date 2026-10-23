# Plan

Implémentation originale Swift/AppKit sans dépendance nouvelle. Source d'appartenance unique StageStore ; ne jamais déduire une stage de la position écran. Les entrées fusionnent fenêtres courantes et membres persistés encore vivants. Une acquisition à l'ouverture, aucun scan AX par Tab ou frappe. Captures à la demande et bornées ; cache partagé à intégrer avec le rail, sans travail permanent supplémentaire.

Lots exclusifs :
1. Configuration et paramètres (Config.swift, nouveau WindowSwitcherConfig.swift, SettingsCatalog*, tests dédiés).
2. Modèle/activation/AX (nouveaux WindowSwitcherModel.swift, WindowSwitcherService.swift, WindowSwitcherWindowAccess.swift et tests ; extraction limitée depuis les signets si nécessaire, sans modifier les autres lots).
3. Interface/clavier (nouveaux WindowSwitcherController.swift, WindowSwitcherPanel.swift, WindowSwitcherHotkeys.swift et tests). Pas de modification main/CLI par ces lots.
Responsable : intégration main/CLI, cache vignettes/MRU, docs, tests Mac et livraison. Chaque agent travaille dans son worktree, sans modifier/revenir sur les autres travaux, livre son commit.
Contrats dans contracts.md. Review après intégration. Build et tests séquentiels jobs2, aucune modification Sources/Tests pendant compilation.
