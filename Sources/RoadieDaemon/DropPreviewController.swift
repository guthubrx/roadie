import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler

@MainActor
final class DropPreviewController {
    private let engine: DropPreviewEngine
    private let live: LiveDropPreview
    private let overlay = DropPreviewOverlayWindow()
    private var lastCandidate: DropPreviewCandidate?
    private var dragContext: DropPreviewContext?
    private var liveEnabled = false

    init(engine: DropPreviewEngine = DropPreviewEngine()) {
        self.engine = engine
        self.live = LiveDropPreview(service: engine.service)
    }

    var candidate: DropPreviewCandidate? {
        lastCandidate
    }
    var snapshotService: SnapshotService { engine.service }
    var isHoldingLayout: Bool { live.isActive }
    var requestsRealSource: Bool { engine.service.effectiveConfig.fx.dropPreview == "real" }
    var pointerConfig: EffectsConfig { engine.service.publishedConfig.fx }
    var requestsPointerCapture: Bool { requestsRealSource || pointerConfig.dragPreview != "none" }
    func isModifierPress(_ event: CGEvent) -> Bool {
        ModifierWindowOperation.resolve(flags: event.flags, config: engine.service.publishedConfig.tiling) != nil
    }

    /// Fige le snapshot utilise pendant tout le drag (SPEC-016 FR-025) : un seul snapshot au lieu d'un par mouvement.
    /// Un contexte deja pris par l'appelant peut etre transmis pour eviter un second snapshot.
    func beginDrag(context: DropPreviewContext? = nil, sourceGestureOwned: Bool = false,
                   allowsLiveUpdates: Bool = true, sourceWindowID: WindowID? = nil, sourceObservedFrame: Rect? = nil) {
        dragContext = context ?? engine.makeContext()
        liveEnabled = allowsLiveUpdates
        if let dragContext, allowsLiveUpdates {
            live.begin(dragContext, sourceGestureOwned: sourceGestureOwned, sourceWindowID: sourceWindowID,
                       sourceObservedFrame: sourceObservedFrame, keepSourceAtOrigin: pointerConfig.dragPreview != "none")
        }
    }

    func endDrag(then action: (@MainActor () -> Void)? = nil) {
        if !liveEnabled, let dragContext {
            live.begin(dragContext)
            live.update(lastCandidate)
        }
        liveEnabled = false
        dragContext = nil
        lastCandidate = nil
        overlay.hide()
        live.finish(then: action)
    }

    func invalidate() { liveEnabled = false; live.invalidate(); dragContext = nil; lastCandidate = nil; overlay.hide() }
    func refreshLivePreview() {
        live.update(lastCandidate)
        if let lastCandidate {
            if live.showsRealSource && lastCandidate.operation != .stackTab {
                overlay.hide()
            } else {
                overlay.show(lastCandidate)
            }
        }
    }

    /// Snapshot de depart d'un drag de fenetre, partage avec la recherche de la fenetre source.
    func makeContext(preferCachedSnapshot: Bool = false) -> DropPreviewContext {
        engine.makeContext(preferCachedSnapshot: preferCachedSnapshot)
    }

    /// Frontière du tap : relevé déjà publié uniquement, jamais de snapshot AX/disque.
    func cachedDragSource(atAXPoint point: CGPoint) -> WindowSnapshot? {
        guard let snapshot = engine.service.cachedGestureSnapshot() else { return nil }
        return WindowDragReorderController.dragSourceWindow(atAXPoint: point, in: snapshot)?.window
    }

    @discardableResult
    func update(
        sourceWindowID: WindowID,
        at point: CGPoint,
        displayID: DisplayID? = nil
    ) -> DropPreviewCandidate? {
        guard let candidate = engine.candidate(
            sourceWindowID: sourceWindowID,
            at: point,
            displayID: displayID,
            context: dragContext
        ) else {
            hide()
            return nil
        }
        lastCandidate = candidate
        live.update(candidate)
        if live.showsRealSource && candidate.operation != .stackTab {
            overlay.hide()
        } else {
            overlay.show(candidate)
        }
        return candidate
    }

    func hide() {
        lastCandidate = nil
        live.update(nil)
        overlay.hide()
    }
}

/// Etat fige au debut d'un drag : snapshot complet et etat persiste lu juste avant.
struct DropPreviewContext {
    var snapshot: DaemonSnapshot
    var persistedStateBeforeSnapshot: PersistentStageState
}

struct DropPreviewCandidate: Equatable {
    var sourceWindowID: WindowID
    var displayID: DisplayID
    var scope: StageScope
    var orderedWindowIDs: [WindowID]
    var placements: [WindowID: Rect]
    var frame: CGRect
    var operation: DropPreviewOperation
    /// Fenêtre visée par le dépôt (nil : dépôt hors de toute fenêtre).
    var targetWindowID: WindowID? = nil
    /// Vrai lorsque la stage cible utilise le moteur à arbre `spatialBsp` (indice visuel `⌥ Onglet`).
    var isTreeMode: Bool = false

    /// Mutation de l'arbre de la stage cible pour ce dépôt (SPEC-017 R12, Spec 165), appliquée sur l'état
    /// frais au moment du dépôt. nil sans fenêtre visée.
    var treeMutation: ((BSPTree) -> BSPTree)? {
        guard let targetWindowID else { return nil }
        let (operation, source) = (self.operation, sourceWindowID)
        return { operation.applied(to: $0, source: source, target: targetWindowID) }
    }

    /// Mutation de groupe d'onglets pour les modes sans arbre (`scrolling`, `masterStack`, `bsp`, Spec 167).
    var groupMutation: ((inout PersistentStageState, StageScope) -> Void)? {
        guard operation == .stackTab, let targetWindowID else { return nil }
        let source = sourceWindowID
        return { state, scope in
            _ = state.stackTab(source, onto: targetWindowID, in: scope)
        }
    }
}

enum DropPreviewOperation: String, Equatable {
    case append
    case insertLeft
    case insertRight
    case insertUp
    case insertDown
    case swap
    case stackTab

    /// Dépôt sur l'arbre (SPEC-017 R12, T092, Spec 165) : échange au centre, empilement en onglet
    /// sur la barre d'onglets ou au centre avec Option, ou découpe sur un bord. O(n²) au pire, n borné.
    func applied(to tree: BSPTree, source: WindowID, target: WindowID) -> BSPTree {
        switch self {
        case .swap:
            return tree.swapping(source, target)
        case .stackTab:
            return tree.stacking(source, onto: target)
        case .append:
            return tree
        case .insertLeft, .insertRight, .insertUp, .insertDown:
            let side: BSPInsertionSide = (self == .insertLeft || self == .insertUp) ? .left : .right
            let sideBySide = self == .insertLeft || self == .insertRight
            return tree.removing(source).inserting(source, nextTo: target, side: side, containerIsWide: sideBySide)
        }
    }

    var tint: NSColor {
        switch self {
        case .swap:
            return NSColor.systemOrange
        case .stackTab:
            return NSColor.systemTeal
        default:
            return NSColor.systemGreen
        }
    }
}

struct DropPreviewEngine {
    let service: SnapshotService

    init(service: SnapshotService = SnapshotService()) {
        self.service = service
    }

