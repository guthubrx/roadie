import Foundation
import CoreGraphics
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
    public let offscreenX: Int
    public let offscreenY: Int

    public init(count: Int = 10, backAndForth: Bool = true,
                offscreenX: Int = -30000, offscreenY: Int = -30000) {
        self.count = count
        self.backAndForth = backAndForth
        self.offscreenX = offscreenX
        self.offscreenY = offscreenY
    }
}

// MARK: - DesktopSwitcher

/// Orchestrateur de la bascule entre desktops virtuels (SPEC-011, FR-002).
/// Sérialise les bascules via actor + pendingTarget (R-003, FR-025).
/// Pas d'appel SkyLight/CGS — déplacement offscreen/onscreen exclusivement via AX (FR-004).
public actor DesktopSwitcher {
    private let registry: DesktopRegistry
    private let mover: any WindowMover
    private let bus: DesktopEventBus
    private let config: DesktopSwitcherConfig
    /// Hook optionnel appelé après chaque transition (T031).
    /// Utilisé par le daemon pour notifier StageManager.reload(forDesktop:).
    private let onDesktopChanged: (@Sendable (Int) async -> Void)?

    private var inFlight: Bool = false
    private var pendingTarget: Int? = nil

    public init(registry: DesktopRegistry,
                mover: any WindowMover,
                bus: DesktopEventBus,
                config: DesktopSwitcherConfig,
                onDesktopChanged: (@Sendable (Int) async -> Void)? = nil) {
        self.registry = registry
        self.mover = mover
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

    /// Restauration visuelle au boot (T038) : show/hide sans émettre desktop_changed.
    /// Aligne l'écran avec le state persisté après un redémarrage du daemon.
    public func restoreInitialView() async {
        let currentID = await registry.currentID
        let allDesktops = await registry.allDesktops()
        let offPoint = CGPoint(x: config.offscreenX, y: config.offscreenY)
        for desktop in allDesktops {
            if desktop.id == currentID {
                for entry in desktop.windows {
                    await mover.move(CGWindowID(entry.cgwid), to: entry.expectedFrame.origin)
                }
            } else {
                for entry in desktop.windows {
                    await mover.move(CGWindowID(entry.cgwid), to: offPoint)
                }
            }
        }
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
        defer {
            inFlight = false
        }

        let fromID = await registry.currentID

        // (a) Cacher les fenêtres du desktop courant
        let fromWIDs = await registry.windows(of: fromID)
        let offPoint = CGPoint(x: config.offscreenX, y: config.offscreenY)
        for wid in fromWIDs {
            await mover.move(wid, to: offPoint)
        }

        // (b) Restaurer les fenêtres du desktop cible à leur expectedFrame
        let toDesktop = await registry.desktop(id: targetID)
        let toWindows = toDesktop?.windows ?? []
        for entry in toWindows {
            let origin = entry.expectedFrame.origin
            await mover.move(CGWindowID(entry.cgwid), to: origin)
        }

        // (c) Mettre à jour le registry
        await registry.setCurrent(id: targetID)
        do {
            try await registry.saveCurrentID()
        } catch {
            logWarn("saveCurrentID failed", ["error": "\(error)", "desktop": String(targetID)])
        }

        // (c.2) Notifier les modules scopés au desktop (ex : StageManager — T031)
        await onDesktopChanged?(targetID)

        // (d) Émettre l'event desktop_changed
        let fromLabel = await registry.desktop(id: fromID)?.label ?? ""
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
                // Récursion via une nouvelle Task pour ne pas bloquer le defer
                inFlight = false   // reset avant la récursion
                try await performSwitch(to: next)
            }
        }
    }
}
