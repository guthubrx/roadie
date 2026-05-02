# Scoring final — Audit SPEC-011 Roadie Virtual Desktops

**Session** : `session-2026-05-02-spec-011-01`
**Périmètre** : SPEC-011 (Sources/RoadieDesktops/, Tests/RoadieDesktopsTests/, intégrations daemon)
**Mode** : `fix` (1 cycle de corrections + 1 cycle scoring lecture seule)
**Date** : 2026-05-02

## Verdict global

**Note : A**

Toutes les gates de la constitution passent, tous les tests sont verts, les findings du cycle reviewer ont été corrigés.

## Tableau de notes

| Axe | Note | Détail |
|---|---|---|
| **Robustesse** | A | Fail-loud : `try?` muets remplacés par log warn ; range checks 1..count ; corruption recovery (FR-013) ; cgwid disparus ignorés (FR-024) ; `unknownDesktop` propagé sur registry. |
| **Concurrence** | A | Acteurs Swift stricts (`DesktopRegistry`, `DesktopSwitcher`, `DesktopEventBus`, `AXWindowMover`). Pas de data race. Sérialisation des bascules via state machine `inFlight + pendingTarget`. Cleanup continuations corrigé (yieldResult.dropped). |
| **Sécurité** | A | 0 import SkyLight/CGS/SLS dans `Sources/RoadieDesktops/` (validé par `Tests/StaticChecks/no-cgs.sh`). Pas de secret en dur. Pas d'injection (sérialisation TOMLKit + escape contrôles). Permissions AX uniquement (déjà demandées V1). |
| **Performance** | A | Bascule perçue instantanée (PerfTests passe < 200 ms p95 sur 10 fenêtres). EventBus latence < 50 ms (test dédié). Cache AX avec invalidation explicite (pas de TTL inutile). |
| **Conformité spec** | A | 25/25 FRs implémentés ; 7/7 user stories couvertes ; 10/10 SCs vérifiables ; idempotence et back-and-forth conformes. |
| **Lisibilité** | A | Naming explicite (`DesktopSwitcher`, `RoadieDesktop`, `setLeafVisible`). Modules monorôles. 0 code mort post-suppression SPEC-003. Documentation inline pour FR-025. |
| **Tests** | A | 168 tests verts, 0 échec. Couverture explicite : Smoke, Parser, EventBus, Registry, Switcher, Perf, Ghost, Label, Migration, EventStream, Disabled, Persistence, CorruptionRecovery + 7 stage scope tests + 6 config tests. |
| **Constitution** | A | Principe A (Suckless), B (0 dep ajoutée), C (CGWindowID partout), D (fail loud), E (TOML texte plat), F (justifié dans Complexity Tracking), G (LOC 751 effectives, plafond 900). |

## Gates de la constitution (vérifications mécaniques)

- [x] **0 dépendance tierce ajoutée** : SwiftPM utilisé pour le build, TOMLKit déjà présent (cohérent existant).
- [x] **Pas de `(bundleID, title)` comme clé primaire** : `CGWindowID` partout (`WindowEntry.cgwid`, `Stage.windows: [CGWindowID]`).
- [x] **Toute action sur fenêtre traçable à un `CGWindowID`** : `WindowMover.move(_ cgwid:)`, registry indexé par cgwid.
- [x] **Binaire `roadied` < 5 MB** : 2.19 MB en release.
- [x] **Cible et plafond LOC déclarés dans plan.md** : 700 / 900. Actuel : 751 LOC effectives ✓
- [x] **0 violation Constitution Check non justifiée** : extension CLI à 5 sous-commandes formellement justifiée dans Complexity Tracking de plan.md.

## Métriques

- **LOC effectives `Sources/RoadieDesktops/`** : 751 (sous plafond 900)
- **LOC totales** : 1085
- **Fichiers source** : 10 (Module, DesktopState, Parser, EventBus, WindowMover, DesktopRegistry, DesktopSwitcher, Selector, Validation, Migration)
- **Fichiers tests** : 13 (Smoke, Parser, EventBus, DesktopRegistry, DesktopSwitcher, Perf, Ghost, Label, Migration, EventStream, Disabled, Persistence, CorruptionRecovery)
- **Build status** : `roadied` ✓, `roadie` ✓
- **Test results** : 168 / 168 PASS

## Cycle 1 — Findings corrigés

| ID | Sévérité | Description | Statut |
|---|---|---|---|
| C1 | CRITICAL | EventBus.swift Sendable violation Swift 6 strict | FIXED |
| H1 | HIGH | DesktopSwitcher `try?` saveCurrentID silencieux | FIXED (do/catch + logWarn) |
| H2 | HIGH | DesktopRegistry parent dir race | FIXED (createDirectory dans init) |
| H3 | HIGH | Migration desktopsDir parent absent | FIXED (createDirectory + propagation) |
| H4 | HIGH | WindowMover cache sans invalidation | FIXED (méthode `invalidate()` + doc) |
| M1 | MEDIUM | EventBus yield() failures ignorés | FIXED (YieldResult.dropped tracking) |
| M2 | MEDIUM | DesktopRegistry silencieux sur ID inconnu | FIXED (throw `unknownDesktop`) |
| M3 | MEDIUM | Parser TOML escape incomplet | FIXED (escape \n\t\r\0\b\f) |
| M4 | MEDIUM | DesktopSwitcher pendingTarget non documenté | FIXED (doc-comment FR-025) |
| M5 | MEDIUM | StageManager extractDesktopUUID retourne "" | FIXED (renommé extractDesktopID, retourne `nil` mode V1) |

## Cycle scoring (lecture seule)

Aucun finding nouveau détecté. État stable, prêt à committer.

## Forces du module

1. **Pivot architectural propre** : suppression complète du legacy SPEC-003 (~600 LOC), remplacement par module isolé `RoadieDesktops` (751 LOC), aucune dette résiduelle.
2. **Concurrence Swift 6 idiomatique** : actors partout, AsyncStream pour le bus, queue collapsing testée.
3. **Documentation traçable** : chaque FR/SC cité dans le code et les tests, contrats CLI/events séparés, research.md justifie les choix.

## Axes d'amélioration différés (V2.1 / V3)

- **Métriques runtime** : exposer un compteur de bascules réussies/échouées via `daemon.status` pour observabilité externe.
- **Test E2E live** : ajouter un harness qui spawn le daemon et exerce `roadie desktop focus N` sur un Mac réel avec X fenêtres factices (gating CI macOS uniquement).
- **TTL cache AX** : si on observe en prod des fenêtres orphelines après crash app, ajouter un balayage périodique du cache AX (out-of-scope V2).
- **Bench LOC vs cible** : on est à 751 / cible 700. Refactor possible sur Parser.swift (125 LOC) pour utiliser plus profondément TOMLKit's encoding.