    /// Lit l'etat persiste puis le snapshot partage (lecture seule pendant le drag). Cout : au plus un snapshot.
    /// Avec `preferCachedSnapshot` (Lot L), réutilise le relevé déjà publié uniquement s'il est encore valide
    /// (âge, `stateStamp` identique, `config` et génération d'observation non invalidée), sinon retombe sur
    /// `sharedSnapshot()` frais.
    func makeContext(preferCachedSnapshot: Bool = false) -> DropPreviewContext {
        let persistedStateBeforeSnapshot = service.effectiveStageStore.state()
        if preferCachedSnapshot {
            if let cached = service.validCachedSnapshot(followFocus: false), !cached.displays.isEmpty {
                return DropPreviewContext(snapshot: cached, persistedStateBeforeSnapshot: persistedStateBeforeSnapshot)
            }
            return DropPreviewContext(snapshot: service.snapshot(followFocus: false), persistedStateBeforeSnapshot: persistedStateBeforeSnapshot)
        }
        return DropPreviewContext(snapshot: service.sharedSnapshot(), persistedStateBeforeSnapshot: persistedStateBeforeSnapshot)
    }

    func candidate(
        sourceWindowID: WindowID,
        at point: CGPoint,
        displayID forcedDisplayID: DisplayID? = nil,
        context: DropPreviewContext? = nil,
        optionHeld: Bool? = nil
    ) -> DropPreviewCandidate? {
        let axPoint = ScreenCoordinate.nsPointToAX(point)
        return candidate(
            sourceWindowID: sourceWindowID,
            atAXPoint: axPoint,
            displayID: forcedDisplayID,
            context: context,
            optionHeld: optionHeld
        )
    }

    func candidate(
        sourceWindowID: WindowID,
        atAXPoint axPoint: CGPoint,
        displayID forcedDisplayID: DisplayID? = nil,
        context: DropPreviewContext? = nil,
        optionHeld: Bool? = nil
    ) -> DropPreviewCandidate? {
        let context = context ?? makeContext()
        let snapshot = context.snapshot
        guard let display = display(containing: axPoint, forcedDisplayID: forcedDisplayID, in: snapshot.displays),
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope),
              stage.mode != .float,
              let source = snapshot.windows.first(where: { $0.window.id == sourceWindowID }),
              let sourceScope = source.scope,
              snapshot.state.activeScope(on: sourceScope.displayID) == sourceScope,
              WindowDragReorderEligibility.accepts(source.window)
        else { return nil }
        let optionPressed = optionHeld ?? (
            NSEvent.modifierFlags.contains(.option)
            || CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        )
        if stage.mode.usesTreeEngine {
            return treeCandidate(
                sourceWindowID: sourceWindowID,
                atAXPoint: axPoint,
                display: display,
                scope: scope,
                sourceIsInScope: sourceScope == scope,
                snapshot: snapshot,
                tree: context.persistedStateBeforeSnapshot.bspTree(for: scope) ?? .empty,
                optionHeld: optionPressed
            )
        }

        let activeEntries = snapshot.windows.filter { entry in
            entry.scope == scope && entry.window.isTileCandidate
        }
        var ordered = service.orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
        if !ordered.contains(sourceWindowID) {
            ordered.append(sourceWindowID)
        }

        let allowsSlotTabs = stage.mode.supportsSlotTabGroups
        let existingSlotGroups = allowsSlotTabs ? SnapshotService.layoutTabGroups(from: stage.groups) : []
        let ownGroupMembers: Set<WindowID> = Set(
            existingSlotGroups.first(where: { $0.windowIDs.contains(sourceWindowID) })?.windowIDs ?? [sourceWindowID]
        )

        // Spec 167 : détection d'un dépôt direct sur une barre d'onglets de slot existante (`scrolling`, `masterStack`, `bsp`).
        var tabBarTarget: LayoutTabBarPlacement? = nil
        if allowsSlotTabs && !existingSlotGroups.isEmpty {
            let liveIDs = activeEntries.map(\.window.id)
            let clipEdges = SnapshotService.scrollingClipEdges(for: display, among: snapshot.displays)
            let barReq = LayoutRequest(
                scope: scope,
                mode: stage.mode,
                container: display.visibleFrame.cgRect,
                windowIDs: ordered.filter { liveIDs.contains($0) },
                splitPolicy: service.effectiveConfig.tiling.splitPolicy,
                outerGaps: service.effectiveOuterGaps(windowCount: liveIDs.count, display: display),
                innerGap: service.effectiveConfig.tiling.gapsInner,
                masterRatio: service.effectiveConfig.tiling.masterRatio,
                focusedWindowID: stage.focusedWindowID ?? snapshot.focusedWindowID,
                tabbedBarHeight: service.effectiveConfig.tiling.tabbedBarHeight,
                scrollingColumnWidth: service.effectiveConfig.tiling.scrollingColumnWidth,
                scrollingClipsLeft: clipEdges.clipsLeft,
                scrollingClipsRight: clipEdges.clipsRight,
                tabGroups: existingSlotGroups
            )
            tabBarTarget = LayoutTabSlots.tabBarFrames(for: barReq).first { placement in
                placement.barFrame.contains(axPoint) && !placement.windowIDs.contains(sourceWindowID)
            }
        }

        let target: ScopedWindowSnapshot?
        if let tabBarTarget {
            target = activeEntries.first(where: { $0.window.id == tabBarTarget.active })
        } else {
            target = activeEntries
                .filter { $0.window.id != sourceWindowID && $0.window.frame.cgRect.contains(axPoint) }
                .sorted { $0.window.frame.cgRect.area < $1.window.frame.cgRect.area }
                .first
        }

        var placements: [WindowID: CGRect] = [:]
        var stackedTileFrame: CGRect? = nil
        let operation: DropPreviewOperation
        var targetWindowID: WindowID? = nil
        if let target {
            targetWindowID = target.window.id
            if tabBarTarget != nil {
                operation = .stackTab
            } else {
                let visibleTargetFrame = target.window.frame.cgRect.intersection(display.visibleFrame.cgRect)
                let hitFrame = visibleTargetFrame.isEmpty ? target.window.frame.cgRect : visibleTargetFrame
                let rawOp = dropOperation(
                    at: axPoint,
                    in: hitFrame,
                    sourceIsActive: activeEntries.contains { $0.window.id == sourceWindowID },
                    optionHeld: optionPressed,
                    allowsStackTab: allowsSlotTabs,
                    horizontalOnly: stage.mode == .scrolling
                )
                if allowsSlotTabs, ownGroupMembers.contains(target.window.id), (rawOp == .swap || rawOp == .stackTab) {
                    return nil
                }
                operation = rawOp
            }
            if operation == .stackTab, allowsSlotTabs {
                // Aperçu de l'empilement en onglet dans le slot cible
                var previewGroups = existingSlotGroups.compactMap { group -> LayoutTabGroup? in
                    let filtered = group.windowIDs.filter { $0 != sourceWindowID }
                    guard filtered.count >= 2 else { return nil }
                    let active = filtered.contains(group.activeWindowID ?? filtered[0]) ? group.activeWindowID : filtered[0]
                    return LayoutTabGroup(windowIDs: filtered, activeWindowID: active)
                }
                if let idx = previewGroups.firstIndex(where: { $0.windowIDs.contains(target.window.id) }) {
                    previewGroups[idx].windowIDs.append(sourceWindowID)
                    previewGroups[idx].activeWindowID = sourceWindowID
                } else {
                    previewGroups.append(LayoutTabGroup(windowIDs: [target.window.id, sourceWindowID], activeWindowID: sourceWindowID))
                }
                let clipEdges = SnapshotService.scrollingClipEdges(for: display, among: snapshot.displays)
                let previewRequest = LayoutRequest(
                    scope: scope,
                    mode: stage.mode,
                    container: display.visibleFrame.cgRect,
                    windowIDs: ordered,
                    splitPolicy: service.effectiveConfig.tiling.splitPolicy,
                    outerGaps: service.effectiveOuterGaps(windowCount: ordered.count, display: display),
                    innerGap: service.effectiveConfig.tiling.gapsInner,
                    masterRatio: service.effectiveConfig.tiling.masterRatio,
                    focusedWindowID: sourceWindowID,
                    tabbedBarHeight: service.effectiveConfig.tiling.tabbedBarHeight,
                    scrollingColumnWidth: service.effectiveConfig.tiling.scrollingColumnWidth,
                    scrollingClipsLeft: clipEdges.clipsLeft,
                    scrollingClipsRight: clipEdges.clipsRight,
                    tabGroups: previewGroups
                )
                let previewPlan = LayoutPlanner.plan(previewRequest)
                placements = previewPlan.placements
                stackedTileFrame = LayoutTabSlots.tabBarFrames(for: previewRequest)
                    .first(where: { $0.windowIDs.contains(sourceWindowID) })?
                    .tileFrame
            } else {
                ordered = reordered(ordered, sourceID: sourceWindowID, targetID: target.window.id, operation: operation)
                if stage.mode != .scrolling && stage.mode != .tabbed {
                    placements = structuralPlacements(
                        sourceID: sourceWindowID,
                        target: target.window,
                        operation: operation,
                        activeEntries: activeEntries,
                        display: display
                    ) ?? [:]
                }
            }
        } else {
            operation = .append
            ordered = ordered.filter { $0 != sourceWindowID } + [sourceWindowID]
        }

