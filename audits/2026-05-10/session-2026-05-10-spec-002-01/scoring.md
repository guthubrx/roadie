# Audit Code v13 — SPEC-002 (Roadie Ecosystem Upgrade)

**Date** : 2026-05-10
**Session** : `session-2026-05-10-spec-002-01`
**Mode** : `fix` (audit + corrections)
**Cycles** : 2 fix + 1 scoring (sur MAX_CYCLES=5 demandés, arrêt précoce car nettoyage complet en cycle 1)
**Périmètre** : 31 fichiers Sources touchés par SPEC-002, ~4 134 LOC critiques

---

## Note globale : **A**

| Domaine                              | Note  |
|--------------------------------------|-------|
| Sécurité (OWASP, secrets, regex DoS) | **A** |
| Complexité algorithmique (Art. XVIII)| **A** |
| Qualité de code                      | **A-**|
| Tests                                | **A** |
| Performance                          | **A** |
| Robustesse (FS, concurrence)         | **A** |
| Duplication                          | **A** |

---

## Synthèse exécutive

SPEC-002 livre un écosystème d'automation (events, rules, groups, query API, power-user commands) sur la base solide de Roadie. L'audit a identifié **8 findings** au cycle 1 — dont **2 hauts** (anti-patterns Article XVIII dans le hot path snapshot) et **3 moyens** (FileHandle leak, race condition, allocations JSON répétées). Tous les findings actionnables (haute et moyenne sévérité) ont été corrigés en cycle 1. Le cycle 2 confirme l'absence de régression et de nouveaux anti-patterns. La suite de tests (252 tests, dont 61 ciblés SPEC-002) passe à 100 % en 0,12 s.

---

## Findings & Corrections appliquées

### `P1` — Set construit dans hot path `applyTilingPolicy` *(high → fixed)*

`Set(config.tiling.allowedSubroles)` était construit à chaque appel d'`applyTilingPolicy`, lui-même appelé `n_windows` fois par tick via `rawWindows.map`. Anti-pattern **Article XVIII §2** (structure de donnée recompactée en boucle).

- **Fichier** : `Sources/RoadieDaemon/DaemonSnapshot.swift:280`
- **Avant** : O(n_windows × n_subroles) construction Set répétée
- **Après** : O(n_subroles) construction unique via `TilingPolicyContext`
- **Fix** : `TilingPolicyContext` pré-calcule `allowedSubroles` et `floatingBundles` une fois par snapshot. La signature publique `applyTilingPolicy(to:config:)` est préservée (utilisée par 17 tests) et délègue à la nouvelle overload `applyTilingPolicy(to:config:context:)`.

### `P2` — Tri répété des règles par fenêtre *(high → fixed)*

