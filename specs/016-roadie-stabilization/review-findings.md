# Constats de la revue du 2026-10-10

Source : cinq revues en lecture seule (moteur de disposition, navrail, utilisabilité, robustesse daemon, instabilité). Les numéros de ligne correspondent au commit `0569a3e`. ✔ = vérifié manuellement dans le code.

## Données runtime (`~/.roadies/events.jsonl` + `.1`)

| Événement | Nombre |
|---|---|
| rail_refresh | 36 932 |
| mutable_bsp_auto_relayout_suppressed | 16 887 |
| windows.missing_reconciled | 6 337 |
| live_tick | 2 500 |
| mutable_bsp_order_repaired | 529 |
| layout_clamped | 496 |
| layout_failed | 61 |

Dernier démarrage : `accessibilityTrusted=false`.

## Critique

1. ✔ **Faux plein écran.** `LayoutMaintainer.swift:1171-1180` `isCommandFullscreenLike` : intent `.command` contenant la fenêtre + taille à 48 px de `visibleFrame`. Une fenêtre seule tilée (gaps 8) remplit la condition. `commandLayoutIntent()` (`DaemonSnapshot.swift:921`) ne passe pas par `validIntent`. Effets : `hideActiveStageSiblingsOfFullscreenWindows` cache les nouvelles fenêtres (l. 187-205, 2372-2401). Même heuristique dans `isMaximizedLike` (l. 1182) et `StageCommands.swift:1037-1053, 983-985`.
2. ✔ **Sortie anticipée globale.** `LayoutMaintainer.swift:196-205` : si un scope actif a une fenêtre plein écran natif (`nativeOnly: true`), `return` pour tous les écrans et `lastObservedFrames` réinitialisé.
3. **Focus bloqué invisible.** `LayoutMaintainer.swift:2496-2572` `restoreFocusedActiveStageIfNeeded` renvoie toujours un tick même si le plan est vide (commandes retirées par `suppressKnownUnmovableFrames` l. 1031-1034) ; sortie l. 175 à chaque tick. Scénario : `toggleFullscreen` (`WindowCommands.swift:458-459`) puis Cmd-Tab vers un frère caché.
4. **Faux « impossible à tiler ».** `LayoutMaintainer.swift:1499-1510` (copie `StageCommands.swift:1419`) somme largeurs ET hauteurs de toutes les fenêtres ; une grille 3 fenêtres avec 2 clampées déclenche le masquage.
5. ✔ **État effacé si illisible.** `JSONPersistence.swift:15-18` `try?` → valeur par défaut ; `StageStore.swift:162-172` ; la sauvegarde suivante écrase tout.
6. **Écritures concurrentes.** `JSONPersistence.swift:41-47` : flock seulement autour de l'écriture ; lectures sans verrou (`StageStore.swift:170`, `StageCommands.swift:81/138/143`, 48 `.save(`). `snapshot()` lit (`DaemonSnapshot.swift:155`), énumère AX, réécrit (`:369`). `LayoutIntentStore` : save/remove/prune = lecture puis écriture complète. `RailRuntimeState.swift:59-63` `setVisibleWidth` sans verrou.
7. ✔ **Pas de timeout AX.** Aucun `AXUIElementSetMessagingTimeout`. `SystemSnapshotProvider.swift:373-397` (~10 appels/fenêtre), `:637`, `:662`, `set()` `:710-731` avec `Thread.sleep` 10 et 20 ms. Tout sur le main thread en mode `run`.
8. **Restauration incomplète (C6).** `roadied/main.swift:394-455`, `RestoreSafetyService.swift:60-133,152-190`. Snapshot écrit au démarrage et à l'arrêt propre seulement ; filtre `isTileCandidate && scope != nil` sans exclure `HiddenWindowPlacement.isHidden` ; arrêt propre ne réaffiche rien ; en modulaire `restore-watch` surveille le pid de `restore-safety` (`main.swift:134-135, 435`) ; SIGHUP non géré (`main.swift:73-84` vs `:413-426`) ; double gestionnaire SIGTERM. Aucun « unhide all ».
9. ✔ **Double close fd.** `RailController.swift:80-107` (config) et `:109-136` (recording) : `close()` immédiat + cancel handler qui ferme plus tard. `startStageStoreWatcher` (`:139-145`) est déjà correct.

## Haute - comportement

