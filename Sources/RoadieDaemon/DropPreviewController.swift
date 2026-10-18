import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler

@MainActor
final class DropPreviewController {
    private let engine: DropPreviewEngine
    private let overlay = DropPreviewOverlayWindow()
    private var lastCandidate: DropPreviewCandidate?
    private var dragContext: DropPreviewContext?

    init(engine: DropPreviewEngine = DropPreviewEngine()) {
        self.engine = engine
    }

    var candidate: DropPreviewCandidate? {
        lastCandidate
    }

    /// Fige le snapshot utilise pendant tout le drag (SPEC-016 FR-025) : un seul snapshot au lieu d'un par mouvement.
    /// Un contexte deja pris par l'appelant peut etre transmis pour eviter un second snapshot.
    func beginDrag(context: DropPreviewContext? = nil) {
        dragContext = context ?? engine.makeContext()
    }

    func endDrag() {
        dragContext = nil
        hide()
    }

    /// Snapshot de depart d'un drag de fenetre, partage avec la recherche de la fenetre source.
    func makeContext() -> DropPreviewContext {
        engine.makeContext()
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
        overlay.show(candidate)
        return candidate
    }

    func hide() {
        lastCandidate = nil
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

    /// Mutation de l'arbre de la stage cible pour ce dépôt (SPEC-017 R12), appliquée sur l'état
    /// frais au moment du dépôt. nil sans fenêtre visée.
    var treeMutation: ((BSPTree) -> BSPTree)? {
        guard let targetWindowID else { return nil }
        let (operation, source) = (self.operation, sourceWindowID)
        return { operation.applied(to: $0, source: source, target: targetWindowID) }
    }
}

enum DropPreviewOperation: String, Equatable {
    case append
    case insertLeft
    case insertRight
    case insertUp
    case insertDown
    case swap

    /// Dépôt sur l'arbre (SPEC-017 R12, T092) : échange des feuilles au centre ; sur un bord, la
    /// fenêtre est retirée puis insérée du côté visé de la cible, la coupe suivant ce bord (bord
    /// gauche ou droit : côte à côte, bord haut ou bas : empilées). O(n²) au pire, n borné.
    func applied(to tree: BSPTree, source: WindowID, target: WindowID) -> BSPTree {
        switch self {
        case .swap:
            return tree.swapping(source, target)
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
        default:
            return NSColor.systemGreen
        }
    }
}

struct DropPreviewEngine {
    private let service: SnapshotService

    init(service: SnapshotService = SnapshotService()) {
        self.service = service
    }

    /// Lit l'etat persiste puis le snapshot partage (lecture seule pendant le drag). Cout : au plus un snapshot.
    func makeContext() -> DropPreviewContext {
        let persistedStateBeforeSnapshot = service.effectiveStageStore.state()
        return DropPreviewContext(snapshot: service.sharedSnapshot(), persistedStateBeforeSnapshot: persistedStateBeforeSnapshot)
    }

    func candidate(
        sourceWindowID: WindowID,
        at point: CGPoint,
        displayID forcedDisplayID: DisplayID? = nil,
        context: DropPreviewContext? = nil
    ) -> DropPreviewCandidate? {
        let axPoint = ScreenCoordinate.nsPointToAX(point)
        return candidate(
            sourceWindowID: sourceWindowID,
            atAXPoint: axPoint,
            displayID: forcedDisplayID,
            context: context
        )
    }