`WindowRuleMatcher.firstMatch(rules:)` faisait `.filter(\.enabled).sorted{...}.first` à chaque appel. Appelé depuis `applyTilingPolicy` pour chaque fenêtre, soit `n_windows × n_rules log n_rules` à chaque tick. Anti-pattern **Article XVIII §2** (tri répété d'une collection invariante).

- **Fichier** : `Sources/RoadieDaemon/WindowRuleMatcher.swift:50`
- **Avant** : O(n_windows × n_rules log n_rules)
- **Après** : O(n_rules log n_rules) hors boucle + O(n_windows × n_rules) matching
- **Fix** : nouvelle overload `firstMatch(sortedRules:window:context:)` qui assume un tableau pré-trié. `TilingPolicyContext.sortedRules` calcule le tri une seule fois. L'API legacy reste publique pour rétro-compatibilité.

### `R1` — `FileHandle` non fermé en cas d'erreur *(medium → fixed)*

Dans `EventLog.write`, le `FileHandle(forWritingTo:)` était ouvert sans `defer { try? handle.close() }`. Si `seekToEnd` ou `write` lancent, le handle reste ouvert jusqu'à la libération ARC.

- **Fichier** : `Sources/RoadieDaemon/EventLog.swift:79`
- **Fix** : `defer { try? handle.close() }` placé immédiatement après l'open.

### `R2` — Race condition `write/rotate` concurrent *(medium → fixed)*

`EventLog` est instancié ~15× dans le daemon (un par service), avec des `append` concurrents (Tasks `@MainActor` + workers). Le pattern `seekToEnd → write(data) → write(newline)` est non-atomique : deux events peuvent s'entrelacer ou la rotation peut couper un event en deux.

- **Fichier** : `Sources/RoadieDaemon/EventLog.swift:64`
- **Fix** : `static let writeLock = NSLock()` partagé entre toutes les instances, pris dans `write()` et `rotateIfNeeded()`. Synchronise les écritures sur le fichier unique `events.jsonl`.

### `P3` — `JSONEncoder/Decoder` alloués par appel *(medium → fixed)*

`JSONEncoder()` / `JSONDecoder()` instanciés dans le hot path : `EventLog.write` (par event), `AutomationQueryService.payload` (par query, polling 5 Hz par les abonnés), `EventSubscriptionService.decodeEnvelope` (par ligne du subscribe).

- **Fichiers** : `EventLog.swift`, `AutomationQueryService.swift`, `EventSubscriptionService.swift`
- **Fix** : `static let encoder/decoder` partagés. JSONEncoder configuré une fois est thread-safe pour des `encode` indépendants.

### Findings différés / informatifs

- **`Q1`** *(low)* — `runEventSubscription` boucle `while true` + `Thread.sleep(0.2)` sans handler SIGTERM personnalisé. Comportement actuel acceptable (CLI, SIGINT par défaut). Différé.
- **`INFO1`** — `WindowRuleEngine.evaluate` construit `RuleEvaluation` pour toutes les règles parcourues. Coût marginal car `n_rules` borné typique < 20. Splittable en fast/slow path si besoin futur.
- **`INFO2`** — Regex utilisateur sans timeout (ReDoS théorique). Surface non publique (config locale = utilisateur s'attaque lui-même). Documentation à enrichir.
- **`INFO3`** — Triple loops `scopes×stages×members` dans `StageStore`. Conformes Article XVIII §3 (commentaires de complexité explicites présents lignes 84, 96, 331, 364, 405).

---

## État build & tests

| Item                          | Statut |
|-------------------------------|--------|
| Build `RoadieCore`            | OK |
| Build `RoadieDaemon`          | OK (warnings deprecated `CGWindowListCreateImage` / `activateIgnoringOtherApps` macOS 14, hors scope SPEC-002) |
| Link exécutables `roadie`/`roadied` | KO via `swift build` natif, OK avec PATH explicite vers Xcode `ld`. Cause : `ld` Anaconda dans le PATH ne supporte pas `-no_warn_duplicate_libraries` injecté par Swift 6.2.3 sous Xcode 26. **Hors scope SPEC-002 — toolchain locale.** |
| Tests SPEC-002 ciblés         | 61/61 OK en 0,07 s |
| Suite complète                | 252/252 OK en 0,12 s |

---

## Conformité Article XVIII (Complexité Algorithmique)

| Pattern scanné                          | Findings | Statut |
|-----------------------------------------|----------|--------|
| Double boucle imbriquée                 | 0        | clean |
| Recherche linéaire dans boucle          | 0        | clean |
| N+1 queries (DB/IO/AX)                  | 0        | clean |
| Tri répété hors boucle                  | 1 (P2)   | **fixed** |
| Set/Dict construit dans boucle          | 1 (P1)   | **fixed** |
| Concat string en boucle                 | 0        | clean |
| I/O dans boucle serrée sans batching    | 0        | clean |
| Récursion non-mémoisée                  | 0        | clean |
| Copie défensive en cascade              | 0        | clean |

**Verdict** : SPEC-002 conforme Article XVIII après cycle 1. Aucun anti-pattern non-justifié restant.

---

## Roadmap recommandée (post-audit)

1. **Hors SPEC-002 — toolchain locale** : retirer `~/anaconda3/bin` du PATH d'execution `swift build` ou repointer vers Xcode `ld`. Ajouter une note dans le README.
2. **Hors SPEC-002 — deprecation macOS 14** : migrer `CGWindowListCreateImage` → `ScreenCaptureKit` et `activateIgnoringOtherApps` → API moderne avant macOS 27.
3. **Refinement INFO1** : si métriques de performance le justifient un jour, splitter `WindowRuleEngine.evaluate` en `fastEvaluate` (sans `evaluations`) et `explainEvaluate` (avec).
4. **Documentation INFO2** : section "config rules" doit suggérer l'usage de regex bornées (`^...$`, pas de `(.*)+`).

---

## Artefacts produits

- `manifest.json` — cartographie du périmètre + threat model
- `cycle-1/aggregated-findings.json` — 8 findings, 5 fixés
- `cycle-2/aggregated-findings.json` — vérification, 0 nouveau finding actionnable
- `cycle-scoring/aggregated-findings.json` — 4 findings résiduels (1 low + 3 info)
- `grade.json` — note globale **A**
- `scoring.md` — ce rapport
