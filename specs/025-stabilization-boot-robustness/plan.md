# Implementation Plan: Stabilization sprint — boot robustness + BUG-001 fix

**Branch**: `025-stabilization-boot-robustness` | **Date**: 2026-05-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/025-stabilization-boot-robustness/spec.md`

## Summary

Sprint de stabilisation post-SPEC-024 qui adresse 7 user stories prioritisées (P1×3, P2×3, P3×1) sans introduire aucune nouvelle feature visible utilisateur. Cible : éliminer les classes de drift connues (frames offscreen persistées, wids zombies, drift widToScope, BUG-001) et fournir des outils d'auto-cicatrisation (`roadie heal`, audit auto au boot, health metric, `roadie diag` bundle). Le fix réel BUG-001 (option B FR-007) a été appliqué sans dépasser le time-box.

> **Implementation status** (post-merge) : livré commits `453e511` (sprint complet) + `936bdf3` (audit fixes L3 + L4). Audit grade A-. Delta LOC effectif +310 (justifié US7 ajoutée en cours, tracé Complexity Tracking ci-dessous). 2 fixes audit appliqués (L3 thread-safety static var, L4 tar exit code check).

## Technical Context

**Language/Version** : Swift 5.9, swift-tools 5.9
**Primary Dependencies** : AppKit, ApplicationServices, CoreGraphics, ScreenCaptureKit, SwiftUI, Combine, TOMLKit (existants, aucun ajout)
**Storage** : `~/.config/roadies/stages/<uuid>/<desktop>/<stage>.toml` (état stages persisté), `~/.local/state/roadies/daemon.log` (logs JSON-lines)
**Testing** : XCTest (existant) + 3 nouveaux tests shell `Tests/25-*.sh` (acceptation E2E)
**Target Platform** : macOS 14 (Sonoma) minimum, validé sur Tahoe 26
**Project Type** : single — projet Swift Package Manager, exécutables + libraries
**Performance Goals** :
- Auto-fix au boot ≤ 200 ms (ne pas allonger le bootstrap perceptible)
- `roadie heal` ≤ 3 s wall-clock (cf. SC-003)
- `daemon.health` réponse ≤ 50 ms

**Constraints** :
- Pas de breaking change CLI/socket/events (FR-011)
- Aucune nouvelle dépendance externe (Article B' constitution-002)
- Codesign ad-hoc roadied-cert (cf. ADR-008, recheck-tcc.sh livré par SPEC-024)

**Scale/Scope** :
- Codebase actuel : ~14 400 LOC effectives post-SPEC-024
- Cible delta SPEC-025 : **+120 LOC nettes** (validation, auto-fix, heal command, GC)
- Plafond strict : **+200 LOC** (au-delà → ADR Complexity Tracking)

### Cible / Plafond LOC pour cette spec (art G' constitution-002)

- **Cible** : delta net ≤ **+120 LOC effectives** sur l'ensemble du projet
- **Plafond strict** : delta net ≤ **+200 LOC**

Composantes attendues :

| Composant | LOC estimées |
|---|---|
| `Stage.validateMembers(against:)` (validation saved_frame au load) | +25 |
| Auto-fix au boot (3 lignes appel + log) dans `Daemon.bootstrap` | +15 |
| `BootStateHealth` struct + sérialisation JSON | +20 |
| `daemon.health` handler IPC | +20 |
| `daemon.heal` handler IPC | +20 |
| `roadie heal` sub-command CLI | +10 |
| GC `.legacy.*` dans `StageManager.saveStage` | +10 |
| `HideStrategyImpl.show()` fallback safe | +10 |
| Tests shell `25-*.sh` | (hors LOC Swift) |
| Configs/docs README | (hors LOC Swift) |
| **TOTAL estimé** | **+130 LOC** |

Marge avant plafond : 70 LOC.

## Constitution Check

*GATE: doit passer avant Phase 0 research. Re-check après Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Aucun fichier Swift > 200 LOC effectives | ✓ | Tous les ajouts sont dans des fichiers existants ; aucun ne dépasse les 200 LOC après ajout |
| Aucune dépendance externe non justifiée | ✓ | Zéro nouvelle dépendance |
| CGWindowID utilisé partout | ✓ | Refactor ne touche pas les clés |
| FR-005 art C' : aucun symbole CGS d'écriture linké au daemon core | ✓ | Pas de nouveau lien |
| Tiler protocol ≥ 2 implémentations | ✓ | BSP + Master-Stack inchangés |
| StagePlugin séparé compilable sans Stage flag | ✓ | Architecture modulaire préservée |
| Logger structuré JSON-lines, pas de `print()` | ✓ | Convention maintenue |
| Tests unitaires existants pour code pur | ✓ | Tests Tiler/Tree/Config inchangés |
| LOC effectives < plafond | ✓ pré-existant | Projet à ~14 400 LOC. Cette spec ajoute ~120 LOC. Plafond pré-existant déjà dépassé depuis SPEC-014 ; pas une nouvelle violation |
| Audit `/audit` mesure et rapporte LOC | ✓ | Pratique en place |

→ **Aucune nouvelle violation. Pas de Complexity Tracking nécessaire.**

## Project Structure

### Documentation (this feature)

```text
specs/025-stabilization-boot-robustness/
├── plan.md              # Ce fichier
├── research.md          # Phase 0 — investigation BUG-001 tree leaf manquant
├── data-model.md        # Phase 1 — BootStateHealth struct, validation flow
├── quickstart.md        # Phase 1 — guide utilisateur troubleshooting
├── contracts/
│   └── ipc-additions.md # daemon.health + daemon.heal (additifs au contrat figé SPEC-024)
└── tasks.md             # Phase 2 — 4 vagues, ~25 tâches
```

### Source Code (repository root)

État cible (modifications minimales) :

```text
Sources/
├── roadied/
│   ├── main.swift                  # +20 LOC : auto-fix au boot + log boot_state_health
│   └── CommandRouter.swift         # +40 LOC : daemon.health + daemon.heal handlers
├── roadie/
│   └── main.swift                  # +10 LOC : roadie heal subcommand
├── RoadieCore/
│   ├── BootStateHealth.swift       # NOUVEAU ~30 LOC : struct + sérialisation
│   └── HideStrategy.swift          # +10 LOC : fallback safe dans show()
├── RoadieStagePlugin/
│   └── StageManager.swift          # +35 LOC : validateMembers + GC saveStage
└── RoadieRail/
    └── RailController.swift        # 1 LOC : default empty_click_hide_active = false

