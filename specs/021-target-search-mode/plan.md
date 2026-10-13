# Implementation Plan: Mode recherche du mode lettres

**Branch**: `021-target-search-mode` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

Un raccourci global (Commande+Option+Contrôle+F par défaut, clé `search_hotkey` de `[experimental.target_mode]`) ouvre une session « recherche » : les étiquettes des cibles s'affichent avec une barre de saisie en bas de l'écran ; le texte tapé filtre les cibles (casse, accents, espaces ignorés), la première correspondance est mise en avant en vert, la navigation et la validation suivent Homerow. Le texte des enfants est rattaché aux cibles web sans appel AX supplémentaire.

## Technical Context

**Language/Version**: Swift 6, macOS 14+
**Primary Dependencies**: AppKit, Carbon (`RegisterEventHotKey`, `TISCopyCurrentKeyboardLayoutInputSource`, `UCKeyTranslate`), ApplicationServices. Aucune dépendance externe.
**Testing**: Swift Testing (`./scripts/test`) : modèle de recherche, analyse du raccourci, validation de configuration ; test manuel dans Bluejay, T3 Code, Finder.
**Performance Goals**: ouverture dans le budget du parcours (`timeout_ms`) ; filtrage à chaque frappe en O(n), n ≤ `max_targets` + cibles Roadie.
**Constraints**: mode lettres existant inchangé (FR-007) ; aucune interception clavier hors session.

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| III | spec, plan, tâches avant code | OK |
| XVI | worktree `.worktrees/021-target-search-mode` | OK |
| XVIII | filtrage O(n) par frappe ; traduction du raccourci O(128) au rechargement ; texte des enfants O(1) par élément | OK |
| XIX | un modèle pur (≥ 3 usages : filtrage, navigation, validation), un enregistreur de raccourci, une clé de config | OK |
| XX | logique testable séparée de l'affichage | OK |

## Project Structure

```text
Sources/RoadieCore/Config.swift                      # search_hotkey (+ validation, knownKeys)
Sources/RoadieDaemon/TargetSearchModel.swift         # NOUVEAU : modèle pur de recherche
Sources/RoadieDaemon/TargetSearchHotkey.swift        # NOUVEAU : analyse + enregistrement du raccourci global
Sources/RoadieDaemon/TargetOverlayPresenter.swift    # session recherche, touches, barre de saisie, mise en avant
Sources/RoadieDaemon/TargetModeRuntimeController.swift # commande targets.search
Sources/RoadieDaemon/TargetHintService.swift         # action command-click
Sources/RoadieDaemon/AppTargetQueryService.swift     # Cmd-clic ; texte des enfants des feuilles web
Sources/RoadieDaemon/CLICommandRouter.swift          # roadie targets search
Sources/roadied/main.swift                           # démarrage du raccourci
Tests/RoadieDaemonTests/TargetSearchModelTests.swift # NOUVEAU
Tests/RoadieDaemonTests/TargetSearchHotkeyTests.swift # NOUVEAU
docs/fr/features.md, docs/en/features.md, examples/roadies.toml
```

## Complexity Tracking

Aucune violation.
