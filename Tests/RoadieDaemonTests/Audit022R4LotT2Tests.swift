import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 4, lot T2 : PERF-009. La préparation des tailles minimales de la réparation
/// des refus indexe le résultat une seule fois. Les minimums restent identiques à l'ancien calcul,
/// qui reparcourait tous les résultats pour chaque fenêtre.
struct Audit022R4LotT2Tests {
    /// Ancien calcul (helper supprimé), sans la part des refus mémorisés qui n'a pas changé. O(r) par ID.
    private static func referenceMinimum(of id: WindowID, in result: ApplyResult) -> CGSize {
        var size = CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide)
        for item in result.items where item.windowID == id && item.status == .clamped {
            if let actual = item.actual {
                let minimum = LayoutMaintainer.minimumSize(requested: item.requested, actual: actual)
                size = CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
            }
        }
        return size
    }

    /// Même combinaison que resolveInfeasibleClampedScopes : plancher puis index des refus.
    private static func indexedMinimum(of id: WindowID, in index: [WindowID: CGSize]) -> CGSize {
        let floor = CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide)
        let refused = index[id] ?? .zero
        return CGSize(width: max(floor.width, refused.width), height: max(floor.height, refused.height))
    }

    /// Résultat synthétique : plusieurs refus par fenêtre, axes refusés variés, éléments appliqués,
    /// échoués ou clampés sans cadre réel, fenêtres de plusieurs scopes. Déterministe.
    static func syntheticResult(windowCount: Int) -> ApplyResult {
        var items: [ApplyResultItem] = []
        for round in 0..<3 {
            for index in 0..<windowCount {
                let id = WindowID(rawValue: UInt32(index + 1))
                let requested = Rect(x: 0, y: 0, width: Double(200 + index % 7 * 10), height: Double(150 + round * 20))
                let grow = Double((index * 31 + round * 17) % 400)
                switch (index + round) % 5 {
                case 0:
                    items.append(ApplyResultItem(windowID: id, status: .clamped, requested: requested,
                        actual: Rect(x: 0, y: 0, width: requested.width + grow, height: requested.height)))
                case 1:
                    items.append(ApplyResultItem(windowID: id, status: .clamped, requested: requested,
                        actual: Rect(x: 0, y: 0, width: requested.width, height: requested.height + grow)))
                case 2:
                    items.append(ApplyResultItem(windowID: id, status: .clamped, requested: requested, actual: nil))
                case 3:
                    items.append(ApplyResultItem(windowID: id, status: .applied, requested: requested,
                        actual: Rect(x: 0, y: 0, width: requested.width + 900, height: requested.height + 900)))
                default:
                    items.append(ApplyResultItem(windowID: id, status: .failed, requested: requested,
                        actual: Rect(x: 0, y: 0, width: requested.width + 500, height: requested.height + 500)))
                }
            }
        }
        return ApplyResult(attempted: items.count, applied: 0, clamped: 0, failed: 0, items: items)
    }

    @Test(arguments: [10, 100, 1000])
    func indexedRefusedMinimumsMatchPerWindowScan(windowCount: Int) {
        let result = Self.syntheticResult(windowCount: windowCount)
        let index = LayoutMaintainer.refusedMinimumSizes(in: result)

        // IDs absents du résultat compris : ils gardent le plancher.
        for raw in 1...(windowCount + 5) {
            let id = WindowID(rawValue: UInt32(raw))
            #expect(Self.indexedMinimum(of: id, in: index) == Self.referenceMinimum(of: id, in: result))
        }
    }

    @Test
    func refusedMinimumsKeepLargestAxisAcrossRepeatedRefusals() {
        let id = WindowID(rawValue: 7)
        let requested = Rect(x: 0, y: 0, width: 300, height: 200)
        let result = ApplyResult(attempted: 3, applied: 0, clamped: 3, failed: 0, items: [
            ApplyResultItem(windowID: id, status: .clamped, requested: requested,
                            actual: Rect(x: 0, y: 0, width: 640, height: 200)),
            ApplyResultItem(windowID: id, status: .clamped, requested: requested,
                            actual: Rect(x: 0, y: 0, width: 300, height: 480)),
            ApplyResultItem(windowID: id, status: .applied, requested: requested,
                            actual: Rect(x: 0, y: 0, width: 2000, height: 2000))
        ])

        let index = LayoutMaintainer.refusedMinimumSizes(in: result)

        #expect(index[id] == CGSize(width: 640, height: 480))
        #expect(index.count == 1)
    }
}
