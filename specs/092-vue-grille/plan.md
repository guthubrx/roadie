# Plan 092 - Vue Grille des workflows

## Contexte technique
Swift 6, AppKit, paquet `RoadieDaemon`. Build `scripts/with-xcode swift build`, tests
`scripts/test --no-parallel`, installation `make install && make restart`, santé
`roadie query health --json`.

## Approche (research R1 à R8)
1. **Modèle.** `AlfredGridView` (entrée `.grid`, réglages d'affichage, tuiles, variables du schéma,
   présélection) et sa construction pure `AlfredGridView.make(object:workflow:input:variables:output:)`
   à partir d'une réponse JSON ou d'une liste de chemins. `AlfredObject.externalID`.
2. **Moteur.** Brique `userinterface.grid` : source (argument ou script), vue construite, effet
   `showGrid`, arrêt. `Step.next` porte la surcharge `config` (brique JSON, Run Script).
   `externalTrigger` trouve aussi une brique par `externalid` ; l'appel externe l'exécute.
3. **Barre.** Le contexte reçoit `workflowGrid` ; la barre garde la vue, construit ses lignes
   `.workflowItem(entry, item, index)` filtrées (mode 2 si `filterable`), choisit `preselect`, et
   dessine en grille. Retour : chemin existant (`confirmWorkflow`), variables de la vue ajoutées.
4. **Disposition et dessin.** `TargetSearchBar.grid` ; `SearchBarLayout.makeGrid` ; dessin d'une tuile
   et du pied dans `SearchBarRenderer`.
5. **Touches.** `SearchInputPanel.gridColumns` ; ← → → `.move(±1)` ; ↑ ↓ ± colonnes dans la barre.
6. **Effet réel.** `AlfredLiveEffects.showGrid` → contrôleur : vue en attente, barre rouverte.
7. **Fiche.** `userinterface.grid` dans les briques gérées.

## Fichiers touchés
- `Sources/RoadieDaemon/AlfredWorkflow.swift` (externalID)
- `Sources/RoadieDaemon/AlfredGridView.swift` (nouveau : vue et construction pure)
- `Sources/RoadieDaemon/AlfredWorkflowEngine.swift` (brique, surcharge, déclencheur)
- `Sources/RoadieDaemon/AlfredWorkflowIndex.swift` (genre `.grid`)
- `Sources/RoadieDaemon/AlfredLiveEffects.swift`, `TargetModeRuntimeController.swift` (effet réel)
- `Sources/RoadieDaemon/LauncherSearchContext.swift`, `TargetOverlayPresenter.swift` (barre)
- `Sources/RoadieDaemon/SearchBarRenderer.swift`, `SearchInputPanel.swift` (dessin, touches)
- `Tests/RoadieDaemonTests/Spec092GridTests.swift`, `Spec088Support.swift` (effet factice)

## Constitution
- XVIII : construction O(n) des tuiles, filtre O(n × m) existant, disposition O(t) tuiles montrées.
- XIX : une seule abstraction nouvelle (`AlfredGridView`, donnée) ; Retour, filtre, icônes, script
  et déclencheurs réutilisés ; pas d'option ajoutée aux réglages.
- XX : la grille passe par les mêmes lignes `.workflowItem` que la liste ; une seule différence de
  rendu (disposition) et de touches (← →). Limite écrite : aspect des images non distingué.

## Risques
- Rendu en tuiles non visible en test : essai utilisateur, captures hors écran si possible.
- Taille des tuiles avec 12 colonnes : bornée par la largeur ; titres tronqués.
