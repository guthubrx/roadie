# Preuve de contexte - audit V15 readonly, session 050 (double-clic sur la barre de titre)

Racine figée : `/private/tmp/roadie-audit-050` (worktree détaché, commit 8c207d6790464616564d66a19c5d013e7f7bfe73).
Revue différentielle : base 3dd5563b24b29ca83312e2c15f881ad4787d51c0 (049) ; deux commits (fc55807b, 8c207d67).
Mode readonly, un cycle. Auditeur : Claude (Opus), même agent que l'orchestration, `independent=false`.

## Biens à protéger
- Disposition en arbre de l'utilisateur : une maximisation au double-clic ne doit pas modifier l'arbre.
- Double-clics propres aux applications (sélection de mot, boutons, onglets, liens, web).
- Réactivité : aucun relevé pour un clic simple (R4).
- Diagnostic de santé cohérent avec la 049.

## Acteurs et points d'entrée
- Moniteur global `leftMouseDown` du composant `titlebar-menu` (`TitlebarContextMenuController.swift:193-202`),
  démarré par défaut dans `roadied run` (`main.swift:200-202, 482`), indépendant de l'option `enabled` du menu.
- `handleDoubleClick` (l. 257-280) : config, action macOS (`AppleActionOnDoubleClick` global, l. 107-117
  de `DaemonHealth.swift`), relevé `snapshot()`, `hitTest`, rôle AX sous le pointeur, `toggleMaximize(windowID:)`.
- Santé : `macOSWindowSettingsCheck(..., roadieDoubleClickMaximize:)` (`DaemonHealth.swift:186-208`), alimentée
  par `service.effectiveConfig` (l. 179).
- Session de geste du tiler ouverte par le même appui (`main.swift:427-445`), interprétée au relâchement
  par `LayoutMaintainer.layoutGesture` / `applyGesture`.

## Invariants vérifiés
1. Un clic simple ne fait qu'une comparaison d'entier (`clickCount == 2`, l. 195).
2. Roadie n'agit que si l'action macOS vaut « None » et si le réglage est actif (`handlesDoubleClick`).
3. Fenêtres épinglées ou flottantes (`pin != nil`, SPEC-047) et rôles interactifs exclus.
4. Délai AX : le délai global de 0,5 s est posé par le relevé (`SystemSnapshotProvider.swift:248-264`) avant
   la requête de rôle par l'élément système.
5. Une maximisation écrite pendant la session de geste du second appui n'est pas adoptée comme
   redimensionnement manuel (reproduction isolée, `repro/`, voir `constats.md`).

## Observations runtime (lecture seule)
- `defaults read -g AppleActionOnDoubleClick` : clé absente (run 20261018T181439624967Z, erreur attendue) ;
  `AppleMiniaturizeOnDoubleClick = 0` (run 20261018T181439810239Z) : macOS agrandit.
- `~/.config/roadies/roadies.toml` : section `[experimental.titlebar_context_menu]` sans `double_click_maximize`
  (run 20261018T181452406416Z) : défaut `true`.

## Fichiers lus
Diff complet ; `TitlebarContextMenuController.swift:150-300` ; `DaemonHealth.swift:55-215` ; `Config.swift:1075-1140, 1365-1372` ;
`WindowCommands.swift:28-50, 530-600` ; `LayoutMaintainer.swift:180-200, 345-375, 1160-1250, treeLayoutCommands, applyGesture` ;
`FocusFollowsMouseController.swift:130-280` ; `TickScheduler.swift:120-135` ; `StageStore.swift:950-970` ;
`main.swift:195-205, 420-450, 475-520` ; `SettingsCatalog.swift:500-515` ; docs FR/EN, CHANGELOG ; spec, plan, research, reuse-audit, tasks.

## Zones non lues et inconnues
- Comportement réel des rôles AX dans les barres de titre des applications (Chrome, Safari, Finder) : non observé.
- Prise en compte à chaud d'un changement de `AppleActionOnDoubleClick` par CFPreferences : non vérifiée.
- Double-clic réel sur le bureau : non exécuté (pas d'accès au bureau, aucune installation).
