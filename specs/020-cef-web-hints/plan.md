# Implementation Plan: Lettres d'accès dans Bluejay

**Branch**: `020-cef-web-hints` (Roadie) et `pr/029-macos-renderer-accessibility` (Grayjay, build Bluejay) | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

Deux obstacles, deux dépôts.

1. **Bluejay** (`/Users/moi/11.Repositories/grayjay`) : sur macOS, ajouter `--force-renderer-accessibility` au démarrage de CEF (`Grayjay.Desktop.CEF/Program.cs:394`), sur une branche locale `pr/029-macos-renderer-accessibility` basée sur `origin/master`. Intégration dans `bluejay/all-features` et build par `build-bluejay-with-prs.sh`, selon `AGENTS.md` du dépôt.
2. **Roadie** (`Sources/RoadieDaemon/AppTargetQueryService.swift`) : dans une zone web, retenir les « feuilles focalisables » (research.md) ; journaliser la répartition des rôles écartés.

## Technical Context

**Language/Version**: Swift 6 (Roadie) ; C# .NET (Bluejay, une ligne)
**Primary Dependencies**: ApplicationServices. Aucune nouvelle dépendance.
**Testing**: Swift Testing (`./scripts/test`) ; mesure `targets.app_scan` ; test manuel dans Bluejay
**Performance Goals**: un appel AX en plus par élément de zone web non candidat ; aucun hors zone web
**Constraints**: Grayjay amont non modifié ; aucune nouvelle clé de configuration ; aucun relayout (FR-007 de 018)
**Scale/Scope**: Roadie 2 fichiers source + 2 de tests ; Bluejay 1 fichier

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| III SpecKit | spec, plan, tâches avant code | OK |
| VIII Forensic | relevé jetable installé, mesuré, retiré ; données personnelles supprimées | OK |
| XVI Worktree | Roadie `.worktrees/020-cef-web-hints` ; Grayjay : worktree dédié pour la branche `pr/*` | OK |
| XVIII Complexité | parcours O(n) ; règle des feuilles O(m + p + u × d) (marqueurs, feuilles en attente, chemins restés dans la pile et leur profondeur) ; histogramme O(n) + tri O(k log k), k rôles distincts | OK |
| XIX Minimalisme | une règle, deux fonctions pures, aucun réglage | OK |
| XX | règle choisie sur mesure réelle, pas sur supposition | OK |

## Project Structure

```text
specs/020-cef-web-hints/ : spec, plan, research, data-model, contracts/app-scan-event.md, quickstart, reuse-audit, tasks
Sources/RoadieDaemon/AppTargetQueryService.swift   # zone web, feuilles focalisables, rôles écartés
Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift
Tests/RoadieDaemonTests/TargetHintServiceTests.swift  # champ rejectedRoles dans l'événement
/Users/moi/11.Repositories/grayjay/Grayjay.Desktop.CEF/Program.cs  # branche pr/029
```

## Complexity Tracking

Aucune violation.
