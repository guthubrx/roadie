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

    /// Cherche dans quel arbre `rootsByDisplay` le `wid` est inséré. Utilisé pour
    /// la migration cross-display déclenchée par un drag manuel : on compare le
    /// display calculé via la frame réelle vs celui dans lequel l'arbre stocke le wid.
    public func displayIDForWindow(_ wid: WindowID) -> CGDirectDisplayID? {
        for (id, root) in workspace.rootsByDisplay {
            if TreeNode.find(windowID: wid, in: root) != nil { return id }
        }
        return nil
    }

    /// Variante publique de `displayIDContaining(point:)` pour usage externe
    /// (ex: drag handler dans le daemon). Le point doit être en coords AX.
    public func displayIDContainingPoint(_ axPoint: CGPoint) -> CGDirectDisplayID? {
        return displayIDContaining(point: axPoint)
    }

    /// Détermine le displayID contenant un point en coords AX (top-left).
    /// Utilise NSScreen.screens directement (sync — incompatible avec async actor).
    /// Fallback : CGMainDisplayID si aucun écran ne contient le point.
    private func displayIDContaining(point axPoint: CGPoint) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        // Conversion AX (top-left) → NS (bottom-left) via la hauteur du PRIMARY
        // (celui qui a frame.origin == .zero — pas garanti d'être screens[0] sur
        // configuration multi-display avec écran externe glissé en main dans
        // Réglages Système).
        let primary = screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? screens[0]
        let mainH = primary.frame.height
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

    /// Supprime le root d'un display du workspace (T027 recovery).
    /// Appelé après migration de toutes les fenêtres de cet écran.
    /// Refuse explicitement de supprimer le primary : son root est un invariant
    /// du `Workspace.rootNode` (compat mono-écran FR-024). Pour le primary, on
    /// re-crée un container vide à la place.
    public func clearDisplayRoot(for displayID: CGDirectDisplayID) {
        if displayID == CGMainDisplayID() {
            workspace.rootsByDisplay[displayID] = TilingContainer(orientation: .horizontal)
            return
        }
        workspace.rootsByDisplay[displayID] = nil
    }

    /// Crée un root vide pour un display s'il n'en a pas déjà un (T028 recovery).
    public func initDisplayRoot(for displayID: CGDirectDisplayID) {
        if workspace.rootsByDisplay[displayID] == nil {
            workspace.rootsByDisplay[displayID] = TilingContainer(orientation: .horizontal)
        }
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
    /// - Parameter nearWid: target d'insertion BSP côté dst. Si nil, on prend
    ///   la première leaf existante de dst (≠ wid) pour que le BSP splitte cette
    ///   cellule au lieu de faire un append horizontal au root (= 3+ colonnes flat).
    /// - Returns: true si le wid existait dans l'arbre src et a été transféré.
    @discardableResult
    public func moveWindow(_ wid: WindowID,
                           fromDisplay src: CGDirectDisplayID,
                           toDisplay dst: CGDirectDisplayID,
                           near nearWid: WindowID? = nil) -> Bool {
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
        // Choisir un target d'insertion BSP-friendly : near explicite > première leaf
        // existante du dst. nil → BSP fait un append horizontal au root, ce qui
        // produit 3+ colonnes flat et casse le BSP idiomatique.
        let nearLeaf: WindowLeaf? = nearWid
            .flatMap { TreeNode.find(windowID: $0, in: dstRoot) }
            ?? dstRoot.allLeaves.first(where: { $0.windowID != wid })
        dstTiler.insert(leaf: newLeaf, near: nearLeaf, in: dstRoot)
        logInfo("moveWindow", [
            "wid": String(wid),
            "from": String(src),
            "to": String(dst),
            "near": nearLeaf.map { String($0.windowID) } ?? "nil",
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

    /// Warp `wid` vers la cellule voisine `direction` : retire la feuille de sa
    /// cellule actuelle puis la réinsère `near` la voisine, ce qui demande au tiler
    /// (BSP) de splitter la cellule cible en 2. Différent du `move` qui swap.
    /// - Returns: true si un voisin existait et le warp a eu lieu.
    @discardableResult
    public func warp(_ wid: WindowID, direction: Direction) -> Bool {
        for (_, root) in workspace.rootsByDisplay {
            guard let leaf = TreeNode.find(windowID: wid, in: root) else { continue }
            guard let neighbor = tiler.focusNeighbor(of: leaf, direction: direction, in: root) else {
                return false
            }
            // Le voisin ne doit pas être notre propre feuille (cas pathologique).
            guard neighbor.windowID != wid else { return false }
            let wasVisible = leaf.isVisible
            tiler.remove(leaf: leaf, from: root)
            // remove() peut détacher la leaf ; réutiliser un nouveau wrapper évite
            // tout cycle parent obsolète (pattern identique à moveWindow).
            let newLeaf = WindowLeaf(windowID: wid)
            newLeaf.isVisible = wasVisible
            tiler.insert(leaf: newLeaf, near: neighbor, in: root)
            logInfo("warp", [
                "wid": String(wid),
                "direction": direction.rawValue,
                "near": String(neighbor.windowID),
            ])
            return true
        }
        return false
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
    /// `Display.visibleFrame` vient de `NSScreen` (coords NS, Y bottom-up). On
    /// convertit en AX (Y top-down) avant tiling, sinon `AXReader.setBounds`
    /// place les fenêtres avec un référentiel décalé sur les écrans non-primary.
    /// - Parameter outerSides: marges externes par côté. Si nil, fallback sur
    ///   `display.gapsOuter` uniforme (legacy). Si fourni, prend le pas — utile
    ///   pour appliquer les overrides `gaps_outer_top/bottom/left/right` du toml.
    public func applyAll(displayRegistry: DisplayRegistry,
                         outerSides: OuterGaps? = nil) async {
        let displays = await displayRegistry.displays
        let primaryHeight = LayoutEngine.primaryScreenHeight()
        for display in displays {
            let visibleFrameAX = LayoutEngine.nsToAx(display.visibleFrame, primaryHeight: primaryHeight)
            let gaps = outerSides ?? .uniform(display.gapsOuter)
            let usable = applyOuterGaps(visibleFrameAX, outerGaps: gaps)
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

    // MARK: - NS↔AX conversion

    /// Hauteur du primary screen (origine NS = (0,0)). Utilisée pour convertir NS↔AX.
    private static func primaryScreenHeight() -> CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    /// Convertit un rect NS (Y bottom-up, origine = primary bottom-left) vers AX
    /// (Y top-down, origine = primary top-left). Pour `(x, y, w, h)` NS :
    /// `y_AX = primaryHeight - y_NS - h`.
    private static func nsToAx(_ ns: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: ns.origin.x,
               y: primaryHeight - ns.origin.y - ns.height,
               width: ns.width,
               height: ns.height)
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
    /// Le root primary est garanti présent par l'init du Workspace + le contrat
    /// de `LayoutEngine.clearDisplayRoot(for:)` qui REFUSE de supprimer le
    /// primary (cf. assertion). Le `!` reste sûr par cet invariant.
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
