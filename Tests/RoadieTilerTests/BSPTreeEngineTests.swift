import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

/// SPEC-017 T044 : moteur à arbre (sens de coupe, projection, commandes de split, frontières,
/// taille minimale, arbre déduit de la géométrie).
@Suite
struct BSPTreeEngineTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let container = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func ratio(_ tree: BSPTree) -> Double? {
        guard case .split(_, let r, _, _) = tree else { return nil }
        return r
    }

    private func orientation(_ tree: BSPTree) -> BSPOrientation? {
        guard case .split(let o, _, _, _) = tree else { return nil }
        return o
    }

    private func children(_ tree: BSPTree) -> (BSPTree, BSPTree)? {
        guard case .split(_, _, let f, let s) = tree else { return nil }
        return (f, s)
    }

    private func leftChild(_ tree: BSPTree) -> BSPTree? { children(tree)?.0 }
    private func rightChild(_ tree: BSPTree) -> BSPTree? { children(tree)?.1 }

    // MARK: - Sens de coupe selon la feuille (R3)

    @Test
    func insertionSplitFollowsLeafNotScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        var tree = BSPTree.leaf(win(1))
        for n in 2...5 {
            tree = tree.inserting(win(n), at: win(n - 1), side: .right, in: screen)
        }
        let frames = tree.place(in: screen, innerGap: 0)
        #expect(frames.count == 5)
        // Spirale yabai : colonnes et rangées alternent, jamais de colonne de 1/8 d'écran.
        for frame in frames.values {
            #expect(frame.width > screen.width / 8)
        }
        #expect(frames[win(1)]?.width == 800)
        #expect(frames[win(2)]?.width == 800)
        #expect(frames[win(3)]?.width == 400)
    }

    @Test
    func insertionOnTallLeafStacks() {
        // [w1 | w2] sur 1000x600 : la feuille w2 fait 500x600, elle est coupée en rangées.
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
            .inserting(win(3), at: win(2), side: .right, in: container)
        let right = children(tree)?.1
        #expect(right.flatMap(orientation) == .horizontal)
        #expect(right.flatMap(ratio) == 0.5)
        #expect(tree.windowIDs == [win(1), win(2), win(3)])
    }

    @Test
    func insertionWithoutAnchorSplitsFirstLeafAndEmptyTreeBecomesRoot() {
        #expect(BSPTree.empty.inserting(win(1), at: nil, side: .right, in: container) == .leaf(win(1)))
        let tree = BSPTree.leaf(win(1)).inserting(win(2), at: win(9), side: .left, in: container)
        #expect(tree == .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(1))))
    }

    @Test
    func insertionMeasuresAnchorOnProjection() {
        // [w1 | w2] dans 1200x1000 : w1 mesure 600x1000 (haut) dans l'arbre complet, mais
        // 1200x1000 (large) si w2 est absent. Le sens suit la feuille VISIBLE.
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 1000)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let visible = tree.inserting(win(3), at: win(1), side: .right, in: screen, excluding: [win(2)])
        let full = tree.inserting(win(3), at: win(1), side: .right, in: screen)
        #expect(leftChild(visible).flatMap(orientation) == .vertical)
        #expect(leftChild(full).flatMap(orientation) == .horizontal)
        // Ancre absente : la première feuille VISIBLE est coupée, jamais une feuille absente.
        let skipped = tree.inserting(win(3), at: win(1), side: .right, in: screen, excluding: [win(1)])
        #expect(rightChild(skipped) == .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3))))
    }

    @Test
    func horizontalSplitKeepsTitleBarSeam() {
        let tree = BSPTree.split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let frames = tree.place(in: container, innerGap: 0)
        guard let top = frames[win(1)], let bottom = frames[win(2)] else { Issue.record("frames"); return }
        #expect(bottom.minY - top.maxY == 1)
    }

    // MARK: - Projection et identité des splits (A9)

    @Test
    func projectionRemovesAbsentLeavesAndFoldsUnarySplits() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.3,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let projected = tree.projected(excluding: [win(3)])
        #expect(projected == .split(orientation: .vertical, ratio: 0.3, first: .leaf(win(1)), second: .leaf(win(2))))
        #expect(tree.projected(excluding: []) == tree)
        #expect(tree.projected(excluding: [win(1), win(2), win(3)]) == .empty)
    }

    @Test
    func fenceExcludingAbsentUpdatesMatchingSplitOfFullTree() {
        // [w1 | [w2 / [w3 | w4]]] ; w3 absent → visible [w1 | [w2 / w4]].
        let inner = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(3)), second: .leaf(win(4)))
        let middle = BSPTree.split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: inner)
        let full = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: middle)

        // Geste : le bord haut de w4 (visible en 500x300 à droite) remonte à y = 200.
        let updated = full.adjustingFence(
            of: win(4), edge: .up, to: CGRect(x: 500, y: 200, width: 500, height: 400),
            in: container, excluding: [win(3)]
        )

        // Seul le split [w2 / [w3 | w4]] change ; la racine et le split replié gardent leur ratio.
        guard let (_, newMiddle) = children(updated), let (_, newInner) = children(newMiddle) else {
            Issue.record("structure"); return
        }
        #expect(ratio(updated) == 0.5)
        #expect(abs((ratio(newMiddle) ?? 0) - 199.0 / 599.0) < 0.0001)
        #expect(newInner == inner)
        // La feuille absente n'est jamais perdue.
        #expect(updated.windowIDs == full.windowIDs)
    }

    @Test
    func toggleExcludingAbsentReachesSplitAboveFoldedOne() {
        // [[w1 | w2] / w3] ; w2 absent → visible [w1 / w3] : le parent visible de w1 est la racine.
        let full = BSPTree.split(
            orientation: .horizontal, ratio: 0.5,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))),
            second: .leaf(win(3))
        )
        let updated = full.togglingSplit(of: win(1), excluding: [win(2)])
        #expect(orientation(updated) == .vertical)
        #expect(children(updated)?.0 == children(full)?.0)
        // Sans exclusion, le parent est le split [w1 | w2].
        #expect(leftChild(full.togglingSplit(of: win(1))).flatMap(orientation) == .horizontal)
        #expect(full.settingSplit(of: win(1), to: .vertical, excluding: [win(2)]) == updated)
    }

    @Test
    func resizeDuringAbsenceKeepsRatioWhenNeighbourReturns() {
        // [w1 | [w2 / w3]] ; w3 absent, resize de w1 à 700 px, puis retour de w3.
        let full = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let resized = full.adjustingFence(
            of: win(1), edge: .right, to: CGRect(x: 0, y: 0, width: 700, height: 600),
            in: container, excluding: [win(3)]
        )
        let frames = resized.place(in: container, innerGap: 0)
        #expect(frames[win(1)]?.width == 700)
        #expect(frames[win(2)]?.minX == 700)
        #expect(frames[win(3)]?.minX == 700)
    }

    @Test
    func minimumCorrectionExcludingAbsentMeasuresVisibleGeometry() {
        // [w1 | [w2 / w3]] ; w3 absent : w2 visible fait 500x600, il exige 700 de large.
        let full = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let corrected = full.correctingForMinimumSize(
            of: win(2), minimum: CGSize(width: 700, height: 600), in: container, excluding: [win(3)]
        )
        #expect(corrected?.windowIDs == full.windowIDs)
        let visible = corrected?.projected(excluding: [win(3)]).place(in: container, innerGap: 0)
        #expect((visible?[win(2)]?.width ?? 0) >= 700)
        #expect((visible?[win(2)]?.height ?? 0) == 600)
    }

    // MARK: - Commandes de split (R12)

    @Test
    func balancedResetsEveryRatio() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.8,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.2, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let balanced = tree.balanced()
        #expect(ratio(balanced) == 0.5)
        #expect(rightChild(balanced).flatMap(ratio) == 0.5)
        #expect(balanced.windowIDs == tree.windowIDs)
    }

    @Test
    func toggleAndSetSplitChangeOnlyParentOfWindow() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let toggled = tree.togglingSplit(of: win(3))
        #expect(orientation(toggled) == .vertical)
        #expect(rightChild(toggled).flatMap(orientation) == .vertical)
        #expect(orientation(tree.togglingSplit(of: win(1))) == .horizontal)
        #expect(tree.settingSplit(of: win(2), to: .horizontal) == tree)
        #expect(BSPTree.leaf(win(1)).togglingSplit(of: win(1)) == .leaf(win(1)))
        #expect(tree.togglingSplit(of: win(9)) == tree)
    }

    // MARK: - Frontière (fence)

    @Test
    func adjustingFenceRecomputesRatioFromRequestedFrame() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        // Bord gauche de w2 tiré à x = 400.
        let left = tree.adjustingFence(of: win(2), edge: .left, to: CGRect(x: 400, y: 0, width: 600, height: 600), in: container)
        #expect(abs((ratio(left) ?? 0) - 0.4) < 0.0001)
        // Avec marge de 10 : bord droit de w1 à x = 595 → 595 / 990.
        let right = tree.adjustingFence(of: win(1), edge: .right, to: CGRect(x: 0, y: 0, width: 595, height: 600), in: container, innerGap: 10)
        #expect(abs((ratio(right) ?? 0) - 595.0 / 990.0) < 0.0001)
        #expect(right.place(in: container, innerGap: 10)[win(1)]?.width == 595)
    }

    @Test
    func adjustingFenceIsBoundedAndIgnoresContainerEdge() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let extreme = tree.adjustingFence(of: win(1), edge: .right, to: CGRect(x: 0, y: 0, width: 5000, height: 600), in: container)
        #expect(ratio(extreme) == 0.95)
        // Aucune frontière à gauche de w1 ni en dessous : arbre inchangé.
        #expect(tree.adjustingFence(of: win(1), edge: .left, to: CGRect(x: 100, y: 0, width: 400, height: 600), in: container) == tree)
        #expect(tree.adjustingFence(of: win(1), edge: .down, to: CGRect(x: 0, y: 0, width: 500, height: 300), in: container) == tree)
    }

    // MARK: - Taille minimale (A2)

    @Test
    func fenceRespectsKnownNeighborMinimumAndKeepsAbsentLeavesAndNestedRatios() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.6,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(99))),
            second: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(win(2)), second: .leaf(win(3))))
        let updated = tree.adjustingFence(of: win(2), edge: .left, to: CGRect(x: 200, y: 0, width: 800, height: 180), in: container,
            excluding: [win(99)], knownMinimums: [win(1): CGSize(width: 600, height: 0), win(99): CGSize(width: 9000, height: 9000)])
        #expect(updated == tree)
        #expect(updated.windowIDs.contains(win(99)))
        #expect(updated.projected(excluding: [win(99)]).place(in: container, innerGap: 0)[win(1)]?.width == 600)
    }

    @Test
    func alreadyInfeasibleHeightDoesNotBlockFeasibleWidthResize() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let updated = tree.adjustingFence(of: win(1), edge: .right, to: CGRect(x: 0, y: 0, width: 800, height: 600), in: container,
            knownMinimums: [win(1): CGSize(width: 100, height: 900), win(2): CGSize(width: 200, height: 0)])
        #expect(updated.place(in: container, innerGap: 0)[win(1)]?.width == 800)
        #expect(updated.place(in: container, innerGap: 0)[win(2)]?.width == 200)
    }

    @Test
    func minimumSizeCorrectionAdjustsNearestSplitOnConstrainedAxis() {
        // [[w1 / w2] | w3] : w2 exige 400 de haut → seul le split [w1 / w2] change.
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))),
            second: .leaf(win(3))
        )
        let corrected = tree.correctingForMinimumSize(of: win(2), minimum: CGSize(width: 100, height: 400), in: container)
        let frames = corrected?.place(in: container, innerGap: 0)
        #expect((frames?[win(2)]?.height ?? 0) >= 400)
        #expect(corrected.flatMap(ratio) == 0.5)

        // w1 exige 700 de large → le split racine (vertical) s'ajuste.
        let wide = tree.correctingForMinimumSize(of: win(1), minimum: CGSize(width: 700, height: 10), in: container)
        #expect((wide?.place(in: container, innerGap: 0)[win(1)]?.width ?? 0) >= 700)
    }

    @Test
    func minimumSizeCorrectionHandlesSecondSideAndGap() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let corrected = tree.correctingForMinimumSize(of: win(2), minimum: CGSize(width: 620, height: 0), in: container, innerGap: 10)
        #expect((corrected?.place(in: container, innerGap: 10)[win(2)]?.width ?? 0) >= 620)
    }

    @Test
    func minimumSizeCorrectionRespectsKnownMinimumOfNeighbour() {
        // [w1 | w2] à 0,3 : w1 exige 500 de large, mais w2 descendrait à 500 sous son minimum 600.
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.3, first: .leaf(win(1)), second: .leaf(win(2)))
        let minimum = CGSize(width: 500, height: 0)
        #expect(tree.correctingForMinimumSize(of: win(1), minimum: minimum, in: container,
                                              knownMinimums: [win(2): CGSize(width: 600, height: 0)]) == nil)
        #expect(tree.correctingForMinimumSize(of: win(1), minimum: minimum, in: container,
                                              knownMinimums: [win(2): CGSize(width: 450, height: 0)]) != nil)
    }

    @Test
    func minimumSizeCorrectionAfterAsymmetricSwapBorrowsOnlyRequiredOuterSpace() {
        let screen = CGRect(x: 150, y: 38, width: 1890, height: 1234)
        let t3 = win(53417), terminal = win(64771), neighbour = win(64539)
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.657, first: .leaf(t3),
            second: .split(
                orientation: .horizontal, ratio: 0.5, first: .leaf(win(54112)),
                second: .split(orientation: .vertical, ratio: 0.5,
                               first: .leaf(terminal), second: .leaf(neighbour))))
            .swapping(terminal, t3)
        let before = tree.place(in: screen, innerGap: 10)
        #expect(before[terminal]?.width == 1235)
        #expect(before[t3]?.width == 317)

        let corrected = tree.correctingForMinimumSize(
            of: t3, minimum: CGSize(width: 840, height: 120), in: screen, innerGap: 10,
            knownMinimums: [neighbour: CGSize(width: 120, height: 0)])
        let after = corrected?.place(in: screen, innerGap: 10)
        #expect((after?[t3]?.width ?? 0) >= 840)
        #expect((after?[neighbour]?.width ?? 0) >= 120)
        #expect((after?[terminal]?.width ?? 0) >= 910)
        #expect(corrected?.windowIDs == tree.windowIDs)

        let unknown = tree.correctingForMinimumSize(
            of: t3, minimum: CGSize(width: 840, height: 120), in: screen, innerGap: 10)
        let unknownFrames = unknown?.place(in: screen, innerGap: 10)
        #expect((unknownFrames?[t3]?.width ?? 0) >= 840)
        #expect((unknownFrames?[terminal]?.width ?? 0) >= 985)
        // L'API n'invente pas de minimum pour la voisine : seule la borne de ratio la protège.
        #expect(unknownFrames?[neighbour]?.width == 45)
    }

    @Test
    func minimumSizeCorrectionClimbsToHigherAncestorWhenNearestIsInfeasible() {
        // [w1 | [w2 | w3]] : w3 exige 450 de large. Le split le plus proche donnerait 50 à w2,
        // sous son minimum connu de 200 : les deux splits partagent l'effort, w1 garde 350.
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let corrected = tree.correctingForMinimumSize(
            of: win(3), minimum: CGSize(width: 450, height: 0), in: container,
            knownMinimums: [win(2): CGSize(width: 200, height: 0)]
        )
        let frames = corrected?.place(in: container, innerGap: 0)
        #expect((frames?[win(3)]?.width ?? 0) >= 450)
        #expect((frames?[win(2)]?.width ?? 0) >= 200)
        #expect((frames?[win(1)]?.width ?? 0) >= 350)
        #expect(corrected.flatMap(ratio).map { $0 < 0.5 } == true)

        // Sans minimum connu pour w2, le split le plus proche suffit.
        let nearest = tree.correctingForMinimumSize(of: win(3), minimum: CGSize(width: 450, height: 0), in: container)
        #expect(nearest.flatMap(ratio) == 0.5)
    }

    @Test
    func minimumSizeCorrectionDistributesOnMirroredPath() {
        let screen = CGRect(x: 150, y: 38, width: 1890, height: 1234)
        let t3 = win(1), terminal = win(3), neighbour = win(4)
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.343,
            first: .split(
                orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)),
                second: .split(orientation: .vertical, ratio: 0.5,
                               first: .leaf(neighbour), second: .leaf(terminal))),
            second: .leaf(t3)).swapping(t3, terminal)
        let corrected = tree.correctingForMinimumSize(
            of: t3, minimum: CGSize(width: 840, height: 120), in: screen, innerGap: 10,
            knownMinimums: [neighbour: CGSize(width: 120, height: 0)])
        let frames = corrected?.place(in: screen, innerGap: 10)
        #expect((frames?[t3]?.width ?? 0) >= 840)
        #expect((frames?[terminal]?.width ?? 0) >= 910)
        #expect((frames?[neighbour]?.width ?? 0) >= 120)
        #expect(corrected?.windowIDs == tree.windowIDs)
        #expect(corrected.flatMap(leftChild).flatMap(ratio) == 0.5) // axe orthogonal inchangé
    }

    @Test
    func minimumSizeCorrectionDistributesHeightAndKeepsTitleBarSeams() {
        let tree = BSPTree.split(
            orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5,
                           first: .leaf(win(2)), second: .leaf(win(3))))
        let corrected = tree.correctingForMinimumSize(
            of: win(3), minimum: CGSize(width: 0, height: 400), in: container, innerGap: 0,
            knownMinimums: [win(2): CGSize(width: 0, height: 120)])
        let frames = corrected?.place(in: container, innerGap: 0)
        guard let top = frames?[win(1)], let middle = frames?[win(2)], let bottom = frames?[win(3)] else {
            Issue.record("correction verticale impossible"); return
        }
        #expect(bottom.height >= 400)
        #expect(middle.height >= 120)
        #expect(top.height >= 78)
        #expect(middle.minY - top.maxY == 1)
        #expect(bottom.minY - middle.maxY == 1)
    }

    @Test
    func minimumSizeCorrectionDistributesAcrossThreeAncestorsAndDetectsImpossibleMinimums() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5, first: .leaf(win(1)),
            second: .split(
                orientation: .vertical, ratio: 0.5, first: .leaf(win(2)),
                second: .split(orientation: .vertical, ratio: 0.5,
                               first: .leaf(win(3)), second: .leaf(win(4)))))
        var known = [win(1): CGSize(width: 200, height: 0), win(2): CGSize(width: 150, height: 0),
                     win(3): CGSize(width: 100, height: 0)]
        let corrected = tree.correctingForMinimumSize(
            of: win(4), minimum: CGSize(width: 450, height: 0), in: container, innerGap: 10,
            knownMinimums: known)
        let frames = corrected?.place(in: container, innerGap: 10)
        #expect((frames?[win(1)]?.width ?? 0) >= 270)
        #expect((frames?[win(2)]?.width ?? 0) >= 150)
        #expect((frames?[win(3)]?.width ?? 0) >= 100)
        #expect((frames?[win(4)]?.width ?? 0) >= 450)
        #expect(corrected?.windowIDs == tree.windowIDs)

        known[win(1)] = CGSize(width: 300, height: 0)
        #expect(tree.correctingForMinimumSize(
            of: win(4), minimum: CGSize(width: 450, height: 0), in: container, innerGap: 10,
            knownMinimums: known) == nil)
    }

    @Test
    func minimumSizeCorrectionRespectsFixedNeighbourSubtreeAndAlreadyUndersizedNeighbours() {
        let neighbour = BSPTree.split(orientation: .vertical, ratio: 0.25,
                                      first: .leaf(win(1)), second: .leaf(win(2)))
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5, first: neighbour,
            second: .split(orientation: .vertical, ratio: 0.5,
                           first: .leaf(win(3)), second: .leaf(win(4))))
        var known = [win(1): CGSize(width: 100, height: 0), win(2): CGSize(width: 200, height: 0),
                     win(3): CGSize(width: 120, height: 0)]
        let corrected = tree.correctingForMinimumSize(
            of: win(4), minimum: CGSize(width: 450, height: 0), in: container, innerGap: 10,
            knownMinimums: known)
        let frames = corrected?.place(in: container, innerGap: 10)
        #expect((frames?[win(1)]?.width ?? 0) >= 100)
        #expect((frames?[win(2)]?.width ?? 0) >= 200)
        #expect((frames?[win(3)]?.width ?? 0) >= 120)
        #expect((frames?[win(4)]?.width ?? 0) >= 450)
        #expect(corrected.flatMap(leftChild) == neighbour)
        #expect(tree.correctingForMinimumSize(
            of: win(4), minimum: CGSize(width: 460, height: 0), in: container, innerGap: 10,
            knownMinimums: known) == nil)

        // w2 fait 364, sous le minimum connu de 400. Elle peut rester intacte lors d'un resize local.
        known[win(2)] = CGSize(width: 400, height: 0)
        let local = tree.correctingForMinimumSize(
            of: win(4), minimum: CGSize(width: 300, height: 0), in: container, innerGap: 10,
            knownMinimums: known)
        #expect(local.flatMap(leftChild) == neighbour)
        #expect(local.flatMap(ratio) == 0.5)
        #expect((local?.place(in: container, innerGap: 10)[win(4)]?.width ?? 0) >= 300)
    }

    @Test
    func minimumSizeCorrectionUsesIntegralPlacementAndFractionalGaps() {
        let pair = BSPTree.split(orientation: .vertical, ratio: 0.5,
                                 first: .leaf(win(1)), second: .leaf(win(2)))
        let shifted = CGRect(x: 0.5, y: 0, width: 1000, height: 600)
        let bounded = pair.correctingForMinimumSize(of: win(1), minimum: CGSize(width: 951, height: 0), in: shifted)
        #expect(bounded.flatMap(ratio) == 0.95)
        #expect(bounded?.place(in: shifted, innerGap: 0)[win(1)]?.width == 951)

        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5, first: .leaf(win(1)),
            second: .split(orientation: .vertical, ratio: 0.5,
                           first: .leaf(win(2)), second: .leaf(win(3))))
        let screen = CGRect(x: 0.5, y: 0, width: 1000.25, height: 600)
        let corrected = tree.correctingForMinimumSize(
            of: win(3), minimum: CGSize(width: 450, height: 0), in: screen, innerGap: 10.25,
            knownMinimums: [win(2): CGSize(width: 120, height: 0)])
        let frames = corrected?.place(in: screen, innerGap: 10.25)
        #expect((frames?[win(3)]?.width ?? 0) >= 450)
        #expect((frames?[win(2)]?.width ?? 0) >= 120)
        #expect((frames?[win(1)]?.width ?? 0) >= 410)
    }

    @Test
    func minimumSizeCorrectionPreservesFoldedAbsentSplitDuringDistributedCorrection() {
        let folded = BSPTree.split(orientation: .horizontal, ratio: 0.3,
                                   first: .leaf(win(3)), second: .leaf(win(5)))
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.657, first: .leaf(win(1)),
            second: .split(
                orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)),
                second: .split(orientation: .vertical, ratio: 0.5, first: folded, second: .leaf(win(4)))))
        let screen = CGRect(x: 150, y: 38, width: 1890, height: 1234)
        let corrected = tree.correctingForMinimumSize(
            of: win(3), minimum: CGSize(width: 840, height: 120), in: screen, innerGap: 10,
            excluding: [win(5)], knownMinimums: [win(4): CGSize(width: 120, height: 0),
                                               win(5): CGSize(width: 5000, height: 5000)])
        let frames = corrected?.projected(excluding: [win(5)]).place(in: screen, innerGap: 10)
        #expect((frames?[win(1)]?.width ?? 0) >= 910)
        #expect((frames?[win(3)]?.width ?? 0) >= 840)
        #expect(corrected?.windowIDs == tree.windowIDs)
        #expect(corrected.flatMap(rightChild).flatMap(rightChild).flatMap(leftChild) == folded)
    }

    @Test
    func minimumSizeCorrectionReturnsNilWhenInfeasible() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        // Ratio requis hors bornes.
        #expect(tree.correctingForMinimumSize(of: win(1), minimum: CGSize(width: 990, height: 0), in: container) == nil)
        // Aucun split ne coupe la hauteur.
        #expect(tree.correctingForMinimumSize(of: win(1), minimum: CGSize(width: 0, height: 700), in: container) == nil)
        // Fenêtre absente.
        #expect(tree.correctingForMinimumSize(of: win(9), minimum: .zero, in: container) == nil)
        // Pas de déficit : arbre inchangé.
        #expect(tree.correctingForMinimumSize(of: win(1), minimum: CGSize(width: 300, height: 300), in: container) == tree)
    }

    // MARK: - Arbre déduit de la géométrie (A8)

    private func expectReproduces(_ tree: BSPTree, _ frames: [(WindowID, CGRect?)], gap: CGFloat = 0) {
        let placed = tree.place(in: container, innerGap: gap)
        for case let (id, frame?) in frames {
            guard let got = placed[id] else { Issue.record("missing \(id)"); continue }
            #expect(abs(got.minX - frame.minX) <= 2 && abs(got.minY - frame.minY) <= 2
                && abs(got.width - frame.width) <= 2 && abs(got.height - frame.height) <= 2,
                    "\(id): \(got) != \(frame)")
        }
    }

    @Test
    func inferredDetectsGrid() {
        let frames: [(WindowID, CGRect?)] = [
            (win(1), CGRect(x: 0, y: 0, width: 600, height: 299)),
            (win(2), CGRect(x: 600, y: 0, width: 400, height: 299)),
            (win(3), CGRect(x: 0, y: 300, width: 600, height: 300)),
            (win(4), CGRect(x: 600, y: 300, width: 400, height: 300)),
        ]
        let tree = BSPTree.inferred(from: frames, in: container)
        #expect(orientation(tree) == .horizontal)
        #expect(leftChild(tree).flatMap(orientation) == .vertical)
        #expect(tree.windowIDs == [win(1), win(2), win(3), win(4)])
        expectReproduces(tree, frames)
    }

    @Test
    func inferredDetectsColumnsAndRows() {
        let columns: [(WindowID, CGRect?)] = [
            (win(1), CGRect(x: 0, y: 0, width: 333, height: 600)),
            (win(2), CGRect(x: 333, y: 0, width: 333, height: 600)),
            (win(3), CGRect(x: 666, y: 0, width: 334, height: 600)),
        ]
        let columnTree = BSPTree.inferred(from: columns, in: container)
        #expect(orientation(columnTree) == .vertical)
        expectReproduces(columnTree, columns)

        let rows: [(WindowID, CGRect?)] = [
            (win(1), CGRect(x: 0, y: 0, width: 1000, height: 195)),
            (win(2), CGRect(x: 0, y: 205, width: 1000, height: 195)),
            (win(3), CGRect(x: 0, y: 410, width: 1000, height: 190)),
        ]
        let rowTree = BSPTree.inferred(from: rows, in: container, innerGap: 10)
        #expect(orientation(rowTree) == .horizontal)
        #expect(rowTree.windowIDs == [win(1), win(2), win(3)])
        expectReproduces(rowTree, rows, gap: 10)
    }

    @Test
    func inferredFallsBackInOrderWhenFrameMissingOrUnusable() {
        let missing: [(WindowID, CGRect?)] = [
            (win(3), CGRect(x: 0, y: 0, width: 500, height: 600)),
            (win(1), nil),
            (win(2), CGRect(x: 500, y: 0, width: 500, height: 600)),
        ]
        let fallback = BSPTree.inferred(from: missing, in: container)
        #expect(fallback.windowIDs == [win(3), win(1), win(2)])
        #expect(fallback == BSPTree.empty
            .inserting(win(3), at: nil, side: .right, in: container)
            .inserting(win(1), at: win(3), side: .right, in: container)
            .inserting(win(2), at: win(1), side: .right, in: container))

        let overlapping: [(WindowID, CGRect?)] = [
            (win(1), CGRect(x: 0, y: 0, width: 800, height: 600)),
            (win(2), CGRect(x: 200, y: 0, width: 800, height: 600)),
        ]
        #expect(BSPTree.inferred(from: overlapping, in: container)
            == .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))))

        let offscreen: [(WindowID, CGRect?)] = [
            (win(1), CGRect(x: 0, y: 0, width: 500, height: 600)),
            (win(2), CGRect(x: 3000, y: 0, width: 500, height: 600)),
        ]
        #expect(BSPTree.inferred(from: offscreen, in: container).windowIDs == [win(1), win(2)])
    }

    @Test
    func inferredKeepsEveryMemberOnceAndHandlesEmpty() {
        #expect(BSPTree.inferred(from: [], in: container) == .empty)
        let duplicated: [(WindowID, CGRect?)] = [(win(1), nil), (win(2), nil), (win(1), nil)]
        #expect(BSPTree.inferred(from: duplicated, in: container).windowIDs == [win(1), win(2)])
    }
}
