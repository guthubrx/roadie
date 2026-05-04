# Research — SPEC-025 Stabilization sprint

**Phase 0** | Date : 2026-05-04 | Branche : `025-stabilization-boot-robustness`

## R1. Validation `saved_frame` au load — algorithme

### Décision

À `loadFromDisk`, pour chaque `member.savedFrame`, vérifier l'**inclusion du centre** dans au moins un display connu via `displayRegistry.displays`. Si non → reset `savedFrame = .zero`.

### Rationale

- Centre plus robuste qu'origine (une frame partiellement offscreen reste valide si majorité visible)
- `displayRegistry` est l'unique source de vérité des displays connus
- `.zero` est interprété par le tree comme "pas de frame mémorisée" → recalcul fresh au prochain `applyLayout`
- Critère "centre dans display" est utilisé partout dans le code (ex: stage.assign infère le scope display via centre frame)

### Alternatives rejetées

| Alternative | Pourquoi rejetée |
|---|---|
| Seuil Y absolu (Y < -50 ou Y > 5000) | Casse multi-display avec LG au-dessus du Built-in (Y AX négatifs légitimes) |
| Validation à chaque event AX (pas juste au load) | Sur-engineering, coût perf pour cas rare |
| Reset à une frame default au lieu de `.zero` | `.zero` permet au tree de calculer un slot fresh, plus prévisible |

## R2. Auto-fix au boot — point d'insertion

### Décision

Dans `Daemon.bootstrap()`, après `stageManager?.loadFromDisk()` et après `StageManagerLocator.shared = stageManager`, AVANT le premier `applyLayout`. Appel séquentiel `purgeOrphanWindows()` puis `rebuildWidToScopeIndex()`.

### Rationale

- L'ordre `purge → rebuild` est critique : purger d'abord retire les wids zombies de `memberWindows`, puis le rebuild de l'index inverse part d'une source propre
- Avant `applyLayout` : sinon le tree pourrait tenter de positionner des leafs zombies
- Méthodes existantes (livrées par SPEC-021/024), réutilisation pure

## R3. `BootStateHealth` — sérialisation

### Décision

Struct `Codable, Sendable` dans `Sources/RoadieCore/BootStateHealth.swift`. Champs : `totalWids`, `widsOffscreenAtRestore`, `widsZombiesPurged`, `widToScopeDriftsFixed`. Verdict computed property.

```swift
public enum Verdict: String, Codable, Sendable {
    case healthy   // 0 anomalies
    case degraded  // 1-30 % wids touched
    case corrupted // > 30 % wids touched
}
```

Sérialisation via `JSONEncoder` standard (pas de custom). Logger émet via `logInfo("boot_state_health", payload)` où `payload` est un `[String: String]` aplati pour compat `DesktopEvent.payload`.

## R4. BUG-001 — investigation tree leaf manquant

### Hypothèse principale

Quand `stage.hide_active` est appelé, les wids restent dans `memberWindows` mais `LayoutEngine.setLeafVisible(wid, false)` ne touche que le `isVisible` du leaf existant. Au moment du `stage.switch back`, si entre-temps un crash daemon ou un reboot a tourné, le state est rechargé depuis disque mais le **tree** est reconstruit fresh — il n'a peut-être pas (encore) le leaf pour cette wid.

### Vérification empirique

Au moment de l'implementation T070-T071, ajouter logs ciblés :
- Dans `LayoutEngine.setLeafVisible` : log `wid`, `visible`, `found` (= leaf trouvé dans un root)
- Dans `HideStrategyImpl.show` : log `expectedFrame`, `state.frame`, `target` final

Si `setLeafVisible` retourne `false` pour les wids problématiques → confirme tree leaf manquant → fix via `ensureLeafExists` idempotent au moment de `stage.switch`.

Si `setLeafVisible` retourne `true` mais `applyLayout` ne re-tile pas → autre piste (peut-être `applyLayoutInFlight` coalescing).

### Mitigation FR-007 indépendante

Quel que soit le verdict de l'investigation, le fallback safe dans `HideStrategyImpl.show()` (centre primary display si `expectedFrame == .zero` ET `state.frame` offscreen) est sain à mettre. Il garantit qu'aucune fenêtre `show()` ne reste invisible.

## R5. `roadie heal` — orchestration

### Décision

Handler IPC `daemon.heal` dans `CommandRouter` qui appelle séquentiellement :
1. `purgeOrphanWindows()`
2. `rebuildWidToScopeIndex()`
3. `daemon.applyLayout()` (force re-tile)
4. `windowDesktopReconciler.runIntegrityCheck(autoFix: true)` si présent

Retour JSON : `{purged, drifts_fixed, wids_restored, duration_ms}`.

### Rationale

- Orchestration des 4 mécanismes existants (livrés par SPEC-021/022/024)
- Aucune nouvelle logique métier — juste une commande consolidée
- Idempotent par construction (chaque appel sous-jacent l'est déjà)

### Alternatives rejetées

| Alternative | Pourquoi rejetée |
|---|---|
| Implémenter la logique heal côté CLI (Sources/roadie) | Le CLI ne devrait pas dupliquer la logique stages — le daemon est l'unique source de vérité |
| Heal automatique périodique (cron toutes les 5 min) | Sur-engineering. L'auto-fix au boot couvre 90 % des cas. Le reste = action utilisateur explicite. |

## R6. GC `.legacy.*` — heuristique 7 jours

### Décision

Dans `StageManager.saveStage`, après écriture du fichier TOML, supprimer les `*.legacy.*` du même dossier dont `mtime > 7 jours`. Silencieux (1 log avec compteur si > 0).

### Rationale

- 7 jours = fenêtre de "rollback potentiel" en cas de drift catastrophique non détecté
- Trigger au save (= déjà au moment d'une écriture, coût marginal)
- `find -mtime +7 -delete` natif macOS, fiable

## R7. Notification `terminal-notifier` au boot

### Décision

Si `BootStateHealth.verdict != .healthy`, déclencher une notification best-effort. Skip silencieux si `terminal-notifier` absent. Anti-spam : 1 notification max par démarrage (pas de loop).

## R8. Tests E2E shell

### Approche

3 scripts shell `Tests/25-*.sh` qui :
1. Prepare un état artificiellement corrompu (injection TOML, kill process pour wid zombie, etc.)
2. Restart daemon (ou lance heal selon le test)
3. Assert post-état via `roadie windows list` + `roadie daemon audit` parsés

### Rationale

- Pas de XCTest pour ces scénarios end-to-end : XCTest nécessite un setup complexe + une session graphique. Shell suffit.
- Article H' constitution-002 : "test-pyramid réaliste, pas de CI macOS prévue". Aligné.

---

## Sources techniques consultées

- SPEC-021 (single source of truth stage ownership) — pour `auditOwnership`, `widToScope`
- SPEC-024 (monobinary merge) — pour `daemon audit --fix`, `purgeOrphanWindows + rebuildWidToScopeIndex`
- ADR-003 (HideStrategy corner) — pour la stratégie `corner` qui crée les Y=-2117
- BUG-001 (specs/bugs/) — pour la cause racine déjà investiguée

→ Aucune `[NEEDS CLARIFICATION]`. Phase 1 design peut démarrer.