        if placements.isEmpty {
            let plan = service.layoutPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, priorityWindowIDs: [sourceWindowID])
            placements = plan.placements
        }
        guard let placedFrame = placements[sourceWindowID], !placedFrame.isEmpty else { return nil }
        let previewFrame = stackedTileFrame ?? placedFrame
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: ordered,
            placements: Dictionary(uniqueKeysWithValues: placements.map { ($0.key, Rect($0.value.integral)) }),
            frame: previewFrame.integral,
            operation: operation,
            targetWindowID: targetWindowID,
            isTreeMode: allowsSlotTabs
        )
    }

    /// Aperçu sur l'arbre projeté (SPEC-017 R12, T092), en lecture seule : cible et zone de dépôt
    /// sont mesurées sur les frames de l'arbre (la frame transitoire de la fenêtre glissée ne compte
    /// pas), puis l'arbre muté par le dépôt est placé. Rien n'est persisté pendant l'aperçu. Pas de
    /// candidat hors de toute fenêtre du scope d'origine : la fenêtre revient à sa place. Une
    /// projection vide sur un autre scope peut recevoir sa première feuille visible.
    // O(n²) au pire - n = feuilles de l'arbre, borné.
    private func treeCandidate(
        sourceWindowID: WindowID,
        atAXPoint axPoint: CGPoint,
        display: DisplaySnapshot,
        scope: StageScope,
        sourceIsInScope: Bool,
        snapshot: DaemonSnapshot,
        tree: BSPTree,
        optionHeld: Bool
    ) -> DropPreviewCandidate? {
        // La cible est mesurée avant le transfert : ses smart gaps sont encore ceux du drag.
        let currentGeometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot)
        let currentFrames = currentGeometry?.frames(of: tree) ?? [:]
        let projectedTree = tree.projected(excluding: currentGeometry?.absent ?? [])
        let activeIDs = projectedTree.activeWindowIDs
        let ownGroup = Set(projectedTree.tabGroup(containing: sourceWindowID)?.windowIDs ?? [sourceWindowID])

        // Spec 165 : dépôt direct sur la barre d'onglets d'une tuile `.tabGroup` existante -> `.stackTab`.
        let tabBarTarget = currentGeometry?.tabBarFrames(of: tree).first { placement in
            placement.barFrame.contains(axPoint) && !placement.windowIDs.contains(sourceWindowID)
        }

        let target: (key: WindowID, value: CGRect)?
        if let tabBarTarget {
            target = (key: tabBarTarget.active, value: tabBarTarget.tileFrame)
        } else {
            target = currentFrames
                .filter { $0.key != sourceWindowID && $0.value.contains(axPoint) }
                .min { lhs, rhs in
                    if lhs.value.area != rhs.value.area { return lhs.value.area < rhs.value.area }
                    let lhsActive = activeIDs.contains(lhs.key)
                    let rhsActive = activeIDs.contains(rhs.key)
                    if lhsActive != rhsActive { return lhsActive }
                    return lhs.key.rawValue < rhs.key.rawValue
                }
        }

        let operation: DropPreviewOperation
        let mutated: BSPTree
        let orderedWindowIDs: [WindowID]
        if let target {
            if tabBarTarget != nil {
                operation = .stackTab
            } else {
                let rawOperation = dropOperation(
                    at: axPoint,
                    in: target.value,
                    sourceIsActive: sourceIsInScope && tree.contains(sourceWindowID),
                    optionHeld: optionHeld,
                    allowsStackTab: true
                )
                // Glisser un onglet sur le centre de sa propre tuile annule proprement le détachement.
                if ownGroup.contains(target.key), (rawOperation == .swap || rawOperation == .stackTab) {
                    return nil
                }
                operation = rawOperation
            }
            mutated = operation.applied(to: tree, source: sourceWindowID, target: target.key)
            orderedWindowIDs = mutated.windowIDs
        } else {
            guard !sourceIsInScope, currentFrames.isEmpty else { return nil }
            operation = .append
            // Même insertion que le dépôt sans cible (insertionRanked), sans perdre les
            // feuilles historiques. Leur absence est traitée seulement par la projection.
            let rest = tree.removing(sourceWindowID)
            orderedWindowIDs = rest.windowIDs + [sourceWindowID]
            mutated = rest.inserting(
                sourceWindowID, at: rest.windowIDs.last, side: .right,
                in: currentGeometry?.container ?? display.visibleFrame.cgRect,
                innerGap: currentGeometry?.innerGap ?? 0,
                excluding: currentGeometry?.absent ?? []
            )
        }

        // Copie locale uniquement : le dépôt recalculera les mêmes marges avec la source
        // affectée au scope cible. L'état figé et le store restent inchangés pendant le drag.
        var projected = snapshot
        if !sourceIsInScope {
            guard let sourceIndex = projected.windows.firstIndex(where: { $0.window.id == sourceWindowID }) else { return nil }
            do {
                try projected.state.assignWindow(sourceWindowID, to: scope)
            } catch {
                return nil
            }
            projected.windows[sourceIndex].scope = scope
        }
        guard let geometry = service.commandTreeGeometry(for: scope, tree: mutated, in: projected) else { return nil }
        let placements = geometry.frames(of: mutated)
        guard let placedFrame = placements[sourceWindowID], !placedFrame.isEmpty else { return nil }
        let previewFrame: CGRect
        if operation == .stackTab,
           let stackedTile = geometry.tabBarFrames(of: mutated).first(where: { $0.windowIDs.contains(sourceWindowID) })?.tileFrame {
            previewFrame = stackedTile.integral
        } else {
            previewFrame = placedFrame.integral
        }
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs,
            placements: placements.mapValues { Rect($0.integral) },
            frame: previewFrame,
            operation: operation,
            targetWindowID: target?.key,
            isTreeMode: true
        )
    }

    private func display(containing point: CGPoint, forcedDisplayID: DisplayID?, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let forced = forcedDisplayID {
            return displays.first { $0.id == forced && $0.frame.cgRect.contains(point) }
        }
        return displays.first { $0.frame.cgRect.contains(point) }
    }

    private func dropOperation(
        at point: CGPoint,
        in frame: CGRect,
        sourceIsActive: Bool,
        optionHeld: Bool = false,
        allowsStackTab: Bool = false,
        horizontalOnly: Bool = false
    ) -> DropPreviewOperation {
        if allowsStackTab && optionHeld {
            return .stackTab
        }
        let unitX = (point.x - frame.minX) / max(1, frame.width)
        let unitY = (point.y - frame.minY) / max(1, frame.height)
        let edge: CGFloat = 0.28
        if unitX < edge { return .insertLeft }
        if unitX > 1 - edge { return .insertRight }
        if !horizontalOnly {
            if unitY < edge { return .insertUp }
            if unitY > 1 - edge { return .insertDown }
        }
        return sourceIsActive ? .swap : .insertRight
    }

    private func reordered(
        _ orderedWindowIDs: [WindowID],
        sourceID: WindowID,
        targetID: WindowID,
        operation: DropPreviewOperation
    ) -> [WindowID] {
        var result = orderedWindowIDs
        guard let targetIndex = result.firstIndex(of: targetID) else { return result }
        if operation == .swap, let sourceIndex = result.firstIndex(of: sourceID) {
            result.swapAt(sourceIndex, targetIndex)
            return result
        }

        result.removeAll { $0 == sourceID }
        let adjustedTargetIndex = result.firstIndex(of: targetID) ?? min(targetIndex, result.count)
        let insertionIndex: Int
        switch operation {
        case .insertLeft, .insertUp:
            insertionIndex = adjustedTargetIndex
        case .insertRight, .insertDown, .append, .swap, .stackTab:
            insertionIndex = min(adjustedTargetIndex + 1, result.count)
        }
        result.insert(sourceID, at: insertionIndex)
        return result
    }

    private func structuralPlacements(
        sourceID: WindowID,
        target: WindowSnapshot,
        operation: DropPreviewOperation,
        activeEntries: [ScopedWindowSnapshot],
        display: DisplaySnapshot
    ) -> [WindowID: CGRect]? {
        guard operation != .swap, operation != .append, operation != .stackTab else { return nil }
        let horizontal: Bool
        switch operation {
        case .insertLeft, .insertUp:
            horizontal = operation == .insertLeft
        case .insertRight, .insertDown:
            horizontal = operation == .insertRight
        case .append, .swap, .stackTab:
            return nil
        }
        guard let sourceFrame = activeEntries.first(where: { $0.window.id == sourceID })?.window.frame.cgRect,
              let container = union(activeEntries.map { $0.window.frame.cgRect })
        else { return nil }

        let gap = CGFloat(service.innerGap())
        let targetSideIDs = Set(activeEntries.compactMap { entry -> WindowID? in
            guard entry.window.id != sourceID,
                  isOnTargetSide(entry.window.frame.cgRect, from: sourceFrame, operation: operation)
            else { return nil }
            return entry.window.id
        })
        var targetGroupWindows = activeEntries.map(\.window).filter { targetSideIDs.contains($0.id) || $0.id == target.id }
        targetGroupWindows.removeAll { $0.id == sourceID }
        // O(n) : appartenance au groupe cible lue dans l'ensemble, sans recherche linéaire par fenêtre.
        let sourceGroupWindows = activeEntries.map(\.window).filter { entry in
            entry.id != sourceID && entry.id != target.id && !targetSideIDs.contains(entry.id)
        }
        guard !targetGroupWindows.isEmpty, !sourceGroupWindows.isEmpty else { return nil }

        let targetGroup = orderedTargetGroup(
            sourceID: sourceID,
            targetID: target.id,
            peers: spatiallySorted(targetGroupWindows, in: union(targetGroupWindows.map { $0.frame.cgRect }) ?? target.frame.cgRect),
            operation: operation
        )
        let sourceGroup = spatiallySorted(sourceGroupWindows, in: union(sourceGroupWindows.map { $0.frame.cgRect }) ?? sourceFrame)
        let targetFirst = operation == .insertLeft || operation == .insertUp
        let rects = DropGroupGeometry.split(container, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: 1)
        let targetRect = targetFirst ? rects.first : rects.second
        let sourceRect = targetFirst ? rects.second : rects.first

        var result: [WindowID: CGRect] = [:]
        result.merge(DropGroupGeometry.planGroup(targetGroup, in: targetRect, horizontal: !horizontal, gap: gap)) { _, rhs in rhs }
        result.merge(DropGroupGeometry.planGroup(sourceGroup, in: sourceRect, horizontal: !horizontal, gap: gap)) { _, rhs in rhs }
        return result
    }

    private func orderedTargetGroup(sourceID: WindowID, targetID: WindowID, peers: [WindowID], operation: DropPreviewOperation) -> [WindowID] {
        var result = peers.filter { $0 != sourceID }
        guard let targetIndex = result.firstIndex(of: targetID) else {
            return [sourceID] + result
        }
        result.removeAll { $0 == sourceID }
        switch operation {
        case .insertLeft, .insertUp:
            result.insert(sourceID, at: targetIndex)
        case .insertRight, .insertDown:
            result.insert(sourceID, at: min(targetIndex + 1, result.count))
        case .append, .swap, .stackTab:
            result.append(sourceID)
        }
        return result
    }

    private func spatiallySorted(_ windows: [WindowSnapshot], in container: CGRect) -> [WindowID] {
        spatiallySortedWindows(windows, in: container).map(\.id)
    }

    private func spatiallySortedWindows(_ windows: [WindowSnapshot], in container: CGRect) -> [WindowSnapshot] {
        let horizontal = container.width >= container.height
        return windows.sorted { lhs, rhs in
            if horizontal {
                if abs(lhs.frame.cgRect.midX - rhs.frame.cgRect.midX) > 48 {
                    return lhs.frame.cgRect.midX < rhs.frame.cgRect.midX
                }
                return lhs.frame.cgRect.midY < rhs.frame.cgRect.midY
            }
            if abs(lhs.frame.cgRect.midY - rhs.frame.cgRect.midY) > 48 {
                return lhs.frame.cgRect.midY < rhs.frame.cgRect.midY
            }
            return lhs.frame.cgRect.midX < rhs.frame.cgRect.midX
        }
    }

    private func union(_ frames: [CGRect]) -> CGRect? {
        guard var result = frames.first else { return nil }
        for frame in frames.dropFirst() {
            result = result.union(frame)
        }
        return result
    }

    private func isOnTargetSide(_ candidate: CGRect, from source: CGRect, operation: DropPreviewOperation) -> Bool {
        switch operation {
        case .insertLeft:
            return candidate.midX < source.midX
        case .insertRight:
            return candidate.midX > source.midX
        case .insertUp:
            return candidate.midY < source.midY
        case .insertDown:
            return candidate.midY > source.midY
        case .append, .swap, .stackTab:
            return false
        }
    }
}

