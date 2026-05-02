# Implementation Plan: Desktop par Display (mode global ↔ per_display)

**Branch** : `013-desktop-per-display` | **Date** : 2026-05-02 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/013-desktop-per-display/spec.md`

## Summary

Étendre `DesktopRegistry` (SPEC-011) pour supporter un état per-display optionnel (`currentByDisplay: [CGDirectDisplayID: Int]`) avec deux modes runtime : `global` (défaut, comportement V2 préservé) et `per_display`. Déplacer la persistance disque sous une racine indexée par `displayUUID` (`~/.config/roadies/displays/<uuid>/desktops/<id>/state.toml`) pour conserver l'historique de chaque écran physique au-delà d'un débranchement, et restaurer ce contenu au rebranchement. Ajouter une migration one-shot V2→V3 transparente. Aucune dépendance ajoutée. ~600 LOC code + ~400 LOC tests.

## Technical Context

**Language/Version** : Swift 6.0 (SwiftPM ; cf. déjà existant SPEC-002+)
**Primary Dependencies** : `RoadieCore`, `RoadieDesktops`, `RoadieTiler` (modules locaux SwiftPM) ; **TOMLKit** (déjà présent depuis SPEC-011 pour la sérialisation toml — pas de nouvelle dépendance)
**Storage** : fichiers TOML plats sous `~/.config/roadies/displays/<uuid>/`
**Testing** : XCTest + suite Swift Testing existante (`Tests/RoadieDesktopsTests/`, `Tests/RoadieCoreTests/`, `Tests/RoadieTilerTests/`)
**Target Platform** : macOS 14+ (Sequoia), arm64 + x86_64 ; pas de SIP-off requis
**Project Type** : single Swift package multi-module (daemon + CLI + libraries FX)
**Performance Goals** : `desktop focus N` < 200 ms (FR perçu, conservé depuis SPEC-011 SC-002) ; restoration au rebranchement < 1 s pour ≤ 20 fenêtres
**Constraints** : zéro régression mode `global` ; migration V2→V3 idempotente ; aucune perte d'état lors du switch de mode à chaud ; pas d'API privée nouvelle (réutilise celles de SPEC-012)
**Scale/Scope** : ~600 LOC code Swift (cible), plafond 800 LOC. Tests ~400 LOC. ≤ 6 fichiers source touchés (DesktopRegistry, Daemon main, CommandRouter, persistence, Config, CLI).

**Cible LOC effectives** : 600 (code Swift hors tests, hors commentaires/blanches)
**Plafond strict** : 800 (= +33 %, justification dans Complexity Tracking si dépassé)

## Constitution Check

| Gate constitutionnel | État | Justification |
|---|---|---|
| **A. Suckless avant tout** | ✅ PASS | Réutilise les structures existantes (`DesktopRegistry`, `Display`, `WindowState`). Aucune abstraction nouvelle au-delà de la map `currentByDisplay` et du mode enum. |
| **B. Zéro dépendance externe** | ✅ PASS | Utilise uniquement `RoadieCore`/`RoadieDesktops`/`RoadieTiler` (modules locaux) + `TOMLKit` (déjà présente). Aucun nouveau package. |
| **C. Identifiants stables** | ✅ PASS | Persistance et matching via `cgWindowID` (UInt32) + `displayUUID` (String stable de `CGDisplayCreateUUIDFromDisplayID`). Fallback secondaire `bundleID + title` UNIQUEMENT au matching de restoration (rare et explicite, justifié par la résilience cross-session). |
| **D. Fail loud** | ✅ PASS | `currentByDisplay[id]` introuvable → log warn explicite + fallback documenté (primary). Aucun retry silencieux. State.toml corrompu → log error + skip de l'entry concernée (FR-020). |
| **E. État sur disque = TOML plat** | ✅ PASS | Persistance via TOMLKit (texte plat, lisible `cat`/`grep`). Pas de JSON ni binaire. Une ligne par fenêtre (compat avec format SPEC-011). |
| **F. CLI minimaliste** | ✅ PASS | Aucun nouveau verbe CLI. `desktop list/focus/current` étendus avec colonnes `display_id`. Pas de flags ajoutés. |
| **G. LOC explicite** | ✅ PASS | Cible 600 / plafond 800 déclarés ci-dessus. |

**Tous gates PASS.** Aucune violation à justifier en Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/013-desktop-per-display/
├── plan.md              # This file (/speckit.plan output)
├── spec.md              # Phase 0 output (/speckit.specify)
├── research.md          # Phase 0 output (/speckit.plan)
├── data-model.md        # Phase 1 output (/speckit.plan)
├── quickstart.md        # Phase 1 output (/speckit.plan)
├── contracts/           # Phase 1 output (/speckit.plan)
│   └── desktop-per-display.md   # Schéma JSON-RPC + format TOML persistance
├── checklists/
│   └── requirements.md  # Phase 0 quality checklist (✅ all PASS)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/
│   ├── Config.swift                  # T001 : champ `mode: String` dans DesktopsConfig + parser
│   ├── Display.swift                 # touche minime : aucun changement structurel
│   └── DisplayRegistry.swift         # touche minime : helper displayContainingFrontmost
├── RoadieDesktops/
│   ├── DesktopRegistry.swift         # T010-T015 : currentByDisplay map, mode handling
│   ├── DesktopPersistence.swift      # T020-T024 : nouvelle racine displays/<uuid>/
│   └── DesktopMigration.swift (NEW)  # T030-T032 : migration V2 → V3 one-shot
├── roadied/
│   ├── main.swift                    # T040-T044 : intégration mode + reload + recovery
│   └── CommandRouter.swift           # T050-T053 : desktop focus/list/current → per_display
└── roadie/
    └── main.swift                    # T060 : sortie CLI desktop list multi-colonnes

Tests/
├── RoadieCoreTests/
│   └── ConfigDesktopsModeTests.swift (NEW)         # T070
├── RoadieDesktopsTests/
│   ├── DesktopRegistryPerDisplayTests.swift (NEW)  # T071
│   ├── DesktopPersistenceUUIDTests.swift (NEW)     # T072
│   ├── DesktopMigrationTests.swift (NEW)           # T073
│   └── DesktopRecoveryTests.swift (NEW)            # T074
└── RoadieTilerTests/
    └── DragCrossDisplayDesktopTests.swift (NEW)    # T075
```

**Structure Decision** : single Swift package multi-module (= structure existante du projet). Aucun nouveau module ; on étend les 5 modules existants. Création d'un fichier neuf `DesktopMigration.swift` pour isoler la logique de migration one-shot (testable sans daemon).

## Complexity Tracking

> Aucune violation des gates constitutionnels. Section vide.
