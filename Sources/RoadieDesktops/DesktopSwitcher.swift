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
    private var pendingTarget: Int? = nil

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
            throw DesktopError.unknownDesktop(id)
        }

        let currentID = await registry.currentID

        // FR-006 : idempotence + back-and-forth
        if id == currentID {
            if config.backAndForth, let recent = await registry.recentID {
                // Back-and-forth : basculer vers recentID
                try await performSwitch(to: recent)
            }
            // back_and_forth=false ou pas de recent → no-op sans event
            return
        }

        // FR-025 / R-003 : sérialisation — si bascule en cours, mémoriser la dernière demande
        if inFlight {
            pendingTarget = id
            return
        }

        try await performSwitch(to: id)
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

        // (e) Activer le stage du desktop d'arrivée
        if let ops = stageOps {
            let toDesktop = await registry.desktop(id: targetID)
            let activeInTo = toDesktop?.activeStageID
            if let stageID = activeInTo {
                await ops.activate(stageID)
            }
        }

        // (f) Émettre l'event desktop_changed
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
