import Foundation
import ApplicationServices
import AppKit
import RoadieCore

// MARK: - StageDisplayKey

/// Clé composite (stageID, displayID) pour indexer un arbre BSP par stage×écran.
/// Remplace l'index pur displayID qui ne gérait qu'un seul tree par écran.
public struct StageDisplayKey: Hashable, Sendable {
    public let stageID: StageID
    public let displayID: CGDirectDisplayID

    public init(stageID: StageID, displayID: CGDirectDisplayID) {
        self.stageID = stageID
        self.displayID = displayID
    }
}

/// Moteur de layout : applique les frames calculées par un Tiler aux fenêtres AX.
@MainActor
public final class LayoutEngine {
    private let registry: WindowRegistry
    public private(set) var workspace: Workspace
    public var tiler: any Tiler
    /// SPEC-014 T080 (US6) : réserve d'edge gauche par display (px), injectée
    /// dans `outerGaps.left` au moment d'`applyAll`. Mise à jour par
    /// `tiling.reserve`. Restoration → set 0 (ou supprime l'entrée).
    public var leftReserveByDisplay: [CGDirectDisplayID: CGFloat] = [:]

    public init(registry: WindowRegistry, workspaceID: WorkspaceID = .main, strategy: TilerStrategy = .bsp) throws {
        self.registry = registry
        self.workspace = Workspace(id: workspaceID)
        guard let tiler = TilerRegistry.make(strategy) else {
            throw LayoutEngineError.unknownStrategy(strategy)
        }
        self.tiler = tiler
        self.workspace.tilerStrategy = strategy
    }

    // MARK: - Stage active

    /// Définit la stage active. Utilisé par StageManager via LayoutHooks.
    /// SPEC-019 (hotfix switchTo) : garantit aussi que le tree (stageID, primaryDisplay)
    /// SPEC-022 — pure setter legacy (applique à TOUS les displays, compat).
    /// Préférer `setActiveStage(_:displayID:)` qui scope par display.
    public func setActiveStage(_ stageID: StageID?) {
        workspace.activeStageID = stageID
        logInfo("layout_engine_active_stage", ["stage": stageID?.value ?? "nil"])
    }

    /// SPEC-022 — setter per-display. Source de vérité scope-aware. Chaque
    /// display peut afficher une stage différente.
    public func setActiveStage(_ stageID: StageID?, displayID: CGDirectDisplayID) {
        if let v = stageID {
            workspace.activeStageByDisplay[displayID] = v
        } else {
            workspace.activeStageByDisplay.removeValue(forKey: displayID)
        }
        logInfo("layout_engine_active_stage_display", [
            "stage": stageID?.value ?? "nil",
            "display": String(displayID),
        ])
    }

    /// SPEC-022 — garantit que toutes les `wids` passées sont présentes dans le tree
    /// `(activeStageID, displayID)`. Le caller passe un `displayID` explicite (plus
    /// de fallback CGMainDisplayID qui faussait les autres displays).
    /// Idempotent : ne ré-insère pas une wid déjà présente.
    /// - Returns: nb de wids effectivement insérées.
    @discardableResult
    public func ensureTreePopulated(with wids: [WindowID],
                                     displayID: CGDirectDisplayID) -> Int {
        let sid = workspace.activeStageID ?? StageID("1")
        let key = StageDisplayKey(stageID: sid, displayID: displayID)
        let displayRoot = root(for: key)
        let existing = Set(displayRoot.allLeaves.map { $0.windowID })
        var inserted = 0
        var lastInserted: WindowID?
        for wid in wids where !existing.contains(wid) {
            insertWindow(wid, focusedID: lastInserted, displayID: displayID)
            lastInserted = wid
            inserted += 1
        }
        if inserted > 0 {
            logInfo("ensure_tree_populated", [
                "stage": sid.value, "display": String(displayID),
                "inserted": String(inserted), "total": String(wids.count),
            ])
        }
        return inserted
    }

    // MARK: - Helpers multi-display / multi-stage

