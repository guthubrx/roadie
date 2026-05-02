import Foundation
import ApplicationServices
import AppKit
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

    // MARK: - Helpers multi-display

    /// Crée un TilingContainer vide pour un displayID donné et l'enregistre.
    @discardableResult
    private func createRoot(for displayID: CGDirectDisplayID) -> TilingContainer {
        let root = TilingContainer(orientation: .horizontal)
        workspace.rootsByDisplay[displayID] = root
        return root
    }

    /// Retourne le root pour un displayID, en le créant à la demande si absent.
    private func root(for displayID: CGDirectDisplayID) -> TilingContainer {
        if let existing = workspace.rootsByDisplay[displayID] { return existing }
        return createRoot(for: displayID)
    }

    /// Détermine le displayID contenant un point en coords AX (top-left).
    /// Utilise NSScreen.screens directement (sync — incompatible avec async actor).
    /// Fallback : CGMainDisplayID si aucun écran ne contient le point.
    private func displayIDContaining(point axPoint: CGPoint) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        // Conversion AX (top-left) → NS (bottom-left) via la hauteur de l'écran principal.
        let mainH = screens[0].frame.height
        let nsPoint = CGPoint(x: axPoint.x, y: mainH - axPoint.y)
        let hit = screens.first { $0.frame.contains(nsPoint) }
        return hit.flatMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }
    }

    /// Instancie le tiler approprié pour un displayID donné.
    /// Sprint 2 : stratégie globale uniquement. Per-display strategy = T038.
    private func currentTiler(for _: CGDirectDisplayID) -> any Tiler {
        return tiler
    }

    // MARK: - Change de stratégie

    /// Change la stratégie au runtime. Échoue sans modifier l'état si stratégie inconnue.
    public func setStrategy(_ strategy: TilerStrategy) throws {
        guard let newTiler = TilerRegistry.make(strategy) else {
            throw LayoutEngineError.unknownStrategy(strategy)
        }
        // Reconstruire chaque arbre avec la nouvelle stratégie.
        for (displayID, root) in workspace.rootsByDisplay {
            let leaves = root.allLeaves.map { $0.windowID }
            let newRoot = TilingContainer(orientation: .horizontal)
            workspace.rootsByDisplay[displayID] = newRoot
            var lastInserted: WindowLeaf?
            for wid in leaves {
                let leaf = WindowLeaf(windowID: wid)
                newTiler.insert(leaf: leaf, near: lastInserted, in: newRoot)
                lastInserted = leaf
            }
        }
        workspace.tilerStrategy = strategy
        tiler = newTiler
        logInfo("tiler strategy changed", ["new": strategy.rawValue])
    }

    /// Seed le rect d'écran utilisable pour le primary display.
    /// À appeler au bootstrap avant les premières insertions.
    public func setScreenRect(_ rect: CGRect) {
        let primaryID = CGMainDisplayID()
        workspace.lastAppliedRectsByDisplay[primaryID] = rect
        workspace.lastAppliedRect = rect
        let primaryRoot = root(for: primaryID)
        _ = tiler.layout(rect: rect, root: primaryRoot)
    }

    // MARK: - Insertion / suppression

    /// Insère une fenêtre dans l'arbre du bon display.
    /// - Parameter displayID: display cible (optionnel — déduit du centre de frame si nil).
    public func insertWindow(_ wid: WindowID, focusedID: WindowID?,
                             displayID: CGDirectDisplayID? = nil) {
        let resolved = resolveDisplayID(for: wid, hint: displayID)
        let targetRoot = root(for: resolved)
        // Dry-run layout pour peupler les `lastFrame` du target avant l'insert.
        if let rect = workspace.lastAppliedRectsByDisplay[resolved] {
            _ = tiler.layout(rect: rect, root: targetRoot)
        } else if let rect = workspace.lastAppliedRect {
            _ = tiler.layout(rect: rect, root: targetRoot)
        }
        // Le focusedID doit être dans le même arbre pour être un target valide.
        let target: WindowLeaf? = focusedID.flatMap { TreeNode.find(windowID: $0, in: targetRoot) }
        let leaf = WindowLeaf(windowID: wid)
        tiler.insert(leaf: leaf, near: target, in: targetRoot)
    }

    /// Détermine le displayID pour un wid, en priorité via le hint explicite,
    /// puis via le centre de sa frame courante, puis via CGMainDisplayID.
    private func resolveDisplayID(for wid: WindowID, hint: CGDirectDisplayID?) -> CGDirectDisplayID {
        if let did = hint { return did }
        if let state = registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            if let did = displayIDContaining(point: center) { return did }
        }
        return CGMainDisplayID()
    }

    public func removeWindow(_ wid: WindowID) {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                tiler.remove(leaf: leaf, from: root)
                return
            }
        }
    }

    /// Déplace un wid de l'arbre `src` vers l'arbre `dst` (T021, R-005).
    /// - Returns: true si le wid existait dans l'arbre src et a été transféré.
    @discardableResult
    public func moveWindow(_ wid: WindowID,
                           fromDisplay src: CGDirectDisplayID,
                           toDisplay dst: CGDirectDisplayID) -> Bool {
        guard let srcRoot = workspace.rootsByDisplay[src],
              let leaf = TreeNode.find(windowID: wid, in: srcRoot) else { return false }
        // Conserver l'état de visibilité avant de retirer la leaf.
        let wasVisible = leaf.isVisible
        // Retirer proprement du src via le tiler (normalise les containers vides).
        tiler.remove(leaf: leaf, from: srcRoot)
        // Créer le root dst si absent.
        let dstRoot = root(for: dst)
        // Construire une nouvelle leaf (remove() détache parent, réutiliser sans risque de cycle).
        let newLeaf = WindowLeaf(windowID: wid)
        newLeaf.isVisible = wasVisible
        let dstTiler = currentTiler(for: dst)
        dstTiler.insert(leaf: newLeaf, near: nil, in: dstRoot)
        logInfo("moveWindow", [
            "wid": String(wid),
            "from": String(src),
            "to": String(dst),
        ])
        return true
    }

    /// Marque une leaf comme invisible (minimisée) dans n'importe quel arbre.
    /// Retourne true si la leaf existe.
    @discardableResult
    public func setLeafVisible(_ wid: WindowID, _ visible: Bool) -> Bool {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                leaf.isVisible = visible
                return true
            }
        }
        return false
    }

    /// Reconstruit l'arbre BSP du primary display depuis la liste plate des leaves.
    public func rebuildTree() {
        let primaryRoot = root(for: CGMainDisplayID())
        let oldLeaves = primaryRoot.allLeaves
        let snapshots = oldLeaves.map { ($0.windowID, $0.isVisible) }
        workspace.rootsByDisplay[CGMainDisplayID()] = TilingContainer(orientation: .horizontal)
        let newRoot = root(for: CGMainDisplayID())
        var lastInserted: WindowLeaf?
        for (wid, visible) in snapshots {
            let leaf = WindowLeaf(windowID: wid)
            leaf.isVisible = visible
            tiler.insert(leaf: leaf, near: lastInserted, in: newRoot)
            lastInserted = leaf
        }
        logInfo("tree rebuilt", ["leaves": String(snapshots.count)])
    }

    // MARK: - Navigation / resize

    @discardableResult
    public func move(_ wid: WindowID, direction: Direction) -> Bool {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                return tiler.move(leaf: leaf, direction: direction, in: root)
            }
        }
        return false
    }

    public func resize(_ wid: WindowID, direction: Direction, delta: CGFloat) {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                tiler.resize(leaf: leaf, direction: direction, delta: delta, in: root)
                return
            }
        }
    }

    public func focusNeighbor(of wid: WindowID, direction: Direction) -> WindowID? {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                return tiler.focusNeighbor(of: leaf, direction: direction, in: root)?.windowID
            }
        }
        return nil
    }

    /// Adapte les `adaptiveWeight` de l'arbre pour refléter une nouvelle frame imposée
    /// manuellement (drag-resize utilisateur).
    /// - Returns: true si au moins un edge a été adapté.
    @discardableResult
    public func adaptToManualResize(_ wid: WindowID, newFrame: CGRect, threshold: CGFloat = 5.0) -> Bool {
        for (_, root) in workspace.rootsByDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root),
               let oldFrame = leaf.lastFrame {
                let leftDelta   = oldFrame.minX - newFrame.minX
                let rightDelta  = newFrame.maxX - oldFrame.maxX
                let topDelta    = oldFrame.minY - newFrame.minY
                let bottomDelta = newFrame.maxY - oldFrame.maxY
                var changed = false
                if abs(leftDelta)   > threshold { adjustEdge(leaf: leaf, direction: .left,  deltaPixels: leftDelta);   changed = true }
                if abs(rightDelta)  > threshold { adjustEdge(leaf: leaf, direction: .right, deltaPixels: rightDelta);  changed = true }
                if abs(topDelta)    > threshold { adjustEdge(leaf: leaf, direction: .up,    deltaPixels: topDelta);    changed = true }
                if abs(bottomDelta) > threshold { adjustEdge(leaf: leaf, direction: .down,  deltaPixels: bottomDelta); changed = true }
                return changed
            }
        }
        return false
    }

    /// Transfère du adaptiveWeight entre `leaf` et son sibling sur l'edge `direction`.
    private func adjustEdge(leaf: WindowLeaf, direction: Direction, deltaPixels: CGFloat) {
        var current: TreeNode = leaf
        while let parent = current.parent {
            if parent.orientation == direction.orientation {
                guard let idx = parent.index(of: current) else { return }
                let siblingIdx = direction.sign > 0 ? idx + 1 : idx - 1
                if siblingIdx < 0 || siblingIdx >= parent.children.count {
                    current = parent
                    continue
                }
                let sibling = parent.children[siblingIdx]
                guard let containerFrame = parent.lastFrame else { return }
                let axisLength = direction.orientation == .horizontal
                    ? containerFrame.width : containerFrame.height
                guard axisLength > 0 else { return }
                let totalWeight = parent.children.reduce(CGFloat(0)) { $0 + $1.adaptiveWeight }
                let deltaWeight = (deltaPixels / axisLength) * totalWeight
                current.adaptiveWeight = max(0.1, current.adaptiveWeight + deltaWeight)
                sibling.adaptiveWeight = max(0.1, sibling.adaptiveWeight - deltaWeight)
                return
            }
            current = parent
        }
    }

    // MARK: - Apply (mono-écran, compat FR-024)

    /// Calcule les frames et applique via AX — API legacy mono-écran.
    /// Applique sur le root du primary display uniquement.
    public func apply(rect: CGRect, gapsOuter: CGFloat = 0, gapsInner: CGFloat = 0) {
        apply(rect: rect, outerGaps: .uniform(Int(gapsOuter)), gapsInner: gapsInner)
    }

    public func apply(rect: CGRect, outerGaps: OuterGaps, gapsInner: CGFloat = 0) {
        let usable = applyOuterGaps(rect, outerGaps: outerGaps)
        let primaryID = CGMainDisplayID()
        workspace.lastAppliedRect = usable
        workspace.lastAppliedRectsByDisplay[primaryID] = usable
        let primaryRoot = root(for: primaryID)
        let frames = tiler.layout(rect: usable, root: primaryRoot)
        for (wid, frame) in frames {
            guard let element = registry.axElement(for: wid) else { continue }
            let innerFrame = frame.insetBy(dx: gapsInner / 2, dy: gapsInner / 2)
            AXReader.setBounds(element, frame: innerFrame)
            registry.updateFrame(wid, frame: innerFrame)
        }
    }

    // MARK: - Apply multi-display (T014)

    /// Applique le layout sur tous les displays connus du registry.
    /// Itère sur chaque Display, utilise son visibleFrame et ses gaps propres.
    public func applyAll(displayRegistry: DisplayRegistry) async {
        let displays = await displayRegistry.displays
        for display in displays {
            let usable = applyOuterGaps(
                display.visibleFrame,
                outerGaps: .uniform(display.gapsOuter)
            )
            let displayRoot = root(for: display.id)
            workspace.lastAppliedRectsByDisplay[display.id] = usable
            let displayTiler = currentTiler(for: display.id)
            let frames = displayTiler.layout(rect: usable, root: displayRoot)
            let innerInset = CGFloat(display.gapsInner) / 2
            for (wid, frame) in frames {
                guard let element = registry.axElement(for: wid) else { continue }
                let innerFrame = frame.insetBy(dx: innerInset, dy: innerInset)
                AXReader.setBounds(element, frame: innerFrame)
                registry.updateFrame(wid, frame: innerFrame)
            }
        }
    }

    // MARK: - Helper gaps

    private func applyOuterGaps(_ rect: CGRect, outerGaps: OuterGaps) -> CGRect {
        CGRect(
            x: rect.origin.x + CGFloat(outerGaps.left),
            y: rect.origin.y + CGFloat(outerGaps.top),
            width: rect.width  - CGFloat(outerGaps.left + outerGaps.right),
            height: rect.height - CGFloat(outerGaps.top  + outerGaps.bottom)
        )
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
    public var tilerStrategy: TilerStrategy
    public var floatingWindowIDs: Set<WindowID>

    // MARK: Multi-display (T013)

    /// Un arbre par écran (clé = CGDirectDisplayID).
    public var rootsByDisplay: [CGDirectDisplayID: TilingContainer]

    /// Dernier rect utilisable par display. Permet le dry-run layout avant insert.
    public var lastAppliedRectsByDisplay: [CGDirectDisplayID: CGRect]

    /// Compat mono-écran : dernier rect du primary display.
    public var lastAppliedRect: CGRect?

    // MARK: Compat mono-écran (FR-024)

    /// Getter/setter de compatibilité : lit et écrit l'arbre du primary display.
    /// Le root primary est toujours présent (créé dans init), ce getter ne peut
    /// donc pas retourner nil. Le `!` est sûr par invariant de init.
    public var rootNode: TilingContainer {
        get { rootsByDisplay[CGMainDisplayID()]! }
        set { rootsByDisplay[CGMainDisplayID()] = newValue }
    }

    /// Identifiant du display principal (au sens CoreGraphics).
    public var displayID: CGDirectDisplayID { CGMainDisplayID() }

    public init(id: WorkspaceID,
                tilerStrategy: TilerStrategy = .bsp) {
        self.id = id
        self.tilerStrategy = tilerStrategy
        self.floatingWindowIDs = []
        self.rootsByDisplay = [:]
        self.lastAppliedRectsByDisplay = [:]
        self.lastAppliedRect = nil
        // Créer le root primary d'emblée pour que les accès legacy fonctionnent
        // immédiatement sans nil-check.
        let primaryID = CGMainDisplayID()
        self.rootsByDisplay[primaryID] = TilingContainer(orientation: .horizontal)
    }
}
