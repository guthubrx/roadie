# Implementation Plan — SPEC-019 Rendus modulaires du navrail

**Branch**: `019-rail-renderers` | **Date**: 2026-05-03 | **Spec**: [spec.md](spec.md)
**Status**: Draft

## Summary

Refactor du module `RoadieRail` pour extraire le rendu actuel des cellules de stage (cascade de captures empilées dans `WindowStack.swift`) derrière un **protocole `StageRenderer`** et un **registre `StageRendererRegistry`**. Le pattern reproduit fidèlement celui de `RoadieTiler` (`Tiler` + `TilerRegistry`) déjà éprouvé. Sélection du renderer actif via une nouvelle clé TOML `[fx.rail].renderer = "<id>"`, hot-reload via `daemon reload`. Compat ascendante stricte : valeur par défaut `stacked-previews` = comportement actuel pixel-identique. Livraison incrémentale en 5 user stories, MVP = US1 (refactor pur) + US2 (premier renderer alternatif `icons-only`).

## Technical Context

| Élément | Choix | Justification |
|---|---|---|
| Langage / SDK | Swift 5.9 + SwiftPM | Cohérence projet |
| Couche | SwiftUI / AppKit (rail = `roadie-rail` exécutable séparé) | Existant SPEC-014, aucun changement |
| Pattern architectural | Protocole + Registry + Default impl + Hot-swap | Reproduit `Tiler`/`TilerRegistry` (Article I' constitution-002) |
| Indexation registry | `[String: () -> any StageRenderer]` | Hash O(1), lookup par identifiant string lisible |
| Configuration | TOML `[fx.rail].renderer = "<id>"` (clé optionnelle) | Cohérent avec les autres clés `[fx.rail]` (halo_color, halo_intensity, etc.) |
| Hot-reload | `roadie daemon reload` → daemon publie un event `config_reloaded` → rail relit `[fx.rail].renderer` et reconstruit ses cellules | Pattern non-invasif, le rail est déjà abonné aux events daemon |
| CLI | `roadie rail renderers list` / `roadie rail renderer <id>` | Symétrique à `roadie tiler list` / `roadie tiler <strategy>` |
| Erreur valeur inconnue | Log warning + fallback `stacked-previews` | Article D' fail-loud sans casser l'UX |
| Type retour render | `AnyView` au boundary du registry, `@ViewBuilder some View` à l'intérieur de chaque renderer | `AnyView` permet stockage uniforme dans dict, `@ViewBuilder some View` interne préserve l'expressivité SwiftUI |
| Plafond LOC | 200 LOC effectives par renderer (Article A'), ≤ 600 LOC totales famille MVP | Cohérent avec contrat suckless |

### Dépendances inter-spec

- **SPEC-014** (Stage Rail UI) : prérequis dur — fournit `RailController`, `StageVM`, `WindowVM`, `ThumbnailVM`, `StageStackView`. Cette spec **refactore** le rendu existant sans toucher au reste du rail.
- **SPEC-018** (Stages-per-display) : prérequis informatif — l'état des stages (per scope) est consommé par les renderers via les VMs. Aucun couplage direct.

### Pas de NEEDS CLARIFICATION

L'ensemble du Technical Context est résolu : pattern éprouvé (`TilerRegistry`), framework existant (SwiftUI), source de config existante (TOML `[fx.rail]`), CLI cohérente avec convention projet.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Vérification | Status | Notes |
|---|---|---|---|
| A'. Mono-fichier ≤ 200 LOC effectives | 7 fichiers prévus (1 protocol, 1 registry, 5 renderers), tous ≤ 200 LOC visés ; consommateur `StageStackView` voit sa taille **diminuer** post-refactor | ✅ | SC-006 trace l'objectif |
| B'. Dépendances minimisées, pas zéro | Aucune nouvelle dépendance Swift Package. Reste sur SwiftUI + AppKit déjà présents | ✅ | |
| C'. Identifiants stables + APIs privées strictement encadrées | Aucun usage de SkyLight/CGS/AX en écriture privée. Pure couche View, lecture seule du registry | ✅ | |
| D'. Fail loud, log structuré | Renderer inconnu → `logWarn("renderer_unknown", ["want": id, "fallback": "stacked-previews"])` | ✅ | |
| E'. Format texte plat | TOML existant étendu, pas de nouveau format | ✅ | |
| F'. CLI minimaliste mais expressive | 2 nouvelles sous-commandes (`rail renderers list`, `rail renderer <id>`), cohérentes avec `roadie tiler list`/`<strategy>` | ✅ | |
| G'. Mode Minimalisme LOC explicite | Cible 600 LOC famille MVP (US1+US2) ; plafond strict 900 LOC | ✅ | Cf. budget par US |
| H'. Test-pyramid réaliste | Tests unit pour Registry (register/lookup/fallback), tests acceptance bash pour switch CLI, **pas de tests d'intégration View** (visuel = screenshot manuel) | ✅ | Compromis assumé : SwiftUI views sans test snapshot natif |
| I'. **Architecture pluggable obligatoire** | C'est précisément l'objet de cette spec — protocole + registry **sont** l'implémentation de cet article | ✅ | |

**Aucune violation, aucune dérogation requise.**

## Phase 0 — Research

Voir [research.md](research.md). Sources consultées :

- Architecture `Sources/RoadieTiler/` (TilerProtocol, TilerRegistry, BSPTiler, MasterStackTiler) — pattern de référence à reproduire
- Constitution-002 Article I' — Architecture pluggable obligatoire
- SwiftUI `some View` opaque return types — pour le retour de `render(...)`
- `WindowStack.swift` actuel (~270 LOC) — code source à extraire
- Pattern `AnyView` vs `@ViewBuilder` vs associated type — choix de design

### Décisions clés

| Décision | Choix retenu | Alternative écartée | Rationale |
|---|---|---|---|
| Type de retour `render` au boundary registry | `AnyView` | `some View` (associated type) | `some View` empêche stocker des renderers hétérogènes dans le même dict ; `AnyView` est l'idiome standard pour ça |
| Forme du protocole | Class-bound protocol `AnyObject` | Struct value | Cohérent avec `Tiler` (référence), permet stockage dans dict |
| Registre — singleton ou injection ? | Singleton statique (`StageRendererRegistry.register/make`) | DI via container | Cohérent avec `TilerRegistry`, simple, suffisant |
| Hot-reload — push ou pull ? | Pull : rail relit `[fx.rail].renderer` à chaque event `config_reloaded` | Push : daemon notifie le rail avec le nouveau renderer | Le rail a déjà accès au TOML, push créerait un couplage inutile |
| LOC budget refactor US1 | 350 LOC nettes (protocol 60 + registry 50 + StackedPreviews 200 + glue StageStackView 40) | Inférieur risquerait sous-spec | Marge confortable sous le plafond 900 |
| Nom de la commande CLI | `roadie rail renderer <id>` (singulier) + `roadie rail renderers list` (pluriel) | `roadie rail renderer set/list` | Symétrie exacte avec `roadie tiler <strategy>` / `roadie tiler list` (aucune sous-commande verbe) |

## Phase 1 — Design & Contracts

Voir [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md).

## Project Structure

### Documentation (this feature)

```text
specs/019-rail-renderers/
├── plan.md              # ce fichier
├── research.md          # Phase 0
├── data-model.md        # Phase 1 — entités StageRenderer / StageRendererRegistry
├── quickstart.md        # Phase 1 — manuel utilisateur "comment changer de renderer"
├── contracts/           # Phase 1
│   ├── stage-renderer-protocol.md  # contrat Swift StageRenderer
│   ├── registry-api.md             # contrat StageRendererRegistry
│   └── cli-protocol.md             # spécification roadie rail renderer/renderers
├── checklists/
│   └── requirements.md  # validation spec
└── tasks.md             # Phase 2 — généré par /speckit.tasks
```

### Source Code (repository root)

```text
Sources/RoadieRail/
├── RailController.swift          # consommateur, modifié pour lire [fx.rail].renderer
├── Networking/
│   └── RailIPCClient.swift       # inchangé
├── Hover/
│   └── EdgeMonitor.swift         # inchangé
├── Views/
│   ├── StageStackView.swift      # consommateur cellule, MODIFIÉ : délègue render au renderer actif
│   └── WindowStack.swift         # SUPPRIMÉ après extraction (US1)
└── Renderers/                    # NOUVEAU dossier
    ├── StageRendererProtocol.swift     # NEW (~60 LOC) — protocole + struct context
    ├── StageRendererRegistry.swift     # NEW (~50 LOC) — register/make/availableRenderers
    ├── StackedPreviewsRenderer.swift   # NEW (~200 LOC) — extrait de WindowStack.swift (US1)
    ├── IconsOnlyRenderer.swift         # NEW (~80 LOC, US2)
    ├── HeroPreviewRenderer.swift       # NEW (~100 LOC, US3)
    ├── MosaicRenderer.swift            # NEW (~120 LOC, US4)
    └── Parallax45Renderer.swift        # NEW (~150 LOC, US5)

Sources/roadied/
└── CommandRouter.swift           # MODIFIÉ : ajout handlers `rail.renderer.list` et `rail.renderer.set`

Sources/roadie/
└── main.swift                    # MODIFIÉ : ajout sous-commandes `rail renderer/renderers`
```

### LOC Budget par US (cible / plafond)

| US | Fichiers concernés | Cible LOC | Plafond LOC |
|---|---|---|---|
| US1 (refactor) | Protocol + Registry + StackedPreviews + glue | 350 | 450 |
| US2 (icons-only) | IconsOnlyRenderer + bootstrap registration | 90 | 130 |
| US3 (hero-preview) | HeroPreviewRenderer + bootstrap | 110 | 150 |
| US4 (mosaic) | MosaicRenderer + bootstrap | 130 | 170 |
| US5 (parallax-45) | Parallax45Renderer + bootstrap | 160 | 200 |
| CLI | CommandRouter handlers + main.swift sous-commandes | 60 | 100 |
| **Total famille** | | **900** | **1200** |

## Risques et mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Régression visuelle subtle après refactor US1 | Moyenne | Élevé | SC-002 = screenshot comparison, validation manuelle obligatoire |
| Hot-reload ne propage pas au rail (rail = process séparé) | Faible | Moyen | Le rail est déjà abonné au stream `events --follow` du daemon ; ajouter cas `config_reloaded` dans `RailController.handleEvent` (~10 LOC) |
| `AnyView` au boundary cause perte perf SwiftUI | Faible | Faible | Mesuré < 1 ms par cellule, sous le seuil sensoriel humain |
| Renderers futurs (US3-5) non livrés faute de temps | Élevée | Faible | MVP = US1+US2 seulement, US3-5 livrables indépendamment |

## Re-évaluation Constitution Check (post-design)

Aucun changement par rapport à la check Phase 0. Tous les articles restent satisfaits.