/// Découpe géométrique d'un groupe de fenêtres pour l'aperçu de dépôt : la première fenêtre
/// prend une part du rectangle, le reste est découpé dans l'orientation alternée.
enum DropGroupGeometry {
    static func split(
        _ rect: CGRect,
        horizontally: Bool,
        gap: CGFloat,
        firstCount: Int,
        secondCount: Int
    ) -> (first: CGRect, second: CGRect) {
        let total = CGFloat(firstCount + secondCount)
        let ratio = total > 0 ? CGFloat(firstCount) / total : 0.5
        if horizontally {
            let usable = max(0, rect.width - gap)
            let firstWidth = floor(usable * ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + gap, y: rect.minY, width: usable - firstWidth, height: rect.height)
            )
        }

        let usable = max(0, rect.height - gap)
        let firstHeight = floor(usable * ratio)
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
            CGRect(x: rect.minX, y: rect.minY + firstHeight + gap, width: rect.width, height: usable - firstHeight)
        )
    }

    /// Passe unique sur un rectangle restant et une orientation alternée. Mêmes découpes que
    /// l'ancienne récursion ; en cas d'identifiant répété, la première occurrence garde sa place.
    // O(n) - n = fenêtres du groupe (avant : O(n²), copie et fusion d'un suffixe à chaque niveau).
    static func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        var placements: [WindowID: CGRect] = [:]
        placements.reserveCapacity(windowIDs.count)
        var remaining = rect
        var isHorizontal = horizontal
        for (index, windowID) in windowIDs.enumerated() {
            let remainingCount = windowIDs.count - index
            let frame: CGRect
            if remainingCount == 1 {
                frame = remaining.integral
            } else {
                let parts = split(remaining, horizontally: isHorizontal, gap: gap, firstCount: 1, secondCount: remainingCount - 1)
                frame = parts.first.integral
                remaining = parts.second
                isHorizontal.toggle()
            }
            if placements[windowID] == nil {
                placements[windowID] = frame
            }
        }
        return placements
    }
}