    func candidate(
        sourceWindowID: WindowID,
        atAXPoint axPoint: CGPoint,
        displayID forcedDisplayID: DisplayID? = nil,
        context: DropPreviewContext? = nil
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
        if stage.mode.usesTreeEngine {
            return treeCandidate(
                sourceWindowID: sourceWindowID,
                atAXPoint: axPoint,
                display: display,
                scope: scope,
                sourceIsInScope: sourceScope == scope,
                snapshot: snapshot,
                tree: context.persistedStateBeforeSnapshot.bspTree(for: scope) ?? .empty
            )
        }

        let activeEntries = snapshot.windows.filter { entry in
            entry.scope == scope && entry.window.isTileCandidate
        }
        var ordered = service.orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
        if !ordered.contains(sourceWindowID) {
            ordered.append(sourceWindowID)
        }

        let target = activeEntries
            .filter { $0.window.id != sourceWindowID && $0.window.frame.cgRect.contains(axPoint) }
            .sorted { $0.window.frame.cgRect.area < $1.window.frame.cgRect.area }
            .first

        var placements: [WindowID: CGRect] = [:]
        let operation: DropPreviewOperation
        if let target {
            operation = dropOperation(at: axPoint, in: target.window.frame.cgRect, sourceIsActive: activeEntries.contains { $0.window.id == sourceWindowID })
            ordered = reordered(ordered, sourceID: sourceWindowID, targetID: target.window.id, operation: operation)
            placements = structuralPlacements(
                sourceID: sourceWindowID,
                target: target.window,
                operation: operation,
                activeEntries: activeEntries,
                display: display
            ) ?? [:]
        } else {
            operation = .append
            ordered = ordered.filter { $0 != sourceWindowID } + [sourceWindowID]
        }

        let plan = service.layoutPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, priorityWindowIDs: [sourceWindowID])
        if placements.isEmpty {
            placements = plan.placements
        }
        guard let frame = placements[sourceWindowID], !frame.isEmpty else { return nil }
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: ordered,
            placements: Dictionary(uniqueKeysWithValues: placements.map { ($0.key, Rect($0.value.integral)) }),
            frame: frame.integral,
            operation: operation
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
        tree: BSPTree
    ) -> DropPreviewCandidate? {
        // La cible est mesurée avant le transfert : ses smart gaps sont encore ceux du drag.
        let currentGeometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot)
        let currentFrames = currentGeometry?.frames(of: tree) ?? [:]
        let target = currentFrames
            .filter({ $0.key != sourceWindowID && $0.value.contains(axPoint) })
            .min(by: { $0.value.area < $1.value.area })
        let operation: DropPreviewOperation
        let mutated: BSPTree
        let orderedWindowIDs: [WindowID]
        if let target {
            operation = dropOperation(at: axPoint, in: target.value, sourceIsActive: sourceIsInScope && tree.contains(sourceWindowID))
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
        guard let frame = placements[sourceWindowID], !frame.isEmpty else { return nil }
        return DropPreviewCandidate(
            sourceWindowID: sourceWindowID,
            displayID: display.id,
            scope: scope,
            orderedWindowIDs: orderedWindowIDs,
            placements: placements.mapValues { Rect($0.integral) },
            frame: frame.integral,
            operation: operation,
            targetWindowID: target?.key
        )
    }

    private func display(containing point: CGPoint, forcedDisplayID: DisplayID?, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let forced = forcedDisplayID {
            return displays.first { $0.id == forced && $0.frame.cgRect.contains(point) }
        }
        return displays.first { $0.frame.cgRect.contains(point) }
    }

