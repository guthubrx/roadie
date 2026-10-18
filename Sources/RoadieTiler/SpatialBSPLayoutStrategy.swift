import CoreGraphics
import RoadieCore

/// Stratégie de layout BSP à arbre persistant (style yabai/i3). Contrairement à
/// `BSPLayoutStrategy` qui reconstruit un arbre équilibré depuis la liste de fenêtres,
/// celle-ci PLACE les fenêtres selon l'arbre fourni dans `request.bspTree`, qui mémorise
/// la structure exacte (qui a coupé qui). L'insertion/suppression dans l'arbre est gérée
/// en amont (reconciliation côté daemon) ; ici on ne fait que le placement géométrique.
///
/// Le placement se fait sur l'arbre PROJETÉ (SPEC-017 A9) : les feuilles gardées pour des
/// fenêtres absentes de la requête (plein écran natif, autre bureau) sont retirées sans
/// toucher aux autres splits. Filet de sécurité : une fenêtre demandée mais absente de l'arbre
/// (ou arbre absent) y est insérée dans l'ordre, pour ne jamais laisser de fenêtre non placée.
public struct SpatialBSPLayoutStrategy: LayoutStrategy {
    public init() {}

    // O(n) quand toutes les fenêtres ont une feuille (cas normal) ; avant PERF-002, O(n²) :
    // un `contains` récursif par fenêtre. O(n²) au pire avec des insertions de secours
    // (`inserting` est O(n), voir BSPTree) - n = fenêtres du stage, borné.
    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }

        let rect = request.container.inset(by: request.outerGaps)
        let gap = CGFloat(request.innerGap)
        let requested = Set(windows)
        let full = request.bspTree ?? .empty
        let leaves = Set(full.windowIDs)
        var tree = full.projected(excluding: leaves.subtracting(requested))
        // Feuilles de l'arbre projeté = feuilles demandées : un test d'appartenance O(1)
        // remplace le parcours de l'arbre pour chaque fenêtre.
        var present = leaves.intersection(requested)
        var previous: WindowID?
        for id in windows where present.insert(id).inserted {
            tree = tree.inserting(id, at: previous, side: .right, in: rect, innerGap: gap)
            previous = id
        }
        return LayoutPlan(placements: tree.place(in: rect, innerGap: gap))
    }
}