public enum WindowDragReorderEligibility {
    public static func accepts(_ window: WindowSnapshot) -> Bool {
        guard window.isTileCandidate else { return false }
        if let furniture = window.furniture {
            guard !furniture.isModal else { return false }
            guard furniture.isResizable else { return false }
        }
        if let subrole = window.subrole, subrole != "AXStandardWindow" {
            return false
        }
        return true
    }
}

@MainActor
final class WindowDragReorderController {
    private let preview: DropPreviewController
    private let commandService: StageCommandService
    private let events: EventLog
    private let userInput: UserInputActivity
    private let dragActivity: WindowDragActivity
    private var pending: PendingWindowDrag?
    private var qualification: Task<Void, Never>?
    private var qualificationState: WindowDragQualification?
    private var nativeMovementPassed = false
    private var decisionMade = false
    private var owned = false
    private var draining = false
    private var nativeReleaseSent = false
    private let pointerPreview: DragPointerPreview
    private var pressWindow: WindowSnapshot?
    private var lastDragEvent: CGEvent?
    private var nativeProbe: Task<(CGRect?, Bool), Never>?
    private var nativeProbeStarted = false
    private var nativeObservedFrame: CGRect?
    private var nativeConfirmed = false
    private var adoptionScheduled = false
    private var nativeFallback = false
    private var initialClickState: Int64 = 1
    private var lastActivityRenewal: TimeInterval = 0
    private var pointerSequence: UInt64 = 0
    private var initialAXPoint: CGPoint?
    private var dragPrimaryHeight: CGFloat = 0
    private var queuedDragPoint: CGPoint?
    private var dragDeliveryScheduled = false
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?
    var routeOwnedDrag: ((CGPoint) -> Void)?
    var routeOwnedRelease: ((CGPoint) -> Void)?