10. ✔ **Identité par titre (C4).** `StageStore.swift:509-575` `reconcileWindowIDs` (appel `DaemonSnapshot.swift:172`), `bestReplacement` `:1381-1402` : un seul candidat + titre non vide = rattachement immédiat.
11. **Stage suit le focus système.** `DaemonSnapshot.swift:336-364, 677-692`, `Config.swift:318,341` (`stageFollowsFocus=true`). Protection après commande 3 s (`StageCommands.swift:781,924,963`).
12. **Resize par bord non protégé.** `DropPreviewController.swift:565-568, 603-619` (zone 44 px), `WindowDragActivity.swift:18` (1,5 s), seulement si le rail tourne (`RailController.swift:38`). Tick 500 ms, seuil 16 px (`LayoutMaintainer.swift:2245-2255`).
13. **Config figée dans le daemon.** `DaemonSnapshot.swift:78,110` `private let config` chargé une fois ; `ConfigReloadService` appelé seulement depuis `roadie/main.swift:321`.
14. **Refus mémorisés pour toujours.** `LayoutMaintainer.swift:47-49, 1035-1042, 1052-1077, 1261-1268, 2619-2640, 2665-2691`. `failedAt` jamais utilisé. Purge seulement au changement de topologie (l. 118). `impossibleKnownMinimumIsStillRequested` supprime aussi la position.
15. **BSP ignore la nouvelle fenêtre focalisée.** `BSPTree.swift:122` `inserting(B, nextTo: B)` sur `.leaf(A)` renvoie `self` ; focus global passé (`DaemonSnapshot.swift:1091,1134`).
16. **Stabilisation globale.** `LayoutMaintainer.swift:235-245, 287-293` : `return` global ; nouveau scope actif sans signature précédente (diff l. 794) = 2 s de gel après chaque changement de stage. Même défaut l. 139-159 (levée de suppression globale).
17. **Classement instable.** `DaemonSnapshot.swift:461-606` (`isUnidentifiedTransientWindow`, 760 px, titre vide) ; attributs `nil` si app lente.
18. **Carte fantôme 30 min.** `RailController.swift:1071-1073` + `WindowPresentationStateResolver.swift:42-45` + grâce `DaemonSnapshot.swift:74`. Faux `maximized` sur stage à une fenêtre (`WindowPresentationStateResolver.swift:8`, tolérance 48).
19. **Rail plus masqué devant une fenêtre agrandie.** `RailController.swift:801-835` (diff 015) ; `fullscreenDisplayIDs` `:965-988` devenu code mort ; tests `PowerUserFocusCommandTests.swift:221-269`.
20. **Focus-souris agressif.** `FocusFollowsMouseController.swift:30-43` : pas de test de mouvement, bouton enfoncé, délai.
21. **Pins supprimés sans grâce.** `StageStore.swift:484-489`, `DaemonSnapshot.swift:170,186` ; `.optionOnScreenOnly` (`SystemSnapshotProvider.swift:268`).
- Moteur 7 : `WindowCommands.swift:453-459` `toggleFullscreen` enregistre un intent avec frames périmées (override supprimé).
- Moteur 11 : `StageCommands.swift:878-934` impossible de basculer vers une stage dont toutes les fenêtres ont disparu (grâce 45 s, `StageStore.swift:1164`).
- Moteur 12 : `StageStore.swift:1143-1154, 1052-1079` `updateFrame`/`assign` remettent `presentationState` à nil.
- Moteur 15 : `LayoutMaintainer.swift:1951-1977` axe orthogonal pris dans `lastObservedFrames` même caché.
- C3 : ✔ `SystemSnapshotProvider.swift:221-244, 320-324, 386-398` cache 600 s incluant `isNativeFullscreen`, `isFocused`, `isMain`, `isModal` ; `invalidateCache()` jamais appelé.
- Observer AX : `AXWindowEventObserver.swift:86-104` `AXObserverAddNotification` ignoré, pas de retry, `kAXUIElementDestroyed` seulement sur l'app, `.defaultMode`.
- Correspondance par cadre 48 px : `SystemSnapshotProvider.swift:634-657, 692-700`.
- Veille/réveil non gérés (aucun `didWake`/`willSleep`).
- Masquage 1 px : `HiddenWindowPlacement.swift:5-26`.
- UUID dupliqués : `RailController.swift:796` `Dictionary(uniqueKeysWithValues:)`, `TargetHintService.swift:533,643`.
- `AutomationSnapshotService.swift:9-13` display actif = `.first` d'un Dictionary ; `rules: []` codé en dur l. 30.

## Haute - performance

22. **~20 snapshots/s en monolithique.** `BorderController.swift:24-38` (120 ms, config rechargée), `FocusFollowsMouseController.swift:23-35` (100 ms), `DaemonSnapshot.swift:159` `intentStore.prune` sans condition, `:369` `stageStore.save` sans comparaison. `DaemonHealth.swift:95-113` heal lourd. `SystemSnapshotProvider.swift:561-570` apply O(n²) (`element(matching:)` réénumère par fenêtre).
23. **Navrail.** Hover 80 ms → snapshot (`RailController.swift:234-263, 920-944`) ; redraw cartes 80 ms (`:243-252, 1426-1430`) ; rebuild complet 1 s (`:66-70, 777-861, 1491-1496`, `looksBlank` `:1919-1926`) ; vignettes pleine résolution (`:1946-1958`) ; snapshot par événement de drag (`:709-714`, `DropPreviewController.swift:103-104`).
24. **Bordure.** `BorderController.swift:24-38, 159-166` : config + snapshot toutes les 120 ms, `setFrame`/`orderFrontRegardless` même sans changement.

## Navrail - autres

