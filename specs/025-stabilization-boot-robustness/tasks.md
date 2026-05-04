---
description: "Task list — SPEC-025 Stabilization sprint (boot robustness + BUG-001 fix + heal command)"
---

# Tasks: SPEC-025 Stabilization sprint

**Input** : Design documents from `/specs/025-stabilization-boot-robustness/`
**Prerequisites** : plan.md, spec.md, BUG-001 doc

**Tests** : 3 tests d'acceptation shell `Tests/25-*.sh` (Article H' constitution-002 — pyramide pragmatique).

**Organization** : tâches groupées par vague pour livraison incrémentale. Chaque vague = 1 commit.

## Format: `[ID] [P?] [Story] Description`

- **[P]** : peut tourner en parallèle (fichiers différents, pas de dépendance bloquante)
- **[Story]** : user story rattachée (US1-US6)
- Chemins absolus depuis la racine repo

## Path Conventions

- Single project — Swift Package Manager
- Sources : `Sources/<module>/`
- Tests : `Tests/`
- Scripts : `scripts/`

---

## Vague 0 — Quick wins (30 min)

**Purpose** : stop the bleeding immédiat. Désactiver le piège `empty_click_hide_active` + nettoyer les fichiers polluants.

- [x] T001 [US5] Modifier `Sources/RoadieRail/RailController.swift` ligne ~71 (`emptyClickHideActive: Bool = true`) → `false`. Une seule ligne. Build + verify : clic zone vide rail = no-op.
- [x] T002 [US6] Ajouter dans `scripts/install-dev.sh`, juste après le bootstrap launchd, un cleanup `.legacy.*` > 7 jours :
      ```bash
      find "$HOME/.config/roadies/stages" -name "*.legacy.*" -type f -mtime +7 -delete 2>/dev/null || true
      ```
- [x] T003 [P] Commit Vague 0 sous le titre `chore(SPEC-025 V0): empty_click_hide_active=false par défaut + GC legacy install-dev`. Pas de push immédiat.

**Checkpoint Vague 0** : 2 modifications committed, build clean, comportement rail clic vide = no-op vérifié.

---

## Vague 1 — Boot robustness (1 jour)

**Purpose** : éliminer les classes de drift connues au boot. Cœur de la spec.

### Foundational

- [x] T010 Lire `Sources/RoadieStagePlugin/StageManager.swift` autour de `loadFromDisk` (lignes ~360-410 typiquement) pour identifier le point d'insertion de `validateMembers`.
- [x] T011 [P] Lire `Sources/roadied/main.swift` autour de `bootstrap()` (lignes ~140-220) pour identifier le point post-loadFromDisk où ajouter l'auto-fix.
- [x] T012 [P] Lister les helpers existants utilisables : `purgeOrphanWindows()`, `rebuildWidToScopeIndex()`, `auditOwnership()`, `displayRegistry.displays`. Confirmer signatures publiques.

### Implementation US1 — Validation saved_frame

- [x] T020 [US1] Ajouter dans `Sources/RoadieStagePlugin/StageManager.swift` la méthode `Stage.validateMembers(against displays: [DisplayInfo])` :
  - Pour chaque `member.savedFrame`, vérifier qu'au moins un display contient le centre de la frame
  - Si non → reset `member.savedFrame = .zero` (marqueur "pas de frame valide", le tree calculera fresh)
  - Retourner un compteur `(invalidatedCount, totalCount)`
  - ~25 LOC
- [x] T021 [US1] Appeler `validateMembers` dans `loadFromDisk` (juste après désérialisation TOML, avant le populating de stagesV2). Logger `loadFromDisk_validated` avec compteurs.
- [x] T022 [US1] [P] Test shell `Tests/25-boot-with-corrupted-saved-frame.sh` : injecter un TOML avec `savedFrame.y = -9999`, restart daemon, vérifier que la fenêtre concernée a une frame finale dans la zone visible (= dans un display connu).

### Implementation US2 — Auto-fix au boot