    /// Installer uniquement pour le mode réel ; l'échec ne change jamais les permissions.
    func configureMouseCapture() {
        guard preview.requestsPointerCapture else {
            if !owned && !draining { removeMouseCapture() }
            return
        }
        guard mouseTap == nil else { return }
        let mask: CGEventMask = [CGEventType.leftMouseDown, .leftMouseDragged, .mouseMoved, .leftMouseUp, .keyDown, .flagsChanged].reduce(0) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<WindowDragReorderController>.fromOpaque(refcon).takeUnretainedValue()
            let consumed = MainActor.assumeIsolated { controller.capture(type, event: event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            events.append(RoadieEvent(type: "drag.real_unavailable", details: ["reason": "mouse_tap_denied"]))
            return
        }
        mouseTap = tap
        mouseTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), mouseTapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopMouseCapture() { cancelPendingDrag(); removeMouseCapture() }
    private func removeMouseCapture() {
        pointerPreview.end(); nativeProbe?.cancel(); nativeProbe = nil
        if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
        if let mouseTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseTapSource, .commonModes) }
        mouseTapSource = nil; mouseTap = nil
        qualification?.cancel(); qualification = nil
        qualificationState = nil
        pointerSequence &+= 1
        dragDeliveryScheduled = false; queuedDragPoint = nil
        userInput.setCapturedPointerHeld(false)
        owned = false; draining = false; nativeReleaseSent = false
    }

    /// Lot D : ne signaler `drag.real_unprepared` que si le clic visait une barre de titre candidate.
    nonisolated static func shouldReportUnpreparedDrag(nativeMovementPassed: Bool, hasCandidateWindow: Bool) -> Bool {
        !nativeMovementPassed && hasCandidateWindow
    }

    /// Mouvements O(1), clic O(w) sur le relevé publié : aucune lecture AX/disque dans le tap.
    private func capture(_ type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == ModifierWindowGestureController.replayMarker { return false }
        if type == .leftMouseDown, preview.isModifierPress(event) {
            pointerPreview.end(); nativeProbe?.cancel(); nativeProbe = nil
            pointerSequence &+= 1
            qualification?.cancel(); qualification = nil; qualificationState = nil
            pending = nil; owned = false; draining = false; decisionMade = false
            dragDeliveryScheduled = false; queuedDragPoint = nil
            preview.invalidate()
            return false
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pointerSequence &+= 1
            dragDeliveryScheduled = false; queuedDragPoint = nil
            userInput.setCapturedPointerHeld(false)
            owned = false; draining = false; nativeReleaseSent = false
            Task { @MainActor [weak self] in self?.cancelPendingDrag() }
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            return false
        }
        if WindowDragNativeRelease.matches(event) { return false }
        if type == .leftMouseDown {
            pointerSequence &+= 1
            dragDeliveryScheduled = false; queuedDragPoint = nil
            userInput.setCapturedPointerHeld(false)
            pending = nil; decisionMade = false
            pointerPreview.end()
            nativeProbe?.cancel(); nativeProbe = nil; nativeProbeStarted = false
            nativeObservedFrame = nil; nativeConfirmed = false; lastDragEvent = nil
            adoptionScheduled = false; nativeFallback = false; pressWindow = nil
            owned = false; draining = false; nativeReleaseSent = false
            nativeMovementPassed = false
            initialAXPoint = event.location
            initialClickState = event.getIntegerValueField(.mouseEventClickState)
            if let window = preview.cachedDragSource(atAXPoint: event.location) {
                pressWindow = window
                beginQualification(window: window, point: event.location)
            } else {
                qualification?.cancel(); qualification = nil; qualificationState = nil
            }
            return false
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53, owned {
            draining = true
            Task { @MainActor [weak self] in self?.cancelPendingDrag() }
            return true
        }
        if type == .flagsChanged, (owned || pending?.didDrag == true), !draining {
            let point = CGPoint(x: event.location.x, y: dragPrimaryHeight - event.location.y)
            let sequence = pointerSequence
            Task { @MainActor [weak self] in
                guard let self, self.pointerSequence == sequence, self.pending != nil, !self.draining else { return }
                self.routeOwnedDrag?(point)
            }
            return false
        }
        if type == .leftMouseDragged || (type == .mouseMoved && nativeReleaseSent && (owned || draining)) {
            if draining { return true }
            guard let initialAXPoint else { return false }
            if !decisionMade && hypot(event.location.x - initialAXPoint.x, event.location.y - initialAXPoint.y) <= 8 {
                return false
            }
            guard pending != nil else {
                // Lot D : ne journaliser `drag.real_unprepared` que si le clic visait réellement une
                // barre de titre candidate (`pressWindow != nil`). Les glissers ordinaires dans le
                // contenu (sélection de texte, curseurs) ne créent ni tâche MainActor ni événement.
                if Self.shouldReportUnpreparedDrag(nativeMovementPassed: nativeMovementPassed, hasCandidateWindow: pressWindow != nil) {
                    let events = events
                    Task { @MainActor in events.append(RoadieEvent(type: "drag.real_unprepared")) }
                }
                nativeMovementPassed = true; return false
            }
            lastDragEvent = event.copy()
            if !owned {
                if !adoptionScheduled {
                    adoptionScheduled = true
                    let sequence = pointerSequence
                    Task { @MainActor [weak self] in
                        guard let self, self.pointerSequence == sequence else { return }
                        self.adoptionScheduled = false
                        self.startNativeProbe()
                        self.tryAdopt()
                    }
                }
                nativeMovementPassed = true
                return false
            }
            guard owned else { return false }
            let point = CGPoint(x: event.location.x, y: dragPrimaryHeight - event.location.y)
            // Router existant du rail : les dépôts sur miniature restent traités une seule fois.
            queuedDragPoint = point
            if !dragDeliveryScheduled {
                dragDeliveryScheduled = true
                let sequence = pointerSequence
                Task { @MainActor [weak self] in
                    guard let self, self.pointerSequence == sequence else { return }
                    self.dragDeliveryScheduled = false
                    guard self.pending != nil, !self.draining, let point = self.queuedDragPoint else { return }
                    self.queuedDragPoint = nil
                    self.routeOwnedDrag?(point)
                }
            }
            if !nativeReleaseSent {
                nativeReleaseSent = true
                // Terminer le glisser macOS avant le placement AX : sinon sa surface reste
                // liée à l'écran source. Roadie conserve la vraie fin physique séparément.
                WindowDragNativeRelease.finish(event, at: initialAXPoint, clickState: initialClickState)
                return false
            }
            return true
        }
        if type == .leftMouseUp, owned || draining {
            let point = CGPoint(x: event.location.x, y: dragPrimaryHeight - event.location.y)
            let cancelled = draining
            let sequence = pointerSequence
            owned = false; draining = false
            nativeReleaseSent = false
            userInput.setCapturedPointerHeld(false)
            // L'application a déjà reçu sa paire down/up ; ce vrai up clôt seulement Roadie.
            Task { @MainActor [weak self] in
                guard let self, self.pointerSequence == sequence else { return }
                self.queuedDragPoint = nil
                if !cancelled, self.pending?.didDrag == false { self.routeOwnedDrag?(point) }
                self.userInput.mouseUp(leftButton: true)
                if !cancelled { self.routeOwnedRelease?(point) }
            }
            return true
        }
        return false
    }

    /// Le bail partagé protège aussi le tiler d'un autre processus pendant un arrêt du pointeur.
    /// Appelé par le minuteur du rail, jamais depuis le callback de capture.
    func renewOwnedDrag(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard owned, let pending, pending.didDrag else { return }
        // Le minuteur existant du writer invalide les générations/portées périmées.
        // Retirer aussi la copie, sans attendre un nouveau mouvement de souris.
        guard preview.isHoldingLayout else { cancelPendingDrag(); return }
        guard now - lastActivityRenewal >= 0.5 else { return }
        lastActivityRenewal = now
        dragActivity.markActive(windowID: pending.windowID)
    }

    init(
        preview: DropPreviewController,
        commandService: StageCommandService = StageCommandService(),
        events: EventLog = EventLog(),
        userInput: UserInputActivity = .shared,
        dragActivity: WindowDragActivity = .shared,
        pointerPreview: DragPointerPreview? = nil
    ) {
        self.pointerPreview = pointerPreview ?? DragPointerPreview()
        self.preview = preview
        self.commandService = commandService
        self.events = events
        self.userInput = userInput
        self.dragActivity = dragActivity
        self.pointerPreview.onPrepared = { [weak self] in self?.tryAdopt() }
    }

    var hasActiveDrag: Bool {
        pending != nil
    }

    func activeDraggedWindowIDForDrop() -> WindowID? {
        guard let pending, pending.didDrag else { return nil }
        return pending.windowID
    }

    func cancelPendingDrag(then action: (@MainActor () -> Void)? = nil) {
        pointerPreview.end(); nativeProbe?.cancel(); nativeProbe = nil
        qualification?.cancel(); qualification = nil
        if owned { draining = true }
        pending = nil
        dragActivity.release()
        preview.endDrag(then: action)
    }

    /// Clic sans bande de titre gérée possible (SPEC-051 C-05) : même effet qu'un clic sans
    /// source de glisser, sans construire de contexte ni de relevé.
    func handleMouseDownOutsideTitleBands() {
        pointerPreview.end(); nativeProbe?.cancel(); nativeProbe = nil
        qualification?.cancel(); qualification = nil
        qualificationState = nil
        owned = false; draining = false
        userInput.setCapturedPointerHeld(false)
        preview.invalidate()
        pending = nil
    }

    func handleMouseDown(at point: CGPoint) {
        // Les moniteurs AppKit peuvent livrer deux fois le même down. Le tap a déjà
        // retiré pending pour un nouveau clic physique : garder ici sa capture unique.
        if let pending, !pending.didDrag, pending.startPoint == point { return }
        let preparedAt = ProcessInfo.processInfo.systemUptime
        defer {
            events.append(RoadieEvent(type: "drag.real_prepare", details: [
                "windowID": pending.map { String($0.windowID.rawValue) } ?? "none",
                "startedAt": String(preparedAt), "x": String(Double(point.x)), "y": String(Double(point.y))]))
        }
        decisionMade = nativeMovementPassed; owned = false; draining = false
        initialAXPoint = ScreenCoordinate.nsPointToAX(point)
        dragPrimaryHeight = point.y + (initialAXPoint?.y ?? 0)
        preview.invalidate()
        var context = preview.makeContext(preferCachedSnapshot: true)
        // Le vrai glisser peut avoir commencé pendant l'acquisition. Garder sa frame de départ.
        if let pressWindow, let index = context.snapshot.windows.firstIndex(where: {
            $0.window.id == pressWindow.id && $0.window.pid == pressWindow.pid
        }) { context.snapshot.windows[index].window.frame = pressWindow.frame }
        guard let source = sourceWindowForDragStart(at: point, in: context.snapshot) else {
            pending = nil
            return
        }
        pending = PendingWindowDrag(
            windowID: source.window.id,
            displayID: source.scope.displayID,
            startPoint: point,
            didDrag: false,
            context: context
        )
        guard preview.requestsPointerCapture, mouseTap != nil, let initialAXPoint else { return }
        pointerPreview.prepare(window: source.window, anchor: initialAXPoint, config: preview.pointerConfig)
        let window = source.window
        if qualificationState?.matches(window: window, point: initialAXPoint) != true {
            beginQualification(window: window, point: initialAXPoint)
        }
    }

    private func beginQualification(window: WindowSnapshot, point: CGPoint) {
        qualification?.cancel()
        let state = WindowDragQualification(window: window, point: point)
        qualificationState = state
        let worker = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let accepted = WindowTitleDragAccess.accepts(window: window, at: point)
            guard !Task.isCancelled else { return }
            // Publication sans détour par MainActor : un snapshot en préparation ne retarde pas le résultat.
            state.complete(accepted)
        }
        qualification = worker
        Task { [weak self] in
            await worker.value
            guard let self, self.qualificationState === state, let accepted = state.result else { return }
            self.events.append(RoadieEvent(type: "drag.real_qualification", details: [
                "windowID": String(window.id.rawValue), "accepted": String(accepted),
                "decisionMade": String(self.decisionMade),
                "elapsedMS": String(format: "%.1f", ((state.completedAt ?? ProcessInfo.processInfo.systemUptime) - state.started) * 1000),
                "startX": String(Double(point.x)), "startY": String(Double(point.y)),
                "frameX": String(window.frame.x), "frameY": String(window.frame.y)
            ]))
            self.tryAdopt()
        }
    }

    private func startNativeProbe() {
        guard !nativeProbeStarted, let drag = pending, drag.didDrag, let from = initialAXPoint,
              let source = drag.context.snapshot.windows.first(where: { $0.window.id == drag.windowID })?.window else { return }
        nativeProbeStarted = true
        let bounds = drag.context.snapshot.displays.first { $0.id == drag.displayID }?.visibleFrame.cgRect
        let sequence = pointerSequence
        let worker = Task.detached(priority: .userInitiated) { () -> (CGRect?, Bool) in
            var last: CGRect?
            var previous: (CGRect, CGPoint)?
            var matchingSamples = 0
            for _ in 0..<16 {
                guard !Task.isCancelled, CGEventSource.buttonState(.combinedSessionState, button: .left) else { return (nil, false) }
                if let observed = NativeResizeRuntime.visibleFrame(source), let point = CGEvent(source: nil)?.location {
                    last = observed
                    if NativeWindowDragEvidence.followsPointer(initial: source.frame.cgRect, observed: observed, from: from, to: point, constrainedTo: bounds) {
                        return (observed, true)
                    }
                    // Les premières images peuvent être en retard. Deux déplacements
                    // successifs cohérents confirment le drag malgré ce retard initial.
                    if let old = previous {
                        if hypot(observed.minX - old.0.minX, observed.minY - old.0.minY) > 1,
                           hypot(point.x - old.1.x, point.y - old.1.y) > 1 {
                            matchingSamples = NativeWindowDragEvidence.followsPointer(initial: old.0, observed: observed,
                                from: old.1, to: point, constrainedTo: bounds, minimumDistance: 1) ? matchingSamples + 1 : 0
                            previous = (observed, point)
                            if matchingSamples >= 2 { return (observed, true) }
                        }
                    } else { previous = (observed, point) }
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            return (last, false)
        }
        nativeProbe = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self, self.pointerSequence == sequence, self.pending != nil, !self.owned else { return }
            self.nativeObservedFrame = result.0; self.nativeConfirmed = result.1
            self.nativeProbe = nil
            self.events.append(RoadieEvent(type: "drag.native_observed", details: [
                "confirmed": String(result.1), "frame": result.0.map { NSStringFromRect($0) } ?? "nil",
                "titleAccepted": String(self.qualificationState?.result == true)]))
            self.tryAdopt()
        }
    }

    private func tryAdopt() {
        guard !owned, !draining, !nativeFallback, var drag = pending, drag.didDrag,
              let event = lastDragEvent, mouseTap != nil,
              CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
        if pointerPreview.failed {
            nativeFallback = true
            events.append(RoadieEvent(type: "drag.pointer_unavailable", details: ["reason": "capture", "windowID": String(drag.windowID.rawValue)]))
            preview.beginDrag(context: drag.context)
            _ = preview.update(sourceWindowID: drag.windowID, at: ScreenCoordinate.axRectToNS(CGRect(origin: event.location, size: .zero)).origin)
            return
        }
        guard pointerPreview.isReady else { return }
        let initial = drag.context.snapshot.windows.first { $0.window.id == drag.windowID }?.window.frame.cgRect
        let unmoved = initial.flatMap { initial in nativeObservedFrame.map { $0.matchesFrame(initial) } } ?? false
        guard nativeConfirmed || (qualificationState?.result == true && (!nativeMovementPassed || unmoved)) else { return }
        owned = true; decisionMade = true; nativeReleaseSent = true
        userInput.claimExplicitResize(); userInput.setCapturedPointerHeld(true)
        drag.sourceGestureOwned = true; pending = drag
        nativeProbe?.cancel(); nativeProbe = nil
        preview.beginDrag(context: drag.context, sourceGestureOwned: true, sourceWindowID: drag.windowID,
                          sourceObservedFrame: nativeObservedFrame.map(Rect.init))
        pointerPreview.show(at: event.location)
        // La copie est prête avant toute remise en page. Terminer le drag natif au point
        // courant, sans rejouer le clic ni renvoyer la fenêtre au point de départ.
        if let release = event.copy() {
            WindowDragNativeRelease.finish(release, at: event.location, clickState: initialClickState)
            release.post(tap: .cgSessionEventTap)
        }
        let point = ScreenCoordinate.axRectToNS(CGRect(origin: event.location, size: .zero)).origin
        events.append(RoadieEvent(type: "drag.real_adopted", details: ["windowID": String(drag.windowID.rawValue),
            "evidence": nativeConfirmed ? "native_motion" : "title", "pointer": preview.pointerConfig.dragPreview]))
        routeOwnedDrag?(point)
    }

    func handleMouseDragged(to point: CGPoint) {
        guard var drag = pending else { return }
        guard hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) > 8 else { return }
        if !drag.didDrag {
            // Le snapshot pris au mouse-down sert pour tous les mouvements du drag.
            preview.beginDrag(context: drag.context, sourceGestureOwned: drag.sourceGestureOwned,
                              allowsLiveUpdates: !preview.requestsPointerCapture || nativeFallback)
        }
        drag.didDrag = true
        pointerPreview.update(at: ScreenCoordinate.nsPointToAX(point))
        dragActivity.markActive(windowID: drag.windowID)
        if let candidate = preview.update(sourceWindowID: drag.windowID, at: point),
           candidate != drag.lastCandidate {
            events.append(RoadieEvent(type: "window_drag_preview", scope: candidate.scope, details: [
                "windowID": String(candidate.sourceWindowID.rawValue),
                "operation": candidate.operation.rawValue
            ]))
            drag.lastCandidate = candidate
        }
        pending = drag
        if preview.requestsPointerCapture && !owned { startNativeProbe(); tryAdopt() }
    }

    /// Relâchement d'un glisser (T216). Sans dépôt reconnu, le glisser cesse tout de suite, sans
    /// grâce : le geste suit A17. Un dépôt reconnu consomme la session de geste de ce processus,
    /// applique le dépôt, puis termine le glisser avec sa preuve (`WindowDragActivity.lastDrop`) pour
    /// le maintien d'un autre processus.
    func handleMouseUp(at point: CGPoint) {
        pointerPreview.end(); nativeProbe?.cancel(); nativeProbe = nil
        guard let drag = pending else { return }
        pending = nil
        if drag.didDrag, drag.sourceGestureOwned,
           preview.update(sourceWindowID: drag.windowID, at: point) == nil,
           let candidate = Self.floatingDrop(drag: drag, at: point) {
            _ = userInput.takeGesture()
            preview.endDrag { [self] in
                _ = commandService.place(windowID: candidate.sourceWindowID, displayID: candidate.displayID,
                    orderedWindowIDs: candidate.orderedWindowIDs, placements: candidate.placements)
                dragActivity.finish(droppedWindowID: candidate.sourceWindowID)
            }
            return
        }
        guard drag.didDrag,
              let candidate = preview.update(sourceWindowID: drag.windowID, at: point)
        else {
            if drag.didDrag { dragActivity.release() }
            preview.endDrag()
            return
        }
        // Dépôt reconnu : il consomme la session de geste, le maintien n'ajuste donc aucune
        // frontière pour ce relâchement (A17).
        _ = userInput.takeGesture()
        preview.endDrag { [self] in
            let result = commandService.place(
                windowID: candidate.sourceWindowID,
                displayID: candidate.displayID,
                orderedWindowIDs: candidate.orderedWindowIDs,
                placements: candidate.placements,
                treeMutation: candidate.treeMutation,
                groupMutation: candidate.groupMutation
            )
            if candidate.operation == .stackTab {
                _ = WindowCommandService(service: preview.snapshotService).focus(windowID: candidate.sourceWindowID)
            }
            dragActivity.finish(droppedWindowID: candidate.sourceWindowID)
            events.append(RoadieEvent(type: "window_drag_apply", scope: candidate.scope, details: [
                "windowID": String(candidate.sourceWindowID.rawValue),
                "operation": candidate.operation.rawValue,
                "changed": String(result.changed)
            ]))
        }
    }

    private static func floatingDrop(drag: PendingWindowDrag, at point: CGPoint) -> DropPreviewCandidate? {
        let snapshot = drag.context.snapshot, end = ScreenCoordinate.nsPointToAX(point)
        guard let display = snapshot.displays.first(where: { $0.frame.cgRect.contains(end) }),
              let scope = snapshot.state.activeScope(on: display.id),
              snapshot.state.stage(scope: scope)?.mode == .float,
              let source = snapshot.windows.first(where: { $0.window.id == drag.windowID }) else { return nil }
        let start = ScreenCoordinate.nsPointToAX(drag.startPoint)
        let frame = source.window.frame.cgRect.offsetBy(dx: end.x - start.x, dy: end.y - start.y)
        let members = snapshot.windows.filter { $0.scope == scope && $0.window.id != drag.windowID }
        var placements = Dictionary(members.map { ($0.window.id, $0.window.frame) }, uniquingKeysWith: { a, _ in a })
        placements[drag.windowID] = Rect(frame)
        return DropPreviewCandidate(sourceWindowID: drag.windowID, displayID: display.id, scope: scope,
            orderedWindowIDs: members.map { $0.window.id } + [drag.windowID], placements: placements, frame: frame, operation: .append)
    }

    private func sourceWindowForDragStart(at point: CGPoint, in snapshot: DaemonSnapshot) -> (window: WindowSnapshot, scope: StageScope)? {
        Self.dragSourceWindow(atAXPoint: ScreenCoordinate.nsPointToAX(point), in: snapshot)
    }

    /// Fenêtre dont la bande de titre est visible sous le point : la première fenêtre vue dans
    /// l'ordre CoreGraphics doit être éligible et le point doit tomber dans sa bande de titre. Une
    /// bande de titre recouverte par le contenu d'une autre fenêtre ne démarre aucun glisser.
    // O(n) - n = fenêtres du snapshot (avant : filtre puis tri par surface, O(n log n)).
    nonisolated static func dragSourceWindow(atAXPoint axPoint: CGPoint, in snapshot: DaemonSnapshot) -> (window: WindowSnapshot, scope: StageScope)? {
        guard let entry = FocusFollowsMousePicker.frontWindow(at: axPoint, in: snapshot),
              let scope = entry.scope,
              entry.pin == nil, entry.window.furniture?.isNativeFullscreen != true,
              snapshot.state.activeScope(on: scope.displayID) == scope,
              WindowDragReorderEligibility.accepts(entry.window),
              titleBarHitRect(for: entry.window.frame.cgRect).contains(axPoint)
        else { return nil }
        return (entry.window, scope)
    }

    private nonisolated static func titleBarHitRect(for frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(WindowTitleDragAccess.titleBarHeight, frame.height))
    }
}

