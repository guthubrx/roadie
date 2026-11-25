import CoreGraphics
import RoadieCore

/// Groupe d'onglets d'une stage pour les stratégies sans arbre (`scrolling`, `masterStack`, `bsp`, Spec 167).
public struct LayoutTabGroup: Equatable, Sendable {
    public var windowIDs: [WindowID]
    public var activeWindowID: WindowID?

    public init(windowIDs: [WindowID], activeWindowID: WindowID? = nil) {
        self.windowIDs = windowIDs
        self.activeWindowID = activeWindowID
    }
}

/// Slot normalisé issu de la réduction des groupes d'onglets d'une stage (Spec 167) :
/// une fenêtre seule ou une pile d'au moins deux onglets vivants partageant la même tuile / colonne.
public struct LayoutTabSlot: Equatable, Sendable {
    public var anchorID: WindowID
    public var windowIDs: [WindowID]
    public var activeWindowID: WindowID

    public var isTabGroup: Bool { windowIDs.count >= 2 }

    public init(anchorID: WindowID, windowIDs: [WindowID], activeWindowID: WindowID) {
        self.anchorID = anchorID
        self.windowIDs = windowIDs
        self.activeWindowID = activeWindowID
    }
}

/// Emplacement géométrique d'une barre d'onglets pour un slot multi-onglets en coordonnées AX (Spec 167).
public struct LayoutTabBarPlacement: Equatable, Sendable {
    public var tileFrame: CGRect
    public var barFrame: CGRect
    public var windowIDs: [WindowID]
    public var active: WindowID

    public init(tileFrame: CGRect, barFrame: CGRect, windowIDs: [WindowID], active: WindowID) {
        self.tileFrame = tileFrame
        self.barFrame = barFrame
        self.windowIDs = windowIDs
        self.active = active
    }
}

/// Couche pure de regroupement en slots à onglets pour les stratégies sans arbre
/// (`scrolling`, `masterStack`, `bsp`, Spec 167).
///
/// Principe :
/// 1. Chaque groupe valide (`>= 2` fenêtres vivantes dans `windowIDs`) est réduit à un seul slot
///    représenté par son onglet actif (`anchorID`), placé à la position du premier membre du groupe.
/// 2. La stratégie géométrique sous-jacente place uniquement les slots.
/// 3. Chaque slot à onglets réserve `tabBarHeight + 4 pt` en haut de sa tuile/colonne et place
///    l'ensemble des fenêtres du groupe dans le cadre contenu résultant.
public enum LayoutTabSlots {
    /// Écart vertical entre le bas de la barre d'onglets et le bord supérieur des fenêtres du groupe.
    public static let barGap: CGFloat = 4

    /// Résout la liste ordonnée des slots à partir des fenêtres vivantes et des groupes déclarés. O(n).
    public static func resolve(
        windowIDs: [WindowID],
        tabGroups: [LayoutTabGroup],
        focusedWindowID: WindowID?
    ) -> [LayoutTabSlot] {
        var uniqueWindows: [WindowID] = []
        uniqueWindows.reserveCapacity(windowIDs.count)
        var liveSet: Set<WindowID> = []
        for id in windowIDs where liveSet.insert(id).inserted {
            uniqueWindows.append(id)
        }
        guard !uniqueWindows.isEmpty else { return [] }

        // Sanitisation des groupes : uniquement les fenêtres vivantes, sans doublon inter-groupes, >= 2 membres.
        var sanitizedGroups: [(windowIDs: [WindowID], activeWindowID: WindowID?)] = []
        var claimed: Set<WindowID> = []
        var groupIndexByWindow: [WindowID: Int] = [:]
        for group in tabGroups {
            var members: [WindowID] = []
            var seenInGroup: Set<WindowID> = []
            for id in group.windowIDs {
                guard liveSet.contains(id), !claimed.contains(id), seenInGroup.insert(id).inserted else { continue }
                members.append(id)
            }
            guard members.count >= 2 else { continue }
            let idx = sanitizedGroups.count
            sanitizedGroups.append((members, group.activeWindowID))
            for id in members {
                claimed.insert(id)
                groupIndexByWindow[id] = idx
            }
        }

        var slots: [LayoutTabSlot] = []
        slots.reserveCapacity(uniqueWindows.count)
        var emittedGroups: Set<Int> = []
        for id in uniqueWindows {
            if let groupIdx = groupIndexByWindow[id] {
                guard emittedGroups.insert(groupIdx).inserted else { continue }
                let group = sanitizedGroups[groupIdx]
                let active: WindowID
                if let focus = focusedWindowID, group.windowIDs.contains(focus) {
                    active = focus
                } else if let stored = group.activeWindowID, group.windowIDs.contains(stored) {
                    active = stored
                } else {
                    active = group.windowIDs[0]
                }
                slots.append(LayoutTabSlot(anchorID: active, windowIDs: group.windowIDs, activeWindowID: active))
            } else {
                slots.append(LayoutTabSlot(anchorID: id, windowIDs: [id], activeWindowID: id))
            }
        }
        return slots
    }

