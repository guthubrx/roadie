# Data Model — SPEC-025

**Phase 1** | Date : 2026-05-04

## Entités runtime introduites ou modifiées

### Nouvelle : `BootStateHealth`

Localisation : `Sources/RoadieCore/BootStateHealth.swift`

```swift
public struct BootStateHealth: Codable, Sendable {
    public let totalWids: Int
    public let widsOffscreenAtRestore: Int   // avant validation FR-001
    public let widsZombiesPurged: Int        // par FR-002
    public let widToScopeDriftsFixed: Int    // par FR-002
    public let timestamp: Date

    public enum Verdict: String, Codable, Sendable {
        case healthy
        case degraded
        case corrupted
    }

    public var verdict: Verdict {
        let touched = widsOffscreenAtRestore + widsZombiesPurged + widToScopeDriftsFixed
        guard totalWids > 0 else { return .healthy }
        let pct = Double(touched) / Double(totalWids)
        if pct == 0 { return .healthy }
        if pct < 0.30 { return .degraded }
        return .corrupted
    }

    public func toLogPayload() -> [String: String] {
        [
            "total_wids": String(totalWids),
            "offscreen_at_restore": String(widsOffscreenAtRestore),
            "zombies_purged": String(widsZombiesPurged),
            "drifts_fixed": String(widToScopeDriftsFixed),
            "verdict": verdict.rawValue,
        ]
    }
}
```

### Modifiée : `Stage` (RoadieStagePlugin)

Ajout d'une méthode mutante `validateMembers(against displays: [DisplayInfo]) -> Int` :

```swift
extension Stage {
    /// Reset les savedFrame des members dont le centre n'est dans aucun display
    /// connu. Retourne le nombre de members invalidés.
    public mutating func validateMembers(against displays: [DisplayInfo]) -> Int {
        var invalidated = 0
        for i in memberWindows.indices {
            let frame = memberWindows[i].savedFrame
            guard frame != .zero else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let isOnKnownDisplay = displays.contains { $0.frame.contains(center) }
            if !isOnKnownDisplay {
                memberWindows[i].savedFrame = .zero
                invalidated += 1
            }
        }
        return invalidated
    }
}
```

### Inchangées (utilisées telles quelles)

- `StageManager.purgeOrphanWindows()` — SPEC-021
- `StageManager.rebuildWidToScopeIndex()` — SPEC-021
- `StageManager.auditOwnership()` — SPEC-021
- `WindowDesktopReconciler.runIntegrityCheck(autoFix:)` — SPEC-022
- `LayoutEngine.setLeafVisible(_:_:)` — SPEC-002 (peut-être étendu en V2.3 si tree leaf manquant confirmé)
- `HideStrategyImpl.show(_:registry:strategy:)` — SPEC-002 (modifié en V2.2 pour fallback safe)

## Flux de boot après SPEC-025

```text
1. roadied launchd start
2. NSApplication.setActivationPolicy(.accessory)
3. Daemon.bootstrap()
   a. AX trust check (existant)
   b. Logger setup (existant)
   c. CGPreflightScreenCaptureAccess log (SPEC-024 T015)
   d. stageManager.loadFromDisk()
      └─ Stage.validateMembers(against: displays)  ← NOUVEAU FR-001
         └─ wids_offscreen_at_restore captured
   e. StageManagerLocator.shared = stageManager
   f. Auto-fix au boot (NOUVEAU FR-002) :
      - violations_before = auditOwnership()
      - if non-empty : purgeOrphanWindows + rebuildWidToScopeIndex
      - log boot_audit_autofixed | boot_audit_clean
   g. BootStateHealth construit + log boot_state_health (NOUVEAU FR-003)
   h. Si verdict != healthy : terminal-notifier (NOUVEAU US3)
   i. RailIntegration.start() (SPEC-024)
   j. applyLayout initial
4. NSApp.run()
```

## Flux de `roadie heal`

```text
1. CLI roadie envoie {"command": "daemon.heal"} sur socket
2. CommandRouter.route → handleHeal(daemon:)
   a. start = Date()
   b. purged = stageManager.purgeOrphanWindows()
   c. drifts_fixed = stageManager.rebuildWidToScopeIndex() count
   d. daemon.applyLayout()
   e. wids_restored = (windowDesktopReconciler != nil)
                       ? await reconciler.runIntegrityCheck(autoFix: true).fixedCount
                       : 0
   f. duration_ms = Int(Date().timeIntervalSince(start) * 1000)
   g. return Response.success([purged, drifts_fixed, wids_restored, duration_ms])
3. CLI affiche output formaté humain ou JSON selon flag
```

## Schémas persistés inchangés

`~/.config/roadies/stages/<uuid>/<desktop>/<stage>.toml` : structure inchangée. Seule la sémantique de `members[].saved_frame` est étendue (plus de validation au load) mais le format est identique.

→ Aucun breaking change persisté. Compat ascendante stricte.