    /// Retourne le root pour une clé (stageID, displayID), en le créant si absent.
    private func root(for key: StageDisplayKey) -> TilingContainer {
        if let existing = workspace.rootsByStageDisplay[key] { return existing }
        let root = TilingContainer(orientation: .horizontal)
        workspace.rootsByStageDisplay[key] = root
        return root
    }

    /// Retourne le root de la stage active pour un displayID.
    private func activeRoot(for displayID: CGDirectDisplayID) -> TilingContainer {
        let stageID = workspace.activeStageID ?? StageID("1")
        return root(for: StageDisplayKey(stageID: stageID, displayID: displayID))
    }

    /// Cherche dans quel arbre une wid est insérée. Parcourt tous les trees
    /// (toutes les stages × tous les displays) et retourne la clé composite.
    private func keyForWindow(_ wid: WindowID) -> StageDisplayKey? {
        for (key, root) in workspace.rootsByStageDisplay {
            if TreeNode.find(windowID: wid, in: root) != nil { return key }
        }
        return nil
    }

    /// Infère la stageID propriétaire d'une wid : depuis le registry, puis stage active.
    private func stageID(for wid: WindowID) -> StageID {
        if let sid = registry.get(wid)?.stageID { return sid }
        return workspace.activeStageID ?? StageID("1")
    }

    /// Cherche dans quel tree (parmi tous les stages du display) le wid est inséré.
    /// Utilisé pour la migration cross-display déclenchée par un drag manuel.
    public func displayIDForWindow(_ wid: WindowID) -> CGDirectDisplayID? {
        return keyForWindow(wid)?.displayID
    }

    /// Variante publique de `displayIDContaining(point:)` pour usage externe.
    public func displayIDContainingPoint(_ axPoint: CGPoint) -> CGDirectDisplayID? {
        return displayIDContaining(point: axPoint)
    }

    /// Détermine le displayID contenant un point en coords AX (top-left).
    private func displayIDContaining(point axPoint: CGPoint) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
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
    private func currentTiler(for _: CGDirectDisplayID) -> any Tiler {
        return tiler
    }

    // MARK: - Change de stratégie

    /// Change la stratégie au runtime. Reconstruit tous les trees existants.
    public func setStrategy(_ strategy: TilerStrategy) throws {
        guard let newTiler = TilerRegistry.make(strategy) else {
            throw LayoutEngineError.unknownStrategy(strategy)
        }
        var newRoots: [StageDisplayKey: TilingContainer] = [:]
        for (key, oldRoot) in workspace.rootsByStageDisplay {
            let leaves = oldRoot.allLeaves.map { $0.windowID }
            let newRoot = TilingContainer(orientation: .horizontal)
            var lastInserted: WindowLeaf?
            for wid in leaves {
                let leaf = WindowLeaf(windowID: wid)
                newTiler.insert(leaf: leaf, near: lastInserted, in: newRoot)
                lastInserted = leaf
            }
            newRoots[key] = newRoot
        }
        workspace.rootsByStageDisplay = newRoots
        workspace.tilerStrategy = strategy
        tiler = newTiler
        logInfo("tiler_strategy_changed", ["new": strategy.rawValue])
    }

    /// Seed le rect d'écran utilisable pour le primary display.
    public func setScreenRect(_ rect: CGRect) {
        let primaryID = CGMainDisplayID()
        workspace.lastAppliedRectsByDisplay[primaryID] = rect
        workspace.lastAppliedRect = rect
        let key = StageDisplayKey(stageID: workspace.activeStageID ?? StageID("1"),
                                   displayID: primaryID)
        let primaryRoot = root(for: key)
        _ = tiler.layout(rect: rect, root: primaryRoot)
    }

    // MARK: - Insertion / suppression

