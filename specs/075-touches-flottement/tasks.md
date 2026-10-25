# Tâches 075

## US1 Variantes de Retour (P1)
- [ ] T001 Tests puis `LauncherModifier`, `LauncherVariant.of` et verbe `bringHere` dans
  `Sources/RoadieDaemon/LauncherActions.swift` ; `Spec075KeysTests` : chaque objet × touche donne
  la description et l'action attendues ; cible à l'écran : ⌘ reste ⌘-clic.
- [ ] T002 `SearchKeyInput.Kind.confirm` avec `option`, `control` (`TargetOverlayPresenter.swift`,
  `SearchInputPanel.swift`, tests existants adaptés) ; `.flagsChanged` → `onFlags`.
- [ ] T003 Session : modificateur tenu, détail remplacé sur la ligne choisie, Retour avec
  variante → `perform` ; `web_search_url` dans `Sources/RoadieCore/Config.swift` ; effets
  `bringHere` et recherche web dans `TargetModeRuntimeController.swift`. Observable : rendu
  natif sur données fictives avec ⌘ tenu.

## US2 ⌘1 à ⌘9 (P1)
- [ ] T004 Tests puis `.pick(n)` (⌘ + chiffre), rang des lignes visibles, `SlashSuggestion.shortcut`
  dessiné à droite (`SearchBarRenderer.swift`) ; action par défaut à toutes les étapes.

## US3 Verbes de la fenêtre active (P1)
- [ ] T005 `actions_hotkey` (config, validation), seconde instance `TargetSearchHotkey`,
  `roadie target actions`, démarrage de la session à l'étape des verbes de la fenêtre au premier
  plan ; repli sur la barre normale sans fenêtre gérée.

## US4 Flèche droite (P2)
- [ ] T006 → avec curseur en fin de saisie non vide → `.actions` ; test de `navigation`.

## US5 Flotter ou tuiler (P1)
- [ ] T007 Tests puis `WindowRuleAffinityService.saveTiling`/`clearTiling` ; l'affinité garde le
  tuilage et inversement (règle unique `affinity-app-<bundle>`), relecture du fichier.
- [ ] T008 Verbes de flottement selon l'état (pin, règle, tuilable) dans `LauncherVerb.verbs` et
  effets ; entrées du menu Fenêtre (`TitlebarContextMenuController.swift`,
  `WindowContextActions.swift`).

## Livraison
- [ ] T009 Suite complète `scripts/test --no-parallel`, installation signée, santé 5/5, essai réel
  des variantes et du flottement durable, docs FR/EN (`docs/fr|en/features.md`, `cli.md`),
  CHANGELOG, `validation.md`.
