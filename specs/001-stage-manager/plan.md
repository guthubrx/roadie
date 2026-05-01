# Implementation Plan: Stage Manager Suckless

**Branch**: `001-stage-manager` | **Date**: 2026-05-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-stage-manager/spec.md`

## Summary

Outil CLI macOS suckless qui permet de basculer la visibilité de groupes de fenêtres ("stages") via les API Accessibility. Approche technique : binaire Swift mono-fichier compilé avec `swiftc`, identifiant fenêtre stable obtenu via `_AXUIElementGetWindow` (API privée stable depuis 10.7), persistance en texte plat dans `~/.stage/`. Aucune dépendance externe, aucun build system tiers.

## Technical Context

**Language/Version** : Swift 5.9+ (toolchain Xcode système)
**Primary Dependencies** : Aucune dépendance tierce. Frameworks système macOS uniquement :
  - `Cocoa` (NSWorkspace, NSRunningApplication)
  - `ApplicationServices` (AXUIElement, AXIsProcessTrusted)
  - `CoreGraphics` (CGWindowListCopyWindowInfo, CGWindowID)
  - API privée `_AXUIElementGetWindow` (déclarée localement, liée au runtime via dlsym ou import direct du symbole exporté par HIServices)
**Storage** : Texte plat dans `~/.stage/` (fichiers `1`, `2`, `current`). Format TAB-séparé.
**Testing** : XCTest non utilisé pour le binaire principal (suckless). Tests d'acceptation = scripts shell (`tests/*.sh`) qui exercent le binaire compilé contre un environnement réel et vérifient l'état des fichiers `~/.stage/`. Tests unitaires Swift uniquement si une fonction pure complexe émerge (peu probable).
**Target Platform** : macOS 11 (Big Sur) ou ultérieur, x86_64 + arm64 (binaire universel via `swiftc -target x86_64-apple-macos11 ; lipo`).
**Project Type** : Single project — un binaire CLI standalone.
**Performance Goals** : Bascule < 500 ms pour 10 fenêtres (SC-001). Assignation < 200 ms (SC-002). Démarrage à froid < 100 ms (objectif implicite suckless).
**Constraints** :
  - Binaire ≤ 500 KB sur disque (SC-003)
  - Zéro fuite mémoire sur 100 cycles (SC-005)
  - Code source ≤ 150 lignes Swift effectives visées (cible), plafond strict 200 (constitution projet, principe A). Realité post-implémentation : ~190 lignes effectives hors commentaires/blanches.
  - Sortie standard silencieuse en succès (FR-009)
**Scale/Scope** : 1 utilisateur, 1 machine, 2 stages, jusqu'à 50 fenêtres totales (couvre largement l'usage cible).

## Constitution Check

*GATE: Doit passer avant Phase 0. Re-vérifié après Phase 1.*

### Gates Constitution Globale (`@~/.speckit/constitution.md`)

| Gate | Statut | Justification |
|---|---|---|
| Article I — Documentation française | PASS | spec.md, plan.md, research.md, data-model.md, quickstart.md, contracts/ tous en français |
| Article II — Co-pilote idéation | PASS | Mode `/my.specify-all` autonome, idéation inline sans interruption |
| Article III — Processus SpecKit | PASS | Cycle complet specify → plan → tasks → implement enclenché |
| Article IV — Circuit breaker | PASS | À surveiller en Phase Implement (max 3 tentatives par bug) |
| Article V — Anti scope-creep | PASS | Scope V1 strict défini dans spec.md "Out of Scope" |
| Article VI — Bypass autorisé | N/A | Mode normal |
| Article VII — ADR | À VENIR | À créer si décision technique structurante émerge en Phase 0 |
| Article VIII — Debug forensic | N/A à ce stade | S'appliquera en Phase Implement si besoin |
| Article IX — Recherche préalable | PARTIEL | Recherche conversationnelle préliminaire effectuée (cf. Research Findings dans spec.md). Phase 0 ci-dessous complète sur les API privées |

### Gates Constitution Projet (`.specify/memory/constitution.md`)

| Gate projet | Statut | Justification |
|---|---|---|
| A — Suckless avant tout (≤ 50 lignes par feature, mono-fichier) | PASS prévu | Cible 150 lignes total pour 3 user stories, soit ~50 par feature. Mono-fichier `stage.swift` |
| B — Zéro dépendance externe | PASS | Vérifié dans Technical Context : uniquement frameworks système macOS, pas de SwiftPM/Cocoapods/Carthage |
| C — Identifiants stables uniquement | PASS | Choix `CGWindowID` documenté dans data-model.md, interdiction `(bundleID, title)` respectée |
| D — Fail loud, no fallback | PASS | FR-008 et FR-009 alignés avec ce principe |
| E — État sur disque texte plat | PASS | Format TAB documenté, parsable en 5 lignes Swift |
| F — CLI minimaliste 4 sous-commandes max | PASS | 2 verbes seulement : `stage <N>` (switch) et `stage assign <N>` (assign). Aucune option flag |

### Vérification cumulée

- [x] Aucun `import Package` ni dépendance tierce dans le design proposé
- [x] Aucun usage de `(bundleID, title)` comme clé primaire (CGWindowID utilisé)
- [x] Toute action sur fenêtre tracée à un `CGWindowID`
- [x] Le binaire compilé visé < 500 KB (vérification post-build, pas un risque)

**Verdict** : aucune violation. Pas de section Complexity Tracking nécessaire.

## Project Structure

### Documentation (this feature)

```text
specs/001-stage-manager/
├── plan.md                         # Ce fichier
├── research.md                     # Phase 0 — décisions techniques
├── data-model.md                   # Phase 1 — entités & format fichiers
├── quickstart.md                   # Phase 1 — install + first run
├── contracts/
│   └── cli-contract.md             # Phase 1 — signature CLI complète
├── checklists/
│   └── requirements.md             # Validation spec
└── tasks.md                        # Phase 3 (créé par /speckit.tasks)
```

### Source Code (repository root)

```text
stage.swift                         # Source unique (~150 lignes)
Makefile                            # 5 lignes : build + install
tests/
├── 01-permission.sh                # Vérifie comportement sans Accessibility
├── 02-assign.sh                    # Assigne frontmost, vérifie ~/.stage/N
├── 03-switch.sh                    # Bascule, vérifie minimisation
├── 04-disappeared.sh               # Tolérance fenêtres disparues
└── helpers.sh                      # Setup/teardown communs
README.md                           # Pointeur vers quickstart.md
```

**Structure Decision** : Single-project, mono-fichier. Le projet n'a pas de couches métier à séparer (pas de modèles, services, contrôleurs distincts) — c'est un binaire de glue entre AX API et fichiers texte. Tout artifice de structure (dossiers `src/`, `models/`, `services/`) violerait le principe A (suckless). La séparation `stage.swift` + `tests/` suffit.

## Complexity Tracking

Aucune violation de constitution à justifier — section vide intentionnellement.
