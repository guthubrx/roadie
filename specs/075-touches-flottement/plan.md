# Plan 075

## Approche
Logique pure d'abord (variantes, rangs ⌘n, verbes de flottement), testée sans AppKit ; puis le
câblage clavier et rendu ; puis les effets (règles, actions).

| Zone | Fichier | Changement |
|---|---|---|
| Variantes | `Sources/RoadieDaemon/LauncherActions.swift` | `LauncherModifier`, `LauncherVariant.of(subject:modifier:)` : description et action ; verbes `bringHere`, `floatAlways`, `tileAlways`, `tileWindow`, `clearTilingRule` |
| Clavier | `Sources/RoadieDaemon/SearchInputPanel.swift` | `.flagsChanged` → `onFlags` ; Retour avec ⌥/⌃ ; ⌘1–9 → `.pick` ; → en fin de saisie → `.actions` |
| Entrée | `Sources/RoadieDaemon/TargetOverlayPresenter.swift` | `Kind.confirm(shift:command:option:control:isRepeat:)`, `.pick(Int)`, `.actions` ; session : modificateur tenu, ⌘n, variantes, ouverture directe aux verbes |
| Rendu | `Sources/RoadieDaemon/SearchBarRenderer.swift` | `SlashSuggestion.shortcut` (« ⌘3 ») dessiné à droite des lignes non choisies |
| Effets | `Sources/RoadieDaemon/TargetModeRuntimeController.swift` | `bringHere`, recherche web, verbes de tuilage, démarrage aux verbes |
| Règles | `Sources/RoadieDaemon/WindowRuleAffinityService.swift` | `saveTiling(window:floating:)`, `clearTiling(window:)`, affinité qui garde le tuilage |
| Menu | `Sources/RoadieDaemon/TitlebarContextMenuController.swift`, `WindowContextActions.swift` | entrées « Toujours flotter / tuiler <App> », « Retirer la règle » |
| Config | `Sources/RoadieCore/Config.swift` | `actions_hotkey`, `web_search_url` (clés connues, validation du raccourci) |
| Raccourci | `Sources/RoadieDaemon/TargetSearchHotkey.swift` (réutilisé), démarrage du daemon | seconde instance |
| CLI | `Sources/RoadieDaemon/CLICommandRouter.swift` | `roadie target actions` |

## Complexité
Variantes : O(1). ⌘n : O(r) sur les lignes visibles (r ≤ 30). Règles : O(R) lecture/écriture du
fichier généré (R règles, < 100).

## Constitution
Pas de nouvelle dépendance ; réutilisation du raccourci Carbon, du fichier de règles généré et
des verbes 074. Aucune abstraction nouvelle à moins de trois usages : `LauncherVariant` sert
trois touches et quatre types d'objet.

## Tests
`Tests/RoadieDaemonTests/Spec075KeysTests.swift` : variantes par objet et touche, rangs ⌘n,
verbes de flottement selon l'état, règle unique (affinité + flottement, retrait de l'un),
navigation clavier (`SearchInputPanel.navigation`).