- Clic qui traverse (`RailController.swift:219-229, 1763-1769`).
- `pendingDrag` bloqué (`:256, 695-757`).
- `revealFrame` déborde sur l'écran voisin (`:1474-1476`).
- Clic sur le fond d'une carte → `focusNativeFullscreen` (`:2505-2513`).
- `activateIgnoringOtherApps` ignoré depuis macOS 14, activation en double (`SystemSnapshotProvider.swift:579-621`), repli par cadre nul (`StageCommands.swift:393`).
- `empty_click_hide_active` change aussi le drop (`RailSettings.swift:150`, `RailController.swift:1679-1697, 740-749`).
- Vignettes purgées pour les membres retenus (`:792-795, 1892-1896`).
- Le rail repositionne des fenêtres (`:886-900, 1465-1472`).
- Event taps sans `tapDisabledByTimeout`, runloop imbriqué (`TargetOverlayPresenter.swift:263-293, 376-386, 492-522, 745-755`).
- Menu de barre de titre : hit test par plus petite fenêtre (`TitlebarContextMenuController.swift:312-321`).
- `retainMissingNormalMembers` inversé (`:1075-1077`).
- Observer d'écran non conservé, pas de `stop()` (`:71-77`).
- Screen Recording jamais vérifié ; capture transparente acceptée (`:3071-3120`).

## Utilisabilité

25. ✔ `roadie/main.swift:468` chemin `<local-path>` ; aussi `scripts/btt/roadie-record-toggle.sh:4`, `README.md:325-330`.
26. `scripts/with-xcode:6-7` impose Xcode.app ; `PATH` fixe sans `/usr/local/bin`.
27. Signature ad hoc (`scripts/install:41`, `scripts/start:42-45`) ; LaunchAgent pointe vers le dépôt.
28. `make restart` = `stop start` → build debug + tmux + retrait LaunchAgent + logs vidés (`scripts/start:15-97`).
29. Pas de verrou global dans `run` (`roadied/main.swift:253-277`) ; pidfile écrit seulement par `scripts/start` (`roadie/main.swift:548-558`, `DaemonHealth.swift:155-167`) ; `ComponentLockFile.swift:46-53, 95-97` non atomique.
30. `(try? RoadieConfigLoader.load()) ?? RoadieConfig()` partout sans log (`DaemonSnapshot.swift:110`, `BorderController.swift:14`, `FocusFollowsMouseController.swift:15`, `LayoutMaintainer.swift:517`, `DesktopCommands.swift:136/198/259`). Validation : `Config.swift:1022-1025, 1133-1177, 1206-1255` (erreurs brutes, clés non vérifiées, `fx.rail.*` signalé à tort).
31. Clés sans effet : `[desktops]`, `stage_manager.enabled`, `hide_strategy` (`Config.swift:241-279`).
32. CLI = scan AX complet par commande (`roadie/main.swift:8`).
33. `--help` code 64 (`roadie/main.swift:491-493`, `roadied/main.swift:324-326`), pas de `--version`, usage incomplet (`:10-73`), JSON incohérent (`:92-94, 123-124, 135`), `cleanup --dry-run` non lu, action sans changement = code 1.
34. `doctor`/`permissions` : pas de Screen Recording, teste le terminal (`PermissionSnapshot.swift`, `Formatters.swift:46-48, 177-203`).
35. Pas de config d'exemple, de raccourcis d'exemple, de `make uninstall`, de rotation de logs ; DMG sans moyen de quitter (`scripts/package-dmg:30-71`).

## Maintenance

36. `tick()` ~360 lignes (`LayoutMaintainer.swift:92-451`), `switchDisplay` ~300 ; bloc « appliquer, réparer, émettre » ×3 (l. 410-425, 476-489, 2511-2534) ; `clampedFramesCannotShareContainer` ×2, `hiddenFrame` ×5 ; `RailController.swift` 3 267 lignes, ~15 types.
37. Seuils dispersés : 16, 24, 48, 64, 120, 0.35, 0.5, 2 s, 4 s, 30 min ; `MutableBSPLayoutStrategy.swift:213-231` compare au gap 24 px fixe et accepte des gaps négatifs.
38. Pas de cible de tests `RoadieAX` ; tests décoratifs (`RoadiedRunFlagsTests.swift`, `ComponentSubcommandTests.swift`, `FileLockTests.swift:57-66` avec `setenv` en parallèle).
39. `CGWindowListCreateImage` (retiré du SDK macOS 15), `activateIgnoringOtherApps` (ignoré depuis macOS 14).

## Robustesse - autres

- `EventLog.swift:68, 98-115` non sûr entre processus (pas d'O_APPEND, rotation sans verrou).
- `EventSubscriptionService.swift:75-89` curseur après rotation, ligne partielle.
- `ConfigReloadService.swift:70`, `LayoutCommandActivity.swift:15-23` `@unchecked Sendable` sans protection.
- Logs stdout launchd sans rotation (`scripts/start:67-70`, `roadied/main.swift:191`).
- `main.swift:368-377` `--ticks` compte les ticks live.