    /// Insère une fenêtre dans l'arbre de sa stage propriétaire × display.
    public func insertWindow(_ wid: WindowID, focusedID: WindowID?,
                             displayID: CGDirectDisplayID? = nil) {
        let resolved = resolveDisplayID(for: wid, hint: displayID)
        let sid = stageID(for: wid)
        let key = StageDisplayKey(stageID: sid, displayID: resolved)
        let targetRoot = root(for: key)
        if let rect = workspace.lastAppliedRectsByDisplay[resolved] {
            _ = tiler.layout(rect: rect, root: targetRoot)
        } else if let rect = workspace.lastAppliedRect {
            _ = tiler.layout(rect: rect, root: targetRoot)
        }
        let target: WindowLeaf? = focusedID.flatMap { TreeNode.find(windowID: $0, in: targetRoot) }
        let leaf = WindowLeaf(windowID: wid)
        tiler.insert(leaf: leaf, near: target, in: targetRoot)
    }

    /// Déplace une wid d'un tree (ancienne stage) vers un tree (nouvelle stage).
    /// Appelé par LayoutHooks.reassignToStage quand l'utilisateur assigne une wid à une stage.
    public func reassignWindow(_ wid: WindowID, toStage newStageID: StageID) {
        guard let oldKey = keyForWindow(wid),
              let oldRoot = workspace.rootsByStageDisplay[oldKey],
              let leaf = TreeNode.find(windowID: wid, in: oldRoot) else {
            // Wid pas encore dans un tree : insérer directement dans la nouvelle stage.
            let displayID = resolveDisplayID(for: wid, hint: nil)
            let newKey = StageDisplayKey(stageID: newStageID, displayID: displayID)
            let newRoot = root(for: newKey)
            let newLeaf = WindowLeaf(windowID: wid)
            tiler.insert(leaf: newLeaf, near: nil, in: newRoot)
            logInfo("layout_reassign_insert", [
                "wid": String(wid),
                "stage": newStageID.value,
            ])
            return
        }
        guard oldKey.stageID != newStageID else { return }
        let wasVisible = leaf.isVisible
        tiler.remove(leaf: leaf, from: oldRoot)
        let displayID = oldKey.displayID
        let newKey = StageDisplayKey(stageID: newStageID, displayID: displayID)
        let newRoot = root(for: newKey)
        let newLeaf = WindowLeaf(windowID: wid)
        newLeaf.isVisible = wasVisible
        tiler.insert(leaf: newLeaf, near: newRoot.allLeaves.first, in: newRoot)
        logInfo("layout_reassign", [
            "wid": String(wid),
            "from_stage": oldKey.stageID.value,
            "to_stage": newStageID.value,
            "display": String(displayID),
        ])
    }