scripts/
└── install-dev.sh                  # +5 LOC : cleanup .legacy.* > 7 jours

Tests/
├── 25-boot-with-corrupted-saved-frame.sh   # NOUVEAU
├── 25-boot-with-zombie-wids.sh              # NOUVEAU
└── 25-heal-command.sh                       # NOUVEAU

README.md / README.fr.md            # +30 lignes : section Troubleshooting
```

**Structure Decision** : modifications chirurgicales sur les fichiers existants + 1 seul nouveau fichier Swift (`BootStateHealth.swift`). Aucune restructure modulaire. Les contrats IPC publics ajoutent uniquement `daemon.health` et `daemon.heal` (additifs, ne cassent pas SPEC-024 contract frozen).

## Vagues d'exécution

Plan d'attaque incrémental. Chaque vague est indépendamment testable et commitable.

### Vague 0 — Quick wins (30 min)

Pas de spec dédiée, juste 2 commits.

- **V0.1** : Désactiver `empty_click_hide_active = false` par défaut dans `RailController.swift` (FR-006, US5). 1 ligne. Build + test rail clic vide → no-op.
- **V0.2** : Ajouter cleanup `.legacy.*` > 7 jours dans `install-dev.sh` (FR-010, US6 partiel). 1 commande `find` + bash. Test : créer fichiers fake, run install-dev, vérifier suppression.

**Sortie** : 2 commits, push pas obligatoire à ce stade.

### Vague 1 — Boot robustness (1 jour)

Cœur de la spec. Adresse US1, US2, US3.

- **V1.1** (FR-001) : `Stage.validateMembers(against: DisplayRegistry)` dans `StageManager.swift`. Au load, pour chaque member, si `saved_frame` n'est dans aucun display connu → reset à `.zero`. Test injection TOML pollué.
- **V1.2** (FR-002) : Auto-fix au boot — appel `purgeOrphanWindows + rebuildWidToScopeIndex` dans `Daemon.bootstrap` après `loadFromDisk`. Log `boot_audit_autofixed` ou `boot_audit_clean`.
- **V1.3** (FR-003) : `BootStateHealth.swift` créé dans RoadieCore. Émis comme log JSON-lines `boot_state_health` à la fin du bootstrap.
- **V1.4** (FR-004) : Handler `daemon.health` dans CommandRouter. Retourne le state health courant (recalculé à la demande, pas cached).
- **V1.5** (FR-009) : GC `.legacy.*` > 7 jours dans `StageManager.saveStage`. Idempotent silencieux.
- **V1.6** (FR-013) : Test shell `Tests/25-boot-with-corrupted-saved-frame.sh` + `25-boot-with-zombie-wids.sh`.

**Sortie** : 1 commit `feat(SPEC-025 boot-robustness)`, build clean, tous les tests existants verts.

### Vague 2 — BUG-001 fix réel (time-box 3h)

Adresse US1 acceptance scenario 2 (cycle hide_active → switch back). Risque technique.

- **V2.1** (investigation, 1h) : ajouter logs ciblés dans `HideStrategyImpl.hide/show` + `LayoutEngine.setLeafVisible` pour tracer `expectedFrame`, `state.frame`, `tree leaf found`. Reproduire le scénario manuellement, observer.
- **V2.2** (fix FR-007, 1h) : modifier `HideStrategyImpl.show()` pour fallback `displayManager.workArea.center` si `expectedFrame == .zero` ET `state.frame` est offscreen. ~10 LOC.
- **V2.3** (fix FR-008, 1h) : si l'investigation révèle que `setLeafVisible(wid, true)` retourne `false` (leaf manquant), corriger l'insertion manquante dans le tree au moment de `stage.switch` ou via un `tree.insertIfMissing()` idempotent.

**Critère d'abandon time-box** : si à 3h on n'a pas de fix qui passe le test acceptance scenario 2, → **option fallback** : appliquer le revert du commit 914b98e (`empty-click hide active stage`). Mieux vaut une feature retirée qu'un bug récurrent.

**Sortie** : 1 commit `fix(BUG-001)` ou `revert(empty-click)`. Test acceptance scenario 2 passe.

### Vague 3 — `roadie heal` + docs (0,5 jour)

Adresse US4, US3 (notification).

- **V3.1** (FR-005) : handler `daemon.heal` dans CommandRouter. Orchestre purge + rebuild + applyLayout + integrity check. Retourne JSON `{drifts_fixed, wids_restored, zombies_purged, duration_ms}`.
- **V3.2** : sous-commande `roadie heal` dans `Sources/roadie/main.swift`. Affiche le récap formaté + exit 0 idempotent.
- **V3.3** (FR-013) : Test shell `Tests/25-heal-command.sh`.
- **V3.4** : Notification terminal-notifier au boot si `state_health.verdict != healthy` (US3 acceptance 1).
- **V3.5** (FR-012) : Section "Troubleshooting" dans README.md + README.fr.md. ~30 lignes.

**Sortie** : 1 commit `feat(heal)`, test passe.

### Vague 4 — Soak + merge (24h)

- **V4.1** : Daily-drive sur la branche `025-stabilization-boot-robustness` pendant 24h sans nouvelle modification.
- **V4.2** : Si pas d'incident → merge dans `main` + push.
- **V4.3** : Tag `v0.2.0-stabilization` pour marquer le baseline stable.

## Complexity Tracking

> **Rempli ONLY si Constitution Check a des violations à justifier**

| Violation | Pourquoi nécessaire | Alternative simple rejetée parce que |
|-----------|---------------------|--------------------------------------|
| Delta LOC +310 dépasse plafond +200 du plan initial | US7 (`roadie diag`) ajoutée en cours de session à la demande utilisateur (besoin produit : bundle structuré pour bug report par utilisateurs tiers). Coût ~200 LOC (collecteur de fichiers + tar + helpers). Sans US7, delta = +110 (sous cible). | Reporter US7 dans une SPEC-026 dédiée aurait dupliqué le ceremonial spec/plan/tasks et fragmenté un sprint cohérent (US7 complémentaire de US3 health metric et US4 heal command — diagnostic forme un tout). |

## Implementation summary (post-merge)

| Composant | Statut | Notes |
|---|---|---|
| Vague 0 quick wins (T001-T003) | ✅ Implemented | Default `empty_click_hide_active=false`, GC `.legacy.*` install-dev |
| Vague 1 boot robustness (T010-T063) | ✅ Implemented | `Stage.validateMembers`, auto-fix au boot, `BootStateHealth`, `daemon.health`, GC runtime |
| Vague 2 BUG-001 fix (T070-T076) | ✅ Implemented (FR-007 partial) | `HideStrategyImpl.show()` fallback safe + log `setLeafVisible_no_leaf_found`. FR-008 tree leaf insertion idempotente reportée si bug réapparaît |
| Vague 3 heal + docs (T090-T122) | ✅ Implemented | `daemon.heal`, `roadie heal`, notification health, README Troubleshooting EN+FR |
| US7 `roadie diag` (FR-016) | ✅ Implemented (ajoutée en cours) | Bundle tarball avec logs, config, stages, system-info |
| Vague 4 soak + tag (T130-T135) | ⏭ DEFER | Wall-clock 24h, action manuelle utilisateur post-merge |

## Audit fixes appliqués (commit 936bdf3)

| ID | Fix |
|---|---|
| L3 quality | `@MainActor` ajouté sur `StageManager.lastValidationInvalidatedCount` (data race théorique Swift 6 strict) |
| L4 robustness | Check `tarProc.terminationStatus == 0` dans `roadie diag` (silent corruption potentielle si tar échoue) |