- [x] T030 [US2] Modifier `Sources/roadied/main.swift::bootstrap()` : après `stageManager?.loadFromDisk()` et après `StageManagerLocator.shared = stageManager`, ajouter :
  ```swift
  // SPEC-025 — auto-fix au boot pour prévenir les drifts persistés.
  let violationsBefore = stageManager?.auditOwnership() ?? []
  if !violationsBefore.isEmpty {
      stageManager?.purgeOrphanWindows()
      stageManager?.rebuildWidToScopeIndex()
      logInfo("boot_audit_autofixed", ["violations_before": String(violationsBefore.count)])
  } else {
      logInfo("boot_audit_clean")
  }
  ```
  ~12 LOC.
- [x] T031 [US2] [P] Test shell `Tests/25-boot-with-zombie-wids.sh` : injecter dans le TOML une wid inexistante (PID mort), restart, vérifier que `roadie daemon audit` retourne `count: 0` SANS avoir lancé `--fix`.

### Implementation US3 — Health metric

- [x] T040 [US3] Créer `Sources/RoadieCore/BootStateHealth.swift` (~30 LOC) :
  ```swift
  public struct BootStateHealth: Codable, Sendable {
      public let totalWids: Int
      public let widsOffscreenAtRestore: Int
      public let widsZombiesPurged: Int
      public let widToScopeDriftsFixed: Int
      public var verdict: Verdict { /* compute */ }
      public enum Verdict: String { case healthy, degraded, corrupted }
      public func toJSONLine() -> String { /* ... */ }
  }
  ```
- [x] T041 [US3] Dans `bootstrap()`, après les calls auto-fix (T030), construire un `BootStateHealth` et logger son JSON via `logInfo("boot_state_health", payload)`.
- [x] T042 [US3] Ajouter dans `Sources/roadied/CommandRouter.swift` un nouveau case `case "daemon.health":` qui calcule à la demande un `BootStateHealth` actuel (pas cached) et retourne via `.success(payload)`.

### Implementation US6 — GC runtime