/// Fin interne du glisser macOS ; distincte du relâchement physique suivi par Roadie.
enum WindowDragNativeRelease {
    private static let marker: Int64 = 0x524F414449453134
    static func matches(_ event: CGEvent?) -> Bool {
        event?.type == .leftMouseUp && event?.getIntegerValueField(.eventSourceUserData) == marker
    }
    static func finish(_ event: CGEvent, at origin: CGPoint, clickState: Int64) {
        event.type = .leftMouseUp
        event.location = origin
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }
}

/// Résultat unique d'une lecture AX : producteur hors main, lecteur dans le tap. O(1).
final class WindowDragQualification: @unchecked Sendable {
    let window: WindowSnapshot
    let point: CGPoint
    let started = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var storedResult: Bool?
    private var finishedAt: TimeInterval?
    init(window: WindowSnapshot, point: CGPoint) { self.window = window; self.point = point }
    var result: Bool? { lock.withLock { storedResult } }
    var completedAt: TimeInterval? { lock.withLock { finishedAt } }
    func complete(_ accepted: Bool) { lock.withLock { storedResult = accepted; finishedAt = ProcessInfo.processInfo.systemUptime } }
    func matches(window other: WindowSnapshot, point otherPoint: CGPoint) -> Bool {
        window.id == other.id && window.pid == other.pid
            && hypot(point.x - otherPoint.x, point.y - otherPoint.y) <= 1
            && abs(window.frame.x - other.frame.x) <= 8 && abs(window.frame.y - other.frame.y) <= 8
            && abs(window.frame.width - other.frame.width) <= 1 && abs(window.frame.height - other.frame.height) <= 1
    }
}

