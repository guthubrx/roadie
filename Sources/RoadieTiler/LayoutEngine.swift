import Foundation
import ApplicationServices
import RoadieCore

/// Moteur de layout : applique les frames calculées par un Tiler aux fenêtres AX.
@MainActor
public final class LayoutEngine {
    private let registry: WindowRegistry
    public private(set) var workspace: Workspace
    public var tiler: any Tiler

    public init(registry: WindowRegistry, workspaceID: WorkspaceID = .main, strategy: TilerStrategy = .bsp) throws {
        self.registry = registry
        self.workspace = Workspace(id: workspaceID)
        guard let tiler = TilerRegistry.make(strategy) else {
            throw LayoutEngineError.unknownStrategy(strategy)
        }
        self.tiler = tiler
        self.workspace.tilerStrategy = strategy
    }

    /// Change la stratégie au runtime. Échoue sans modifier l'état si stratégie inconnue.
    public func setStrategy(_ strategy: TilerStrategy) throws {
        guard let newTiler = TilerRegistry.make(strategy) else {
            throw LayoutEngineError.unknownStrategy(strategy)
        }
        let leaves = workspace.rootNode.allLeaves.map { $0.windowID }
        workspace.rootNode = TilingContainer(orientation: .horizontal)
        workspace.tilerStrategy = strategy
        tiler = newTiler
        var lastInserted: WindowLeaf?
        for wid in leaves {
            let leaf = WindowLeaf(windowID: wid)
            tiler.insert(leaf: leaf, near: lastInserted, in: workspace.rootNode)
            lastInserted = leaf
        }
        logInfo("tiler strategy changed", ["new": strategy.rawValue])
    }

    /// Seed le rect d'écran utilisable. À appeler au bootstrap avant les premières
    /// insertions pour que l'auto-orientation BSP dispose des `lastFrame` dès la 1ère
    /// fenêtre. Sans ce seed, la 1ère insertion retombe sur l'orientation parent.opposite
    /// au lieu d'utiliser l'aspect ratio de l'écran.
    public func setScreenRect(_ rect: CGRect) {
        workspace.lastAppliedRect = rect
        // Calcul à blanc pour propager les lastFrame dans tout l'arbre existant
        // (cas de re-seed après changement de display ou de gaps).
        _ = tiler.layout(rect: rect, root: workspace.rootNode)
    }

    /// Insère une fenêtre dans l'arbre.
    public func insertWindow(_ wid: WindowID, focusedID: WindowID?) {
        // Dry-run layout pour peupler les `lastFrame` du target avant l'insert.
        // Indispensable à l'auto-orientation BSP qui décide horizontal/vertical
        // selon l'aspect ratio du target.
        if let rect = workspace.lastAppliedRect {
            _ = tiler.layout(rect: rect, root: workspace.rootNode)
        }
        let target: WindowLeaf? = focusedID.flatMap { TreeNode.find(windowID: $0, in: workspace.rootNode) }
        let leaf = WindowLeaf(windowID: wid)
        tiler.insert(leaf: leaf, near: target, in: workspace.rootNode)
    }

