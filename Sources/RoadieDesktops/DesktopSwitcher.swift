import Foundation
import CoreGraphics
import AppKit
import RoadieCore

// MARK: - Erreurs

public enum DesktopError: Error, Equatable {
    case unknownDesktop(Int)
    case noRecentDesktop
    case multiDesktopDisabled
}

// MARK: - DesktopSwitcherConfig

public struct DesktopSwitcherConfig: Sendable {
    public let count: Int
    public let backAndForth: Bool

    public init(count: Int = 10, backAndForth: Bool = true) {
        self.count = count
        self.backAndForth = backAndForth
    }
}

// MARK: - DesktopSwitcher

/// Orchestrateur de la bascule entre desktops virtuels (SPEC-011, FR-002).
/// Délègue entièrement le hide/show des fenêtres au StageManager via DesktopStageOps.
/// Pas d'appel aux frameworks privés — pas de déplacement offscreen direct (FR-004).
/// Sérialise les bascules via actor + pendingTarget (R-003, FR-025).
public actor DesktopSwitcher {
    private let registry: DesktopRegistry
    private let stageOps: (any DesktopStageOps)?
    private let bus: DesktopEventBus
    private let config: DesktopSwitcherConfig
    /// Hook optionnel appelé après chaque transition (T031).
    /// Utilisé par le daemon pour notifier StageManager.reload(forDesktop:).
    private let onDesktopChanged: (@Sendable (Int) async -> Void)?

    private var inFlight: Bool = false
    private var pendingTarget: Int?

    public init(registry: DesktopRegistry,
                stageOps: (any DesktopStageOps)? = nil,
                bus: DesktopEventBus,
                config: DesktopSwitcherConfig,
                onDesktopChanged: (@Sendable (Int) async -> Void)? = nil) {
        self.registry = registry
        self.stageOps = stageOps
        self.bus = bus
        self.config = config
        self.onDesktopChanged = onDesktopChanged
    }

    // MARK: - Bascule principale (T019-T022)

    /// Bascule vers le desktop `id`. Implémente la state machine data-model.md.
    ///
    /// **Comportement sur séquences rapides (FR-025, M4)** : si une bascule est déjà
    /// en cours (`inFlight == true`), la demande est mémorisée dans `pendingTarget`.
    /// Seule la DERNIÈRE demande en attente est retenue — les demandes intermédiaires
    /// sont annulées. Ce comportement est intentionnel et conforme à FR-025 (last wins).
    /// Ne pas modifier sans réviser FR-025.
    public func `switch`(to id: Int) async throws {
        // FR-023 : validation range
        guard (1...config.count).contains(id) else {
            logWarn("desktop_switch_rejected", [
                "to": String(id), "reason": "out_of_range",
                "count": String(config.count)
            ])
            throw DesktopError.unknownDesktop(id)
        }

        let currentID = await registry.currentID
        logInfo("desktop_switch_requested", [
            "from": String(currentID), "to": String(id),
            "in_flight": String(inFlight)
        ])

        // FR-006 : idempotence + back-and-forth
        if id == currentID {
            if config.backAndForth, let recent = await registry.recentID {
                logInfo("desktop_switch_back_and_forth", [
                    "current": String(currentID), "recent": String(recent)
                ])
                try await performSwitch(to: recent)
            } else {
                logInfo("desktop_switch_noop_same_id",
                        ["id": String(id), "back_and_forth": String(config.backAndForth)])
            }
            return
        }

        // FR-025 / R-003 : sérialisation — si bascule en cours, mémoriser la dernière demande
        if inFlight {
            logInfo("desktop_switch_pending",
                    ["from": String(currentID), "to": String(id)])
            pendingTarget = id
            return
        }

        try await performSwitch(to: id)
        logInfo("desktop_switch_completed",
                ["from": String(currentID), "to": String(id)])
    }

    /// Bascule vers `recentID` (FR-007).
    public func back() async throws {
        guard let recent = await registry.recentID else {
            throw DesktopError.noRecentDesktop
        }
        try await `switch`(to: recent)
    }

    // MARK: - Logique interne

    private func performSwitch(to targetID: Int) async throws {
        inFlight = true
        defer { inFlight = false }

        let fromID = await registry.currentID

        // (a) Sauvegarder le stage actif courant dans le desktop quitté
        if let ops = stageOps {
            let activeInFrom = await ops.currentStageID()
            if let stageID = activeInFrom, var fromDesktop = await registry.desktop(id: fromID) {
                fromDesktop.activeStageID = stageID
                try? await registry.save(fromDesktop)
            }
            // (b) Tout cacher via StageManager
            await ops.deactivateAll()
        }

        // (c) Mettre à jour le registry (currentID + recentID)
        await registry.setCurrent(id: targetID)
        do {
            try await registry.saveCurrentID()
        } catch {
            logWarn("saveCurrentID failed", ["error": "\(error)", "desktop": String(targetID)])
        }

        // (d) Notifier les modules scopés au desktop (ex : StageManager — T031)
        await onDesktopChanged?(targetID)

        // (e) Activer le stage du desktop d'arrivée.
        // FIX : si activeStageID est nil (cas notamment du desktop quitté SANS save
        // par une transition incomplète, ou du desktop jamais visité dont les stages
        // viennent juste d'être rechargés), fallback sur le PREMIER stage du desktop.
        // Sans ce fallback, les fenêtres restent hidden et l'utilisateur doit créer
        // une nouvelle fenêtre pour déclencher un layout (re-show).
        if let ops = stageOps {
            let toDesktop = await registry.desktop(id: targetID)
            var stageToActivate: Int? = toDesktop?.activeStageID
            if stageToActivate == nil, let first = toDesktop?.stages.first {
                stageToActivate = first.id
            }
            if let stageID = stageToActivate {
                await ops.activate(stageID)
            }
        }

        // (f) Émettre l'event desktop_changed (SPEC-013 FR-024 : payload étendu).
        let fromLabel = await registry.desktop(id: fromID)?.label ?? ""
        let toDesktop = await registry.desktop(id: targetID)
        let toLabel = toDesktop?.label ?? ""
        let event = DesktopChangeEvent(
            event: "desktop_changed",
            from: String(fromID),
            to: String(targetID),
            fromLabel: fromLabel,
            toLabel: toLabel
        )
        await bus.publish(event)
        // SPEC-013 FR-024 : event additionnel via EventBus.shared avec display_id
        // (= primary en mode global) et mode pour SketchyBar et autres consumers.
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let primaryID = CGMainDisplayID()
        await EventBus.shared.publish(DesktopEvent(
            name: "desktop_changed",
            payload: [
                "from": String(fromID),
                "to": String(targetID),
                "display_id": String(primaryID),
                "mode": "global",
                "ts": String(ts)
            ]
        ))

        // FR-025 : si une bascule a été mise en attente pendant cette exécution
        if let next = pendingTarget {
            pendingTarget = nil
            let newCurrent = await registry.currentID
            if next != newCurrent {
                inFlight = false   // reset avant la récursion
                try await performSwitch(to: next)
            }
        }
    }
}
