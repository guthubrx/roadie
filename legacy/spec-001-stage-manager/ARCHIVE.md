# Archive — SPEC-001 stage-manager (suckless mono-fichier)

**Statut** : archivé 2026-05-01. **Le code suivant n'évolue plus.** Successeur : `Sources/RoadieStagePlugin/StageManager.swift` (SPEC-002).

## Pourquoi cette archive

SPEC-001 est l'origine du projet : un Stage Manager macOS suckless, mono-fichier `stage.swift` (259 LOC), sans dépendance externe. La spec a été implémentée à 11/13 (T037 + T038 = stress tests reportés), validée par audit Grade A.

SPEC-002 (tiler V1 + StageManager modulaire) a refondu le concept en plusieurs targets Swift Package Manager (`RoadieCore`, `RoadieStagePlugin`, `RoadieTiler`). Le code mono-fichier ici est conservé comme **référence historique** :

- comparaison de complexité : 259 LOC suckless vs ~2014 LOC V1 modulaire
- exemple de Stage Manager minimal sans tiler ni multi-desktop
- usage utilisateur direct possible : `make` puis `./stage 1|2` ou `./stage assign 1|2`

## Fichiers

| Fichier | Description |
|---|---|
| `stage.swift` | Mono-fichier 259 LOC, frameworks système macOS uniquement |
| `Makefile` | Build minimal (clang+swift-frontend, target binaire `stage`) |
| `README.md` | Quickstart SPEC-001 |
| `CLAUDE.md` | Instructions Claude pour la session SPEC-001 (historique) |
| `karabiner-stage.json` | Config Karabiner pour bind les touches Capslock+1/2 → `stage 1/2` |
| `audits/` | Audit Grade A de cycle final |
| `tests/` | Tests d'intégration shell (3 scripts) |

## Compilation locale

```bash
cd legacy/spec-001-stage-manager
make
./stage 1            # bascule stage 1
./stage assign 2     # assigne fenêtre frontmost à stage 2
```

État persisté dans `~/.stage/` (texte plat).

## Ne pas évoluer

Toute évolution Stage Manager va dans `Sources/RoadieStagePlugin/` (V1+) ou via SPEC-003 multi-desktop. **Cette archive est figée.**
