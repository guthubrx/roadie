# Tâches 099

- [x] T001 Tests `Tests/RoadieDaemonTests/Spec099ViewModeTests.swift` : cycle, symboles, colonnes,
  mémoire bornée et relue, lignes en grille (titres retirés, fichiers seuls pour `files`), touche
  résolue reconnue par `SearchInputPanel.navigation`, réglage lu.
- [x] T002 Réglage `view_cycle_hotkey` (`Config.swift`, `SettingsCatalog.swift`, enregistreur dans
  `SettingsView.swift`). (FR-005)
- [x] T003 `Sources/RoadieDaemon/LauncherViews.swift` : présentation, mémoire, lignes en grille. (FR-002, FR-007)
- [x] T004 Barre : source (FR-001), application de la présentation, noms (FR-003), clavier (FR-008),
  touche `.cycleView` (FR-005), chip et clic (FR-006) ; contexte et contrôleur.
- [x] T005 Vignettes d'images en grille (FR-004).
- [ ] T006 Suite complète, installation, documentation FR/EN, CHANGELOG, validation, index.

Analyse : couverture 8/8 (FR-001 à FR-008). Converge : FR-001 `currentViewSource`, FR-002 `gridRows` et
`applyViewMode`, FR-003 `namesInFooter`, FR-004 `thumbnailImage`, FR-005 réglage et `cycleKey`, FR-006 chip
et `counterFrame`, FR-007 `LauncherViewBook`, FR-008 `gridColumns` dans `navigate` : CONVERGED. Survol du chip
remplacé par un chip qui porte le nom de la présentation (« ▦ Grille ») : pas de suivi du survol dans la barre.
T006 : installation reportée, voir validation.md.