    private func dropOperation(at point: CGPoint, in frame: CGRect, sourceIsActive: Bool) -> DropPreviewOperation {
        let unitX = (point.x - frame.minX) / max(1, frame.width)
        let unitY = (point.y - frame.minY) / max(1, frame.height)
        let edge: CGFloat = 0.28
        if unitX < edge { return .insertLeft }
        if unitX > 1 - edge { return .insertRight }
        if unitY < edge { return .insertUp }
        if unitY > 1 - edge { return .insertDown }
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
        case .insertRight, .insertDown, .append, .swap:
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
        guard operation != .swap, operation != .append else { return nil }
        let horizontal: Bool
        switch operation {
        case .insertLeft, .insertUp:
            horizontal = operation == .insertLeft
        case .insertRight, .insertDown:
            horizontal = operation == .insertRight
        case .append, .swap:
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
        case .append, .swap:
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
        case .append, .swap:
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

    init(
        preview: DropPreviewController,
        commandService: StageCommandService = StageCommandService(),
        events: EventLog = EventLog(),
        userInput: UserInputActivity = .shared,
        dragActivity: WindowDragActivity = .shared
    ) {
        self.preview = preview
        self.commandService = commandService
        self.events = events
        self.userInput = userInput
        self.dragActivity = dragActivity
    }

    var hasActiveDrag: Bool {
        pending != nil
    }

    func activeDraggedWindowIDForDrop() -> WindowID? {
        guard let pending, pending.didDrag else { return nil }
        return pending.windowID
    }

    func cancelPendingDrag() {
        pending = nil
        preview.endDrag()
        dragActivity.release()
    }

    /// Clic sans bande de titre gérée possible (SPEC-051 C-05) : même effet qu'un clic sans
    /// source de glisser, sans construire de contexte ni de relevé.
    func handleMouseDownOutsideTitleBands() {
        preview.hide()
        pending = nil
    }

    func handleMouseDown(at point: CGPoint) {
        preview.hide()
        let context = preview.makeContext()
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
    }

    func handleMouseDragged(to point: CGPoint) {
        guard var drag = pending else { return }
        guard hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) > 8 else { return }
        if !drag.didDrag {
            // Le snapshot pris au mouse-down sert pour tous les mouvements du drag.
            preview.beginDrag(context: drag.context)
        }
        drag.didDrag = true
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
    }

    /// Relâchement d'un glisser (T216). Sans dépôt reconnu, le glisser cesse tout de suite, sans
    /// grâce : le geste suit A17. Un dépôt reconnu consomme la session de geste de ce processus,
    /// applique le dépôt, puis termine le glisser avec sa preuve (`WindowDragActivity.lastDrop`) pour
    /// le maintien d'un autre processus.
    func handleMouseUp(at point: CGPoint) {
        guard let drag = pending else { return }
        pending = nil
        defer { preview.endDrag() }
        guard drag.didDrag,
              let candidate = preview.update(sourceWindowID: drag.windowID, at: point)
        else {
            if drag.didDrag { dragActivity.release() }
            return
        }
        // Dépôt reconnu : il consomme la session de geste, le maintien n'ajuste donc aucune
        // frontière pour ce relâchement (A17).
        _ = userInput.takeGesture()
        defer { dragActivity.finish(droppedWindowID: candidate.sourceWindowID) }
        let result = commandService.place(
            windowID: candidate.sourceWindowID,
            displayID: candidate.displayID,
            orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements,
            treeMutation: candidate.treeMutation
        )
        events.append(RoadieEvent(type: "window_drag_apply", scope: candidate.scope, details: [
            "windowID": String(candidate.sourceWindowID.rawValue),
            "operation": candidate.operation.rawValue,
            "changed": String(result.changed)
        ]))
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
              snapshot.state.activeScope(on: scope.displayID) == scope,
              WindowDragReorderEligibility.accepts(entry.window),
              titleBarHitRect(for: entry.window.frame.cgRect).contains(axPoint)
        else { return nil }
        return (entry.window, scope)
    }

    private nonisolated static func titleBarHitRect(for frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(44, frame.height))
    }
}

private struct PendingWindowDrag {
    var windowID: WindowID
    var displayID: DisplayID
    var startPoint: CGPoint
    var didDrag: Bool
    var lastCandidate: DropPreviewCandidate?
    var context: DropPreviewContext
}

@MainActor
private final class DropPreviewOverlayWindow: NSPanel {
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 5, dy: 5)
        let color = operation.tint
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        color.withAlphaComponent(operation == .swap ? 0.20 : 0.15).setFill()
        path.fill()

        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()

        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 7, yRadius: 7)
        color.withAlphaComponent(0.36).setStroke()
        inner.lineWidth = 1
        inner.stroke()
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