    /// Détermine le displayID pour un wid.
    private func resolveDisplayID(for wid: WindowID, hint: CGDirectDisplayID?) -> CGDirectDisplayID {
        if let did = hint { return did }
        if let state = registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            if let did = displayIDContaining(point: center) { return did }
        }
        return CGMainDisplayID()
    }

    /// Supprime le root d'un display du workspace.
    /// Adapté pour opérer sur la stage active seulement.
    public func clearDisplayRoot(for displayID: CGDirectDisplayID) {
        let sid = workspace.activeStageID ?? StageID("1")
        let key = StageDisplayKey(stageID: sid, displayID: displayID)
        if displayID == CGMainDisplayID() {
            workspace.rootsByStageDisplay[key] = TilingContainer(orientation: .horizontal)
        } else {
            workspace.rootsByStageDisplay[key] = nil
        }
    }

    /// Crée un root vide pour un display s'il n'en a pas dans la stage active.
    public func initDisplayRoot(for displayID: CGDirectDisplayID) {
        let sid = workspace.activeStageID ?? StageID("1")
        let key = StageDisplayKey(stageID: sid, displayID: displayID)
        if workspace.rootsByStageDisplay[key] == nil {
            workspace.rootsByStageDisplay[key] = TilingContainer(orientation: .horizontal)
        }
    }

    /// SPEC-022 : retire la wid de TOUS les trees où elle pourrait apparaître.
    /// Avant le fix, retournait après le 1er retrait → wids polluant plusieurs
    /// trees (ex: insérée built-in stage 1 au boot, puis assign vers LG sans
    /// nettoyage built-in) restaient dans le tree d'origine et faussaient le
    /// tiling de l'autre display.
    public func removeWindow(_ wid: WindowID) {
        for (_, root) in workspace.rootsByStageDisplay {
            while let leaf = TreeNode.find(windowID: wid, in: root) {
                tiler.remove(leaf: leaf, from: root)
            }
        }
    }

    /// Déplace un wid entre deux displays (cross-display drag).
    /// Préserve la stage propriétaire de la wid.
    @discardableResult
    public func moveWindow(_ wid: WindowID,
                           fromDisplay src: CGDirectDisplayID,
                           toDisplay dst: CGDirectDisplayID,
                           near nearWid: WindowID? = nil) -> Bool {
        let sid = stageID(for: wid)
        let srcKey = StageDisplayKey(stageID: sid, displayID: src)
        guard let srcRoot = workspace.rootsByStageDisplay[srcKey],
              let leaf = TreeNode.find(windowID: wid, in: srcRoot) else { return false }
        let wasVisible = leaf.isVisible
        tiler.remove(leaf: leaf, from: srcRoot)
        let dstKey = StageDisplayKey(stageID: sid, displayID: dst)
        let dstRoot = root(for: dstKey)
        let newLeaf = WindowLeaf(windowID: wid)
        newLeaf.isVisible = wasVisible
        let dstTiler = currentTiler(for: dst)
        let nearLeaf: WindowLeaf? = nearWid
            .flatMap { TreeNode.find(windowID: $0, in: dstRoot) }
            ?? dstRoot.allLeaves.first(where: { $0.windowID != wid })
        dstTiler.insert(leaf: newLeaf, near: nearLeaf, in: dstRoot)
        logInfo("move_window_cross_display", [
            "wid": String(wid),
            "from": String(src),
            "to": String(dst),
            "stage": sid.value,
            "near": nearLeaf.map { String($0.windowID) } ?? "nil",
        ])
        return true
    }

    /// Marque une leaf comme invisible dans n'importe quel tree.
    @discardableResult
    public func setLeafVisible(_ wid: WindowID, _ visible: Bool) -> Bool {
        for (_, root) in workspace.rootsByStageDisplay {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                leaf.isVisible = visible
                return true
            }
        }
        // SPEC-025 FR-008 — log explicite quand le leaf est introuvable.
        // Cause possible : la wid est dans memberWindows mais pas (encore)
        // insérée dans un tree (ex: fenêtre venant d'être créée, ou drift
        // tree vs memberWindows). Le caller doit décider quoi faire (typiquement
        // appeler tree.insertIfMissing, ou laisser le prochain applyLayout gérer).
        logWarn("setLeafVisible_no_leaf_found", [
            "wid": String(wid),
            "visible_requested": String(visible),
            "trees_count": String(workspace.rootsByStageDisplay.count),
        ])
        return false
    }

    /// Reconstruit l'arbre BSP de la stage active sur le primary display.
    public func rebuildTree() {
        let primaryID = CGMainDisplayID()
        let sid = workspace.activeStageID ?? StageID("1")
        let key = StageDisplayKey(stageID: sid, displayID: primaryID)
        let primaryRoot = root(for: key)
        let oldLeaves = primaryRoot.allLeaves
        let snapshots = oldLeaves.map { ($0.windowID, $0.isVisible) }
        workspace.rootsByStageDisplay[key] = TilingContainer(orientation: .horizontal)
        let newRoot = root(for: key)
        var lastInserted: WindowLeaf?
        for (wid, visible) in snapshots {
            let leaf = WindowLeaf(windowID: wid)
            leaf.isVisible = visible
            tiler.insert(leaf: leaf, near: lastInserted, in: newRoot)
            lastInserted = leaf
        }
        logInfo("tree_rebuilt", ["leaves": String(snapshots.count), "stage": sid.value])
    }

    // MARK: - Navigation / resize

    @discardableResult
    public func move(_ wid: WindowID, direction: Direction) -> Bool {
        let sid = workspace.activeStageID ?? StageID("1")
        for (key, root) in workspace.rootsByStageDisplay where key.stageID == sid {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                return tiler.move(leaf: leaf, direction: direction, in: root)
            }
        }
        return false
    }

    public func resize(_ wid: WindowID, direction: Direction, delta: CGFloat) {
        let sid = workspace.activeStageID ?? StageID("1")
        for (key, root) in workspace.rootsByStageDisplay where key.stageID == sid {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                tiler.resize(leaf: leaf, direction: direction, delta: delta, in: root)
                return
            }
        }
    }

    public func focusNeighbor(of wid: WindowID, direction: Direction) -> WindowID? {
        let sid = workspace.activeStageID ?? StageID("1")
        for (key, root) in workspace.rootsByStageDisplay where key.stageID == sid {
            if let leaf = TreeNode.find(windowID: wid, in: root) {
                return tiler.focusNeighbor(of: leaf, direction: direction, in: root)?.windowID
            }
        }
        return nil
    }

    /// Warp `wid` vers la cellule voisine dans la direction donnée.
    @discardableResult
    public func warp(_ wid: WindowID, direction: Direction) -> Bool {
        let activeSID = workspace.activeStageID ?? StageID("1")
        for (key, root) in workspace.rootsByStageDisplay where key.stageID == activeSID {
            guard let leaf = TreeNode.find(windowID: wid, in: root) else { continue }
            let srcDisplayID = key.displayID
            if let displayRect = workspace.lastAppliedRectsByDisplay[srcDisplayID],
               let leafFrame = leaf.lastFrame,
               LayoutEngine.isAtEdge(leafFrame, of: displayRect, direction: direction),
               let dstID = LayoutEngine.adjacentDisplayID(from: srcDisplayID, direction: direction) {
                logInfo("warp_cross_display_edge", [
                    "wid": String(wid),
                    "direction": direction.rawValue,
                    "from": String(srcDisplayID),
                    "to": String(dstID),
                ])
                return moveWindow(wid, fromDisplay: srcDisplayID, toDisplay: dstID, near: nil)
            }
            if let neighbor = tiler.focusNeighbor(of: leaf, direction: direction, in: root),
               neighbor.windowID != wid {
                let wasVisible = leaf.isVisible
                tiler.remove(leaf: leaf, from: root)
                let newLeaf = WindowLeaf(windowID: wid)
                newLeaf.isVisible = wasVisible
                tiler.insert(leaf: newLeaf, near: neighbor, in: root)
                logInfo("warp_intra", [
                    "wid": String(wid),
                    "direction": direction.rawValue,
                    "near": String(neighbor.windowID),
                ])
                return true
            }
            if let dstID = LayoutEngine.adjacentDisplayID(from: srcDisplayID, direction: direction) {
                logInfo("warp_cross_display", [
                    "wid": String(wid),
                    "direction": direction.rawValue,
                    "from": String(srcDisplayID),
                    "to": String(dstID),
                ])
                return moveWindow(wid, fromDisplay: srcDisplayID, toDisplay: dstID, near: nil)
            }
            return false
        }
        return false
    }

    private static func isAtEdge(_ frame: CGRect, of display: CGRect,
                                  direction: Direction) -> Bool {
        let tol: CGFloat = 10
        switch direction {
        case .left:  return frame.minX <= display.minX + tol
        case .right: return frame.maxX >= display.maxX - tol
        case .up:    return frame.minY <= display.minY + tol
        case .down:  return frame.maxY >= display.maxY - tol
        }
    }

    private static func adjacentDisplayID(from srcID: CGDirectDisplayID,
                                          direction: Direction) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        guard let srcScreen = screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == srcID
        }) else { return nil }
        let src = srcScreen.frame
        var best: (distance: CGFloat, id: CGDirectDisplayID)?
        for screen in screens where screen != srcScreen {
            let f = screen.frame
            guard let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { continue }
            var dist: CGFloat = -1
            switch direction {
            case .right:
                let yOverlap = max(0, min(f.maxY, src.maxY) - max(f.minY, src.minY))
                if f.minX >= src.maxX - 1 && yOverlap > 0 { dist = f.minX - src.maxX }
            case .left:
                let yOverlap = max(0, min(f.maxY, src.maxY) - max(f.minY, src.minY))
                if f.maxX <= src.minX + 1 && yOverlap > 0 { dist = src.minX - f.maxX }
            case .up:
                let xOverlap = max(0, min(f.maxX, src.maxX) - max(f.minX, src.minX))
                if f.minY >= src.maxY - 1 && xOverlap > 0 { dist = f.minY - src.maxY }
            case .down:
                let xOverlap = max(0, min(f.maxX, src.maxX) - max(f.minX, src.minX))
                if f.maxY <= src.minY + 1 && xOverlap > 0 { dist = src.minY - f.maxY }
            }
            if dist >= 0 && (best == nil || dist < best!.distance) {
                best = (dist, did)
            }
        }
        return best?.id
    }

    /// Adapte les adaptiveWeight de l'arbre pour refléter une frame imposée manuellement.
    @discardableResult
    public func adaptToManualResize(_ wid: WindowID, newFrame: CGRect, threshold: CGFloat = 5.0) -> Bool {
        for (_, root) in workspace.rootsByStageDisplay {
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

    public func apply(rect: CGRect, gapsOuter: CGFloat = 0, gapsInner: CGFloat = 0) {
        apply(rect: rect, outerGaps: .uniform(Int(gapsOuter)), gapsInner: gapsInner)
    }

    public func apply(rect: CGRect, outerGaps: OuterGaps, gapsInner: CGFloat = 0) {
        let usable = applyOuterGaps(rect, outerGaps: outerGaps)
        let primaryID = CGMainDisplayID()
        workspace.lastAppliedRect = usable
        workspace.lastAppliedRectsByDisplay[primaryID] = usable
        let primaryRoot = activeRoot(for: primaryID)
        let frames = tiler.layout(rect: usable, root: primaryRoot)
        for (wid, frame) in frames {
            guard let element = registry.axElement(for: wid) else { continue }
            let innerFrame = frame.insetBy(dx: gapsInner / 2, dy: gapsInner / 2)
            AXReader.setBounds(element, frame: innerFrame)
            registry.updateFrame(wid, frame: innerFrame)
        }
    }

    // MARK: - Apply multi-display (T014)

    /// Applique le layout sur tous les displays, chacun selon SA stage active.
    /// SPEC-022 — utilise `activeStageByDisplay[display.id]` (per-display) au lieu
    /// d'un scalaire global. Permet à chaque display d'afficher une stage différente
    /// simultanément.
    public func applyAll(displayRegistry: DisplayRegistry,
                         outerSides: OuterGaps? = nil) async {
        let displays = await displayRegistry.displays
        let primaryHeight = LayoutEngine.primaryScreenHeight()
        for display in displays {
            // Stage active spécifique à ce display. Fallback "1" si jamais set.
            let activeSID = workspace.activeStageByDisplay[display.id] ?? StageID("1")
            let visibleFrameAX = LayoutEngine.nsToAx(display.visibleFrame, primaryHeight: primaryHeight)
            var gaps = outerSides ?? .uniform(display.gapsOuter)
            if let reserve = leftReserveByDisplay[display.id], reserve > 0 {
                gaps = OuterGaps(top: gaps.top, bottom: gaps.bottom,
                                 left: gaps.left + Int(reserve), right: gaps.right)
            }
            let usable = applyOuterGaps(visibleFrameAX, outerGaps: gaps)
            let key = StageDisplayKey(stageID: activeSID, displayID: display.id)
            let displayRoot = root(for: key)
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

    private static func primaryScreenHeight() -> CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

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

    // MARK: Stage active

    /// SPEC-022 — stage active **par display**. Source de vérité du tree à layouter
    /// pour chaque display. Avant : scalaire global → tous les displays affichaient
    /// le tree de la même stage, ce qui faussait le rendu multi-display.
    public var activeStageByDisplay: [CGDirectDisplayID: StageID] = [:]

    /// Compat ascendante : retourne la première stage active trouvée (legacy
    /// callers qui n'ont pas encore migré vers per-display). Setter applique
    /// à TOUS les displays connus (compat avec switchTo legacy global).
    public var activeStageID: StageID? {
        get { activeStageByDisplay.values.first }
        set {
            if let v = newValue {
                // Si on a déjà des entries, mettre à jour toutes les valeurs;
                // sinon initialiser primary display.
                if activeStageByDisplay.isEmpty {
                    activeStageByDisplay[CGMainDisplayID()] = v
                } else {
                    for k in activeStageByDisplay.keys { activeStageByDisplay[k] = v }
                }
            } else {
                activeStageByDisplay.removeAll()
            }
        }
    }

    // MARK: Multi-stage × Multi-display

    /// Un arbre BSP par tuple (stageID, displayID). Source de vérité du layout V2.
    public var rootsByStageDisplay: [StageDisplayKey: TilingContainer]

    /// Dernier rect utilisable par display (indépendant de la stage).
    public var lastAppliedRectsByDisplay: [CGDirectDisplayID: CGRect]

    /// Compat mono-écran : dernier rect du primary display.
    public var lastAppliedRect: CGRect?

    // MARK: Compat ascendante — rootsByDisplay (propriété calculée)

    /// Vue filtrée sur la stage active : retourne le tree de chaque display pour
    /// la stage courante. Usage legacy et tests V1 qui accèdent via ce dict.
    public var rootsByDisplay: [CGDirectDisplayID: TilingContainer] {
        get {
            guard let sid = activeStageID else { return [:] }
            var result: [CGDirectDisplayID: TilingContainer] = [:]
            for (key, container) in rootsByStageDisplay where key.stageID == sid {
                result[key.displayID] = container
            }
            return result
        }
        set {
            let sid = activeStageID ?? StageID("1")
            for (displayID, container) in newValue {
                let key = StageDisplayKey(stageID: sid, displayID: displayID)
                rootsByStageDisplay[key] = container
            }
        }
    }

    // MARK: Compat mono-écran (FR-024)

    public var rootNode: TilingContainer {
        get {
            let sid = activeStageID ?? StageID("1")
            let key = StageDisplayKey(stageID: sid, displayID: CGMainDisplayID())
            // Retourner l'existant ou un container vide (sans mutation du dict —
            // le get ne peut pas muter self sur un struct). Le setter fera la vraie insert.
            return rootsByStageDisplay[key] ?? TilingContainer(orientation: .horizontal)
        }
        set {
            let sid = activeStageID ?? StageID("1")
            let key = StageDisplayKey(stageID: sid, displayID: CGMainDisplayID())
            rootsByStageDisplay[key] = newValue
        }
    }

    public var displayID: CGDirectDisplayID { CGMainDisplayID() }

    public init(id: WorkspaceID,
                tilerStrategy: TilerStrategy = .bsp) {
        self.id = id
        self.tilerStrategy = tilerStrategy
        self.floatingWindowIDs = []
        self.rootsByStageDisplay = [:]
        self.lastAppliedRectsByDisplay = [:]
        self.lastAppliedRect = nil
        self.activeStageID = StageID("1")
        // Créer le root primary pour la stage 1 par défaut pour que les accès
        // legacy fonctionnent immédiatement sans nil-check.
        let primaryID = CGMainDisplayID()
        let defaultKey = StageDisplayKey(stageID: StageID("1"), displayID: primaryID)
        self.rootsByStageDisplay[defaultKey] = TilingContainer(orientation: .horizontal)
    }
}