    /// Construit la requête réduite aux seuls représentants de slots.
    private static func slotRequest(from request: LayoutRequest, slots: [LayoutTabSlot]) -> LayoutRequest {
        var reduced = request
        reduced.windowIDs = slots.map(\.anchorID)
        reduced.tabGroups = []
        if let focus = request.focusedWindowID,
           let slot = slots.first(where: { $0.windowIDs.contains(focus) }) {
            reduced.focusedWindowID = slot.anchorID
        }
        if !request.priorityWindowIDs.isEmpty {
            reduced.priorityWindowIDs = Set(slots.compactMap { slot in
                slot.windowIDs.contains(where: request.priorityWindowIDs.contains) ? slot.anchorID : nil
            })
        }
        if !request.newWindowIDs.isEmpty {
            reduced.newWindowIDs = Set(slots.compactMap { slot in
                slot.windowIDs.contains(where: request.newWindowIDs.contains) ? slot.anchorID : nil
            })
        }
        if !request.currentFrames.isEmpty {
            var frames: [WindowID: CGRect] = [:]
            for slot in slots {
                if let f = request.currentFrames[slot.anchorID]
                    ?? slot.windowIDs.compactMap({ request.currentFrames[$0] }).first {
                    frames[slot.anchorID] = f
                }
            }
            reduced.currentFrames = frames
        }
        return reduced
    }

    /// Planifie la requête via `strategy` sur les slots, puis étend chaque slot à onglets sous sa barre.
    public static func plan(_ request: LayoutRequest, using strategy: any LayoutStrategy) -> LayoutPlan {
        let slots = resolve(
            windowIDs: request.windowIDs,
            tabGroups: request.tabGroups,
            focusedWindowID: request.focusedWindowID
        )
        guard slots.contains(where: \.isTabGroup) else {
            return strategy.plan(request)
        }
        let slotPlan = strategy.plan(slotRequest(from: request, slots: slots))
        let barHeight = max(0, CGFloat(request.tabbedBarHeight))
        var placements: [WindowID: CGRect] = [:]
        placements.reserveCapacity(request.windowIDs.count)

        for slot in slots {
            guard let tileFrame = slotPlan.placements[slot.anchorID] else { continue }
            if !slot.isTabGroup {
                placements[slot.anchorID] = tileFrame
                continue
            }
            let reserve: CGFloat = barHeight > 0
                ? min(barHeight + barGap, floor(tileFrame.height / 3))
                : 0
            let contentFrame = CGRect(
                x: tileFrame.minX,
                y: tileFrame.minY + reserve,
                width: tileFrame.width,
                height: max(1, tileFrame.height - reserve)
            ).integral
            for id in slot.windowIDs {
                placements[id] = contentFrame
            }
        }
        return LayoutPlan(placements: placements)
    }

    /// Calcule les cadres exacts des barres d'onglets pour tous les slots multi-onglets de `request`.
    public static func tabBarFrames(for request: LayoutRequest) -> [LayoutTabBarPlacement] {
        guard request.mode.supportsSlotTabGroups else { return [] }
        let slots = resolve(
            windowIDs: request.windowIDs,
            tabGroups: request.tabGroups,
            focusedWindowID: request.focusedWindowID
        )
        guard slots.contains(where: \.isTabGroup) else { return [] }

        let strategy: any LayoutStrategy
        switch request.mode {
        case .scrolling:
            strategy = ScrollingLayoutStrategy(
                columnWidthRatio: CGFloat(request.scrollingColumnWidth),
                clipsLeft: request.scrollingClipsLeft,
                clipsRight: request.scrollingClipsRight
            )
        case .masterStack:
            strategy = MasterStackLayoutStrategy(masterRatio: CGFloat(request.masterRatio))
        case .bsp:
            strategy = BSPLayoutStrategy()
        default:
            return []
        }

        let slotPlan = strategy.plan(slotRequest(from: request, slots: slots))
        let configuredBar = max(16, CGFloat(request.tabbedBarHeight))
        var result: [LayoutTabBarPlacement] = []

        for slot in slots where slot.isTabGroup {
            guard let rawTile = slotPlan.placements[slot.anchorID] else { continue }
            let tile = rawTile.integral
            guard tile.width > 0, tile.height >= 24 else { continue }
            let reserve = min(configuredBar + barGap, floor(tile.height / 3))
            let barH = min(configuredBar, max(16, reserve - barGap))
            let barFrame = CGRect(
                x: tile.minX,
                y: tile.minY,
                width: tile.width,
                height: barH
            ).integral
            result.append(LayoutTabBarPlacement(
                tileFrame: tile,
                barFrame: barFrame,
                windowIDs: slot.windowIDs,
                active: slot.activeWindowID
            ))
        }
        return result
    }
}