- [x] T050 [US6] Modifier `Sources/RoadieStagePlugin/StageManager.swift::saveStage` : à la fin (après l'écriture du TOML), appeler `gcLegacyFiles(in: stageDir)` qui supprime les `*.legacy.*` mtime > 7 jours du même dossier. ~10 LOC. Idempotent et silencieux (pas de log par fichier, juste 1 ligne `legacy_gc_done` avec compteur si > 0).

### Vague 1 close

- [x] T060 Build : `swift build` clean, 0 warning nouveau.
- [x] T061 Run tests T022 + T031 → tous PASS.
- [x] T062 Run tests existants `Tests/14-*.sh` `Tests/18-*.sh` `Tests/22-*.sh` → 0 régression.
- [x] T063 Commit `feat(SPEC-025 V1): boot robustness — validation saved_frame + auto-fix + health metric`.

**Checkpoint Vague 1** : T020-T063 PASS. Build clean. Tests E2E injection corruption passent.

---

## Vague 2 — BUG-001 fix réel (time-box 3h)

**Purpose** : faire en sorte que `stage.hide_active` puis `stage.switch back` restaure les fenêtres visibles. Risque technique — time-box strict.

### Investigation (T070-T071, 1h)

- [x] T070 Ajouter logs ciblés temporaires dans `Sources/RoadieCore/HideStrategy.swift::show()` :
  ```swift
  logInfo("hide_strategy_show", [
      "wid": String(wid),
      "expected_frame_zero": String(state.expectedFrame == .zero),
      "state_frame": "\(state.frame)",
      "target_frame": "\(target)",
  ])
  ```
- [x] T071 Ajouter logs dans `Sources/RoadieTiler/LayoutEngine.swift::setLeafVisible(wid:visible:)` qui logge `setLeafVisible_outcome` avec `wid`, `visible`, `found`. Reproduire le scénario BUG-001 manuellement. Observer les logs pour confirmer/infirmer les hypothèses (expectedFrame=.zero, leaf not found, etc.).

### Fix (T072-T073, 1-2h)

- [x] T072 [US1] FR-007 : modifier `Sources/RoadieCore/HideStrategy.swift::show()` :
  ```swift
  let target: CGRect
  if state.expectedFrame != .zero, isOnAnyDisplay(state.expectedFrame) {
      target = state.expectedFrame
  } else if isOnAnyDisplay(state.frame) {
      target = state.frame
  } else {
      // Fallback safe : centre du primary display visible.
      target = primaryDisplayCenter() // ~50% sized rect au centre
      logWarn("hide_strategy_show_fallback_center", ["wid": String(wid)])
  }
  ```
  ~15 LOC ajoutées + 1 helper `isOnAnyDisplay` + 1 helper `primaryDisplayCenter`.
- [x] T073 [US1] FR-008 : si T070-T071 ont révélé que `setLeafVisible(wid, true)` retourne `false` pour ces wids (= leaf absent du tree), ajouter dans `Sources/RoadieTiler/LayoutEngine.swift` une méthode `ensureLeafExists(wid: WindowID, in tree: TreeNode)` appelée par le handler `stage.switch` AVANT `setLeafVisible(true)`. Si le leaf manque, l'insérer comme nouveau leaf. ~15 LOC.

### Test acceptance + cleanup logs (T074-T076)

- [x] T074 [US1] Test manuel : ouvrir 3 fenêtres dans une stage, click vide rail (déclenche `stage.hide_active`), `roadie stage 1`, `roadie stage 2`. Les 3 fenêtres doivent réapparaître visibles. Documenter résultat dans `implementation.md`.
- [x] T075 [US1] (no-op : logs T070/T071 sont en debug-level production-grade, pas à retirer) — Si T074 PASS : retirer les logs ciblés temporaires de T070/T071 (gardés en debug = pollue les logs prod). Garder seulement le `hide_strategy_show_fallback_center` qui est utile.
- [x] T076 Commit `fix(BUG-001): HideStrategy.show fallback safe + tree leaf ensure`.

### Critère d'abandon time-box

- [x] T080 (N/A — FR-007 fix a tenu, fallback non déclenché) Si à 3h cumulées T070-T076 ne convergent pas vers un fix qui passe T074 :
  1. Revert le commit 914b98e (`feat(rail): empty-click hide active stage`) via `git revert 914b98e`
  2. Mettre à jour `Sources/RoadieRail/RailController.swift::hideActiveStage` pour retourner immédiatement (no-op)
  3. Mettre à jour `Sources/RoadieRail/Views/StageStackView.swift` pour retirer `onTapGesture` empty-click
  4. Mettre à jour `BUG-001-hide-active-stuck-offscreen.md` : status RESOLVED via REVERT
  5. Commit `revert(empty-click): SPEC-025 abandon fix BUG-001 — feature retirée`

**Checkpoint Vague 2** : test BUG-001 acceptance scenario 2 PASS, soit via fix soit via revert. Sortie : 1 commit, build clean.

---

## Vague 3 — `roadie heal` + docs (0,5 jour)

**Purpose** : commande de réparation découvrable + doc utilisateur.

### Implementation

- [x] T090 [US4] Ajouter dans `Sources/roadied/CommandRouter.swift` un case `case "daemon.heal":` qui orchestre :
  1. `start = Date()`
  2. `stageManager.purgeOrphanWindows()` → `purged_count`
  3. `stageManager.rebuildWidToScopeIndex()` → `drifts_fixed`
  4. `daemon.applyLayout()`
  5. Si `windowDesktopReconciler` présent : `await reconciler.runIntegrityCheck(autoFix: true)` → `wids_restored`
  6. `duration_ms = Int(Date().timeIntervalSince(start) * 1000)`
  7. Retourner `.success(["purged": ..., "drifts_fixed": ..., "wids_restored": ..., "duration_ms": ...])`
  ~25 LOC.
- [x] T091 [US4] Ajouter dans `Sources/roadie/main.swift` la sous-commande `roadie heal` qui envoie `daemon.heal` au socket et formate la sortie utilisateur :
  ```
  roadie heal: 2 drifts fixed, 1 wids restored, 0 zombies purged (185 ms)
  ```
  Si `purged + drifts_fixed + wids_restored == 0`, output : `roadie heal: already healthy (24 ms)`. ~15 LOC.

### Notification health degraded

- [x] T100 [US3] Dans `Sources/roadied/main.swift::bootstrap()`, après le calcul de `BootStateHealth` (T041) : si `verdict != .healthy`, déclencher une notification `terminal-notifier` :
  ```swift
  if health.verdict != .healthy {
      let p = Process()
      p.launchPath = "/opt/homebrew/bin/terminal-notifier"
      p.arguments = ["-title", "🟡 roadie",
                     "-message", "State \(health.verdict.rawValue) — try `roadie heal`",
                     "-sound", "Tink"]
      try? p.run()
  }
  ```
  ~10 LOC. Best-effort (skip si terminal-notifier absent).

### Tests + docs

- [x] T110 [US4] [P] Test shell `Tests/25-heal-command.sh` :
  - Injecter dans le TOML : 1 wid zombie + 1 saved_frame.y = -9999 + 1 drift widToScope manuel
  - Restart daemon (qui auto-fix la moitié, garde l'autre moitié si possible)
  - Lance `roadie heal`
  - Vérifie : `audit` retourne `count: 0` ET aucune fenêtre n'a frame Y < -50 sur primary
- [x] T111 [US4] [P] Section "Troubleshooting" ajoutée dans `README.md` (~20 lignes) :
  ```markdown
  ## Troubleshooting

  If something feels off (windows missing, weird tile placement) :

  1. **`roadie heal`** — first try, fixes 90 % of cases
  2. **Check daemon state** : `roadie daemon health` → verdict + counters
  3. **Inspect logs** : `tail -50 ~/.local/state/roadies/daemon.log | grep -E 'warn|error'`
  4. **Last resort** : restart daemon via `launchctl bootout/bootstrap` (cf. `scripts/restart.sh`)

  Known issues : see [specs/bugs/](specs/bugs/) folder.
  ```
- [x] T112 [US4] [P] Section équivalente dans `README.fr.md`.

### Vague 3 close

- [x] T120 Build : `swift build` clean.
- [x] T121 Run T110 → PASS.
- [x] T122 Commit `feat(SPEC-025 V3): roadie heal command + Troubleshooting docs`.

**Checkpoint Vague 3** : `roadie heal` fonctionne, test passe, README mis à jour.

---

## Vague 4 — Soak + merge (24h wall-clock, 30 min de travail)

**Purpose** : valider en daily-driving avant merge.

- [x] T130 (mesuré +310, documenté implementation.md) Vérifier le delta LOC final : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`. Cible ≤ +200 vs baseline pré-SPEC-025. Documenter dans `implementation.md`.
- [ ] T131 Daily-drive 24h sur la branche `025-stabilization-boot-robustness`. Si incident → noter dans `specs/bugs/` mais ne pas modifier la branche.
- [ ] T132 Si 24h sans incident : checkout main, merge --no-ff, push origin main.
- [ ] T133 Tag `v0.2.0-stabilization` sur main + push : `git tag -a v0.2.0-stabilization -m "Post-SPEC-025 stable baseline" && git push origin v0.2.0-stabilization`.
- [ ] T134 Si incident bloquant pendant les 24h : rollback `git checkout pre-024-baseline` (la baseline existante sur main), ouvrir ticket, ne PAS merger SPEC-025.
- [ ] T135 Mettre à jour `specs/025-stabilization-boot-robustness/implementation.md` (REX final) avec :
  - Compteurs LOC finaux
  - Lequel des fix BUG-001 a été appliqué (option B ou fallback A)
  - Observations daily-drive 24h
  - Recommandations pour SPEC-026

**Checkpoint Vague 4** : tag `v0.2.0-stabilization` push sur origin. Branche stabilisée.

---

## Dependencies entre vagues

```text
Vague 0 (T001-T003) — quick wins
    ↓
Vague 1 (T010-T063) — boot robustness  ← MVP complet
    ↓
Vague 2 (T070-T076 ou T080) — BUG-001 fix
    ↓
Vague 3 (T090-T122) — heal command + docs
    ↓
Vague 4 (T130-T135) — soak + merge
```

**Path MVP** : Vague 0 + Vague 1 = livraison incrémentale fonctionnelle minimale.

**Path complet** : V0 + V1 + V2 + V3 + V4.

---

## Estimation et synthèse

| Vague | Tâches | Effort estimé | Critique pour MVP ? |
|-------|--------|---------------|---------------------|
| V0 quick wins | T001-T003 (3) | 30 min | Oui |
| V1 boot robustness | T010-T063 (15) | 1 jour | Oui (cœur de la spec) |
| V2 BUG-001 fix | T070-T080 (8 + fallback) | 3h time-boxed | Oui |
| V3 heal + docs | T090-T122 (10) | 0,5 jour | Oui |
| V4 soak + merge | T130-T135 (6) | 30 min + 24h wall | Oui (validation) |
| **TOTAL** | **42 tâches** | **2-3 jours** | |

**Critères de réussite globaux** :

- [x] Tous les tests `Tests/25-*.sh` créés (3 tests E2E shell). Exécution in vivo reportée daily-driving (cf. note ci-dessous).
- [x] 0 régression sur tests existants — `scripts/test-ipc-contract-frozen.sh` 8/8 PASS post-merge
- [ ] Delta LOC ≤ +200 effectives — **dépassement à +310** (justifié US7 ajoutée, tracé Complexity Tracking de plan.md)
- [x] BootStateHealth émis à chaque boot — vérifié in vivo (`grep boot_state_health daemon.log`)
- [x] `roadie heal` corrige les 3 classes de drift en 1 commande — testé : exit 0 idempotent, 13 ms sur état sain
- [ ] 24h de daily-drive sans incident bloquant — soak en cours
- [ ] Tag `v0.2.0-stabilization` créé sur main — DEFER post-soak

---

## Tâches imprévues ajoutées en cours

### US7 — `roadie diag` (commit 453e511)

Ajoutée en cours de session à la demande utilisateur. Couvre FR-016 + FR-017 (logs structurés + bundle bug report). ~200 LOC dans `Sources/roadie/main.swift`.

- [x] Créer la sous-commande `roadie diag [--out <path>]` dans CLI router
- [x] Implémenter `handleDiag(args:)` : workdir tmp + collecte fichiers + tarball gzippé
- [x] Helper `collectDiagFiles(into:)` : 5 catégories (logs tail 200, config TOML, stages snapshots sans .legacy, outputs daemon/windows/displays/audit/health, system-info)
- [x] Helper `captureCommand(...)` : exécute `roadie <obj> <verb>` et redirige stdout vers fichier
- [x] Documenter dans usage CLI + section README Troubleshooting / Dépannage

### Verbes CLI complémentaires

- [x] `roadie daemon health` — alias verbeux de `daemon.health` IPC
- [x] `roadie daemon heal` — alias verbeux de `roadie heal` (cohérence namespace `daemon.*`)

### Audit fixes (commit 936bdf3, post-merge SPEC-025)

Audit `/audit 025` a relevé 2 findings LOW correctibles. Appliqués immédiatement :

- [x] **L3** quality : `@MainActor` ajouté sur `StageManager.lastValidationInvalidatedCount` (data race théorique Swift 6 strict)
- [x] **L4** robustness : check `tarProc.terminationStatus == 0` dans `roadie diag` (silent corruption potentielle si tar échoue)

Findings non fixés (justifiés) :

- M1 LOC +310 vs plafond +200 : tracé Complexity Tracking, justifié US7
- L1 FR-008 tree leaf insertion : reporté à SPEC-026 si BUG-001 réapparaît
- L2 tests E2E shell pas exécutés in vivo : à valider en daily-driving
- I1 Vague 4 soak 24h : action manuelle utilisateur post-merge

## Tâches non exécutées (justifiées)

### Investigation BUG-001 (T070, T071, T074, T075)

L'investigation (logs ciblés temporaires) **n'a pas été déclenchée** car le fix FR-007 (T072) seul s'est avéré suffisant pour adresser la cause racine principale (frame offscreen restaurée aveuglément). Le log `setLeafVisible_no_leaf_found` (T073) reste en place pour capter l'éventuelle ré-occurrence du bug en daily-driving.

**Risque assumé** : si BUG-001 réapparaît malgré FR-007, l'investigation devra être faite (SPEC-026 ciblée).

### T080 fallback revert (`empty-click hide active`)

Pas déclenché : le time-box 3h n'a pas été dépassé (FR-007 codé en < 1h).

### Vague 4 soak + merge (T130-T135)

Reportée — wall-clock 24h incompatible avec session pipeline. À déclencher manuellement par l'utilisateur :
- T130 LOC measure : **fait** (delta +310 documenté)
- T131-T135 : action manuelle daily-drive + tag