    public func removeWindow(_ wid: WindowID) {
        if let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode) {
            tiler.remove(leaf: leaf, from: workspace.rootNode)
        }
    }

    /// Marque une leaf comme invisible (minimisée) — sa position dans l'arbre est préservée,
    /// mais elle ne consomme pas d'espace au prochain layout. Retourne true si la leaf existe.
    @discardableResult
    public func setLeafVisible(_ wid: WindowID, _ visible: Bool) -> Bool {
        guard let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode) else { return false }
        leaf.isVisible = visible
        return true
    }

    /// Reconstruit l'arbre BSP depuis la liste plate des leaves existantes.
    /// Utile quand le tree est devenu plat (cascade d'inserts avec target=nil).
    /// Préserve l'ordre d'origine et l'état isVisible.
    public func rebuildTree() {
        let oldLeaves = workspace.rootNode.allLeaves
        let snapshots = oldLeaves.map { ($0.windowID, $0.isVisible) }
        workspace.rootNode = TilingContainer(orientation: .horizontal)
        var lastInserted: WindowLeaf?
        for (wid, visible) in snapshots {
            let leaf = WindowLeaf(windowID: wid)
            leaf.isVisible = visible
            tiler.insert(leaf: leaf, near: lastInserted, in: workspace.rootNode)
            lastInserted = leaf
        }
        logInfo("tree rebuilt", ["leaves": String(snapshots.count)])
    }

    @discardableResult
    public func move(_ wid: WindowID, direction: Direction) -> Bool {
        guard let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode) else { return false }
        return tiler.move(leaf: leaf, direction: direction, in: workspace.rootNode)
    }

    public func resize(_ wid: WindowID, direction: Direction, delta: CGFloat) {
        guard let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode) else { return }
        tiler.resize(leaf: leaf, direction: direction, delta: delta, in: workspace.rootNode)
    }

    public func focusNeighbor(of wid: WindowID, direction: Direction) -> WindowID? {
        guard let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode) else { return nil }
        return tiler.focusNeighbor(of: leaf, direction: direction, in: workspace.rootNode)?.windowID
    }

    /// Adapte les `adaptiveWeight` de l'arbre pour refléter une nouvelle frame imposée
    /// manuellement (drag-resize utilisateur). Ne modifie pas la leaf cible elle-même —
    /// le delta pixel est transféré aux siblings appropriés sur chaque edge bougé,
    /// ainsi l'utilisateur garde la taille qu'il vient de choisir au prochain layout.
    /// - Returns: true si au moins un edge a été adapté.
    @discardableResult
    public func adaptToManualResize(_ wid: WindowID, newFrame: CGRect, threshold: CGFloat = 5.0) -> Bool {
        guard let leaf = TreeNode.find(windowID: wid, in: workspace.rootNode),
              let oldFrame = leaf.lastFrame else { return false }
        let leftDelta = oldFrame.minX - newFrame.minX     // >0 si étendu vers la gauche
        let rightDelta = newFrame.maxX - oldFrame.maxX    // >0 si étendu vers la droite
        let topDelta = oldFrame.minY - newFrame.minY      // >0 si étendu vers le haut
        let bottomDelta = newFrame.maxY - oldFrame.maxY   // >0 si étendu vers le bas

        var changed = false
        if abs(leftDelta) > threshold { adjustEdge(leaf: leaf, direction: .left, deltaPixels: leftDelta); changed = true }
        if abs(rightDelta) > threshold { adjustEdge(leaf: leaf, direction: .right, deltaPixels: rightDelta); changed = true }
        if abs(topDelta) > threshold { adjustEdge(leaf: leaf, direction: .up, deltaPixels: topDelta); changed = true }
        if abs(bottomDelta) > threshold { adjustEdge(leaf: leaf, direction: .down, deltaPixels: bottomDelta); changed = true }
        return changed
    }

    /// Transfère du adaptiveWeight entre `leaf` et son sibling sur l'edge `direction`,
    /// équivalent à `deltaPixels` pixels (positif = la leaf grandit, le sibling rétrécit).
    /// Remonte dans l'arbre jusqu'à trouver un container dont l'orientation correspond.
    private func adjustEdge(leaf: WindowLeaf, direction: Direction, deltaPixels: CGFloat) {
        var current: TreeNode = leaf
        while let parent = current.parent {
            if parent.orientation == direction.orientation {
                guard let idx = parent.index(of: current) else { return }
                let siblingIdx = direction.sign > 0 ? idx + 1 : idx - 1
                if siblingIdx < 0 || siblingIdx >= parent.children.count {
                    current = parent
                    continue   // bord atteint dans ce container, remonter d'un niveau
                }
                let sibling = parent.children[siblingIdx]
                guard let containerFrame = parent.lastFrame else { return }
                let axisLength = direction.orientation == .horizontal
                    ? containerFrame.width : containerFrame.height
                guard axisLength > 0 else { return }
                let totalWeight = parent.children.reduce(CGFloat(0)) { $0 + $1.adaptiveWeight }
                // Conversion exacte pixel → weight pour que la leaf garde sa frame voulue.
                let deltaWeight = (deltaPixels / axisLength) * totalWeight
                current.adaptiveWeight = max(0.1, current.adaptiveWeight + deltaWeight)
                sibling.adaptiveWeight = max(0.1, sibling.adaptiveWeight - deltaWeight)
                return
            }
            current = parent
        }
    }

    /// Calcule les frames et applique via AX. Gaps externes asymétriques par défaut
    /// uniformes (compat ancienne API) ; passer un OuterGaps pour spec par côté.
    public func apply(rect: CGRect, gapsOuter: CGFloat = 0, gapsInner: CGFloat = 0) {
        apply(rect: rect, outerGaps: .uniform(Int(gapsOuter)), gapsInner: gapsInner)
    }

    public func apply(rect: CGRect, outerGaps: OuterGaps, gapsInner: CGFloat = 0) {
        let usable = CGRect(
            x: rect.origin.x + CGFloat(outerGaps.left),
            y: rect.origin.y + CGFloat(outerGaps.top),
            width: rect.width - CGFloat(outerGaps.left + outerGaps.right),
            height: rect.height - CGFloat(outerGaps.top + outerGaps.bottom)
        )
        workspace.lastAppliedRect = usable
        let frames = tiler.layout(rect: usable, root: workspace.rootNode)
        for (wid, frame) in frames {
            guard let element = registry.axElement(for: wid) else { continue }
            let innerFrame = frame.insetBy(dx: gapsInner / 2, dy: gapsInner / 2)
            AXReader.setBounds(element, frame: innerFrame)
            registry.updateFrame(wid, frame: innerFrame)
        }
    }
}

public enum LayoutEngineError: Error, CustomStringConvertible {
    case unknownStrategy(TilerStrategy)
    public var description: String {
        switch self {
        case .unknownStrategy(let s):
            let avail = TilerRegistry.availableStrategies.map(\.rawValue).joined(separator: ", ")
            return "unknown tiler strategy: \(s.rawValue). Available: \(avail)"
        }
    }
}

// MARK: - Workspace state

public struct Workspace {
    public let id: WorkspaceID
    public var displayID: CGDirectDisplayID
    public var rootNode: TilingContainer
    public var tilerStrategy: TilerStrategy
    public var floatingWindowIDs: Set<WindowID>
    /// Dernier rect utilisable (workArea moins gaps externes). Permet à insertWindow
    /// de faire un dry-run layout avant l'insert pour peupler les `lastFrame`.
    public var lastAppliedRect: CGRect?

    public init(id: WorkspaceID,
                displayID: CGDirectDisplayID = CGMainDisplayID(),
                tilerStrategy: TilerStrategy = .bsp) {
        self.id = id
        self.displayID = displayID
        self.rootNode = TilingContainer(orientation: .horizontal)
        self.tilerStrategy = tilerStrategy
        self.floatingWindowIDs = []
        self.lastAppliedRect = nil
    }
}
