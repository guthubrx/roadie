# Audit Scoring — SPEC-002 Tiler + Stage Manager

**Date** : 2026-05-01
**Mode** : autonome (pas d'utilisateur en ligne pour test runtime)
**Périmètre** : SPEC-002 (binaires roadied + roadie + 3 modules + tests)

---

## Tableau de notes

| Dimension | Note | Justification |
|---|---|---|
| **Build & Compilation** | A | `swift build` et `swift build -c release` réussissent ; `swift test` 32 PASS / 0 échec |
| **Architecture** | A | 4 modules clairement séparés (Core, Tiler, StagePlugin, CLI), Tiler en protocole avec 2 implémentations (BSP + Master-Stack), StagePlugin authentiquement opt-in |
| **Coverage requirements** | B+ | 19/23 FR implémentés, 4 FR avec implémentation partielle (FR-006 snapshot apps existantes : présent mais à valider live ; FR-021 daemon-not-running : présent ; FR-018 hide-strategy hybride : implémenté mais non testé) |
| **Performance** | C | **Non mesurée en runtime** : le daemon n'a pas pu être démarré dans cette session (pas de session graphique active + besoin d'autorisation Accessibility manuelle). SC-001 à SC-003 latences à valider lors du premier run user. |
| **Test coverage** | B | 32 tests unitaires PASS sur Core+Tiler+StagePlugin. Tests d'intégration shell scripts NON ÉCRITS (Tâches T029, T041, T051, T054, T060). À prioriser au prochain passage. |
| **LOC effectives** | A | 2009 < 4000 cible (SC-006). Marge confortable pour ajouter intégration tests + finitions sans dépasser. |
| **Empreinte daemon** | A | 1.6 MB (cible < 5 MB) |
| **Empreinte CLI** | C | **1.4 MB (cible < 500 KB)** — dépassement dû à TOMLKit lié via RoadieCore. À refactorer en V2 (extraire Config en module séparé sans CLI dependency) |
| **Documentation** | A | spec.md, plan.md, research.md (820 lignes), data-model.md, contracts/, quickstart.md, 3 ADRs, constitution-002.md, tasks.md, implementation.md tous écrits |
| **Conformité Constitution** | A | Articles globaux (français, SpecKit, ADRs) et constitution-002 respectés. Justifications claires des écarts (multi-fichier, TOMLKit). |
| **Click-to-focus différenciateur** | B | Implémentation présente (`kAXApplicationActivatedNotification` câblé dans `axDidActivateApplication`), MAIS non testé empiriquement faute d'environnement live. À valider au premier run. |

## Note globale : **B+**

Justification : qualité d'ingénierie élevée (code propre, tests unitaires complets, build reproductible, architecture modulaire correcte) **mais** non testé en runtime (impossible sans session utilisateur active). Le passage de B+ à A nécessitera :
1. Validation runtime du daemon (premier `roadied --daemon` et observations).
2. Refactor Config pour libérer le CLI de TOMLKit.
3. Tests d'intégration shell réels.

---

## Findings cycle 1

| ID | Sévérité | Catégorie | Description | Statut |
|---|---|---|---|---|
| F1 | HIGH | size | Binaire CLI 1.4 MB (cible < 500 KB) à cause de TOMLKit lié via RoadieCore | DOCUMENTÉ V2 |
| F2 | MEDIUM | testing | Aucun test d'intégration shell exécuté | DOCUMENTÉ T029/T041/T051/T054/T060 reportés |
| F3 | MEDIUM | runtime | Daemon non démarré ; click-to-focus + tiling non validés empiriquement | NORMAL — attente session user |
| F4 | LOW | warnings | 6 warnings `'as' test is always true` dans AXEventLoop.swift sur les comparaisons `kAX...Notification as String` | À NETTOYER (cosmetic) |
| F5 | LOW | code | `BSPTiler.move` ne traite pas le cas multi-niveau quand le voisin direct n'existe pas (algo simplifié V1) | DOCUMENTÉ — fonctionnel pour cas simples |
| F6 | INFO | features manquantes | Tâches T067 (snapshot ordered by kCGWindowLayer), T068 (subrole exclusion popups), T066 (KnownBundleIds) implémentées partiellement seulement | DOCUMENTÉ tasks.md |

## Gates SpecKit

| Gate | Statut |
|---|---|
| Constitution globale (Articles I-IX) | PASS |
| Constitution projet 002 (Principes A'-H) | PASS |
| Build clean | PASS |
| Tests unitaires | PASS (32/32) |
| Coverage requirements (FR) | PARTIEL — 19/23 |
| Coverage SC chiffrés | NON MESURÉ runtime |
| LOC < 4000 | PASS (2009) |
| Daemon < 5 MB | PASS (1.6 MB) |
| CLI < 500 KB | **FAIL** (1.4 MB) |
| 0 dépendance non système au runtime | TOMLKit lié statiquement → vérifier `otool` après refactor |

**Verdict** : ✅ Build correct + tests unitaires OK. Validation runtime à faire au prochain passage utilisateur. Non bloquant pour la mise en main.