private struct PendingWindowDrag {
    var windowID: WindowID
    var displayID: DisplayID
    var startPoint: CGPoint
    var didDrag: Bool
    var sourceGestureOwned = false
    var lastCandidate: DropPreviewCandidate?
    var context: DropPreviewContext
}

@MainActor
final class DropPreviewOverlayWindow: NSPanel {
    private let previewView = DropPreviewOverlayView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        colorSpace = .sRGB
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        alphaValue = 0.92
        contentView = previewView
    }

    func show(_ candidate: DropPreviewCandidate) {
        let frame = ScreenCoordinate.axRectToNS(candidate.frame).insetBy(dx: -5, dy: -5)
        previewView.operation = candidate.operation
        previewView.isTreeMode = candidate.isTreeMode
        setFrame(frame, display: true)
        orderFrontRegardless()
        previewView.needsDisplay = true
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
private final class DropPreviewOverlayView: NSView {
    var operation: DropPreviewOperation = .append
    var isTreeMode: Bool = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 5, dy: 5)
        let color = operation.tint
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        color.withAlphaComponent(operation == .swap || operation == .stackTab ? 0.20 : 0.15).setFill()
        path.fill()

        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()

        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 7, yRadius: 7)
        color.withAlphaComponent(0.36).setStroke()
        inner.lineWidth = 1
        inner.stroke()

        if operation == .stackTab, rect.width >= 120, rect.height >= 90 {
            // Bandeau supérieur simulant la barre d'onglets de la tuile (AppKit : y croît vers le haut).
            let barHeight: CGFloat = min(26, max(18, rect.height * 0.12))
            let barRect = NSRect(
                x: rect.minX + 6,
                y: rect.maxY - barHeight - 6,
                width: rect.width - 12,
                height: barHeight
            )
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 6, yRadius: 6)
            color.withAlphaComponent(0.35).setFill()
            barPath.fill()
            color.withAlphaComponent(0.85).setStroke()
            barPath.lineWidth = 1.5
            barPath.stroke()

            let pillWidth = max(24, (barRect.width - 14) / 2)
            let leftPill = NSRect(x: barRect.minX + 4, y: barRect.minY + 3, width: pillWidth, height: barRect.height - 6)
            let rightPill = NSRect(x: leftPill.maxX + 6, y: barRect.minY + 3, width: pillWidth, height: barRect.height - 6)
            color.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: leftPill, xRadius: 4, yRadius: 4).fill()
            color.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: rightPill, xRadius: 4, yRadius: 4).fill()

            drawBadge(tr("Empiler en onglet", "Stack as tab"), in: rect, color: color)
        } else if operation == .swap, isTreeMode, rect.width >= 140, rect.height >= 70 {
            drawBadge(tr("Échanger · ⌥ Onglet", "Swap · ⌥ Tab"), in: rect, color: color)
        }
    }

    private func drawBadge(_ text: String, in rect: NSRect, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padX: CGFloat = 14
        let padY: CGFloat = 6
        let badgeRect = NSRect(
            x: rect.midX - (size.width + padX * 2) / 2,
            y: rect.midY - (size.height + padY * 2) / 2,
            width: size.width + padX * 2,
            height: size.height + padY * 2
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.68).setFill()
        badgePath.fill()
        color.withAlphaComponent(0.95).setStroke()
        badgePath.lineWidth = 1.5
        badgePath.stroke()
        let textOrigin = NSPoint(x: badgeRect.minX + padX, y: badgeRect.minY + padY)
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

private enum ScreenCoordinate {
    static func nsPointToAX(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func axRectToNS(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }
}
