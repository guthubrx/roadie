import CoreGraphics
import RoadieCore

/// Stratégie de layout BSP à arbre persistant (style yabai/i3). Contrairement à
/// `BSPLayoutStrategy` qui reconstruit un arbre équilibré depuis la liste de fenêtres,
/// celle-ci PLACE les fenêtres selon l'arbre fourni dans `request.bspTree`, qui mémorise
/// la structure exacte (qui a coupé qui). L'insertion/suppression dans l'arbre est gérée
/// en amont (reconciliation côté daemon) ; ici on ne fait que le placement géométrique.
///
/// Repli : si aucun arbre n'est fourni (ou incohérent avec `windowIDs`), on construit un
/// arbre équilibré à la volée pour ne jamais laisser de fenêtre non placée.
public struct SpatialBSPLayoutStrategy: LayoutStrategy {
    public init() {}

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }

        let rect = request.container.inset(by: request.outerGaps)
        let gap = CGFloat(request.innerGap)

        let tree = usableTree(for: request, windows: windows)
        var placements = tree.place(in: rect, innerGap: gap)

        // Filet de sécurité : toute fenêtre demandée mais absente de l'arbre reçoit quand
        // même une place (ne devrait pas arriver après reconciliation, mais évite une
        // fenêtre invisible en cas d'incohérence transitoire).
        let missing = windows.filter { placements[$0] == nil }
        if !missing.isEmpty {
            let fallback = BSPTree.balanced(from: missing, containerIsWide: rect.width >= rect.height)
            for (id, frame) in fallback.place(in: rect, innerGap: gap) {
                placements[id] = frame
            }
        }
        return LayoutPlan(placements: placements)
    }

    private func usableTree(for request: LayoutRequest, windows: [WindowID]) -> BSPTree {
        if let tree = request.bspTree, Set(tree.windowIDs) == Set(windows) {
            return tree
        }
        // Arbre absent ou désynchronisé : repli équilibré déterministe.
        return BSPTree.balanced(from: windows, containerIsWide: request.container.width >= request.container.height)
    }
}
