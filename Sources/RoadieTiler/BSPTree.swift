import CoreGraphics
import RoadieCore

/// Orientation d'un nœud de split BSP.
/// - `vertical` : les deux enfants sont côte à côte (séparation verticale), `first` à gauche.
/// - `horizontal` : les deux enfants sont empilés (séparation horizontale), `first` en haut.
public enum BSPOrientation: String, Codable, Equatable, Sendable {
    case vertical
    case horizontal
}

/// Côté d'insertion d'une nouvelle fenêtre par rapport à la feuille qu'elle divise.
public enum BSPInsertionSide: String, Codable, Equatable, Sendable {
    case right   // nouvelle fenêtre en second (droite/bas)
    case left    // nouvelle fenêtre en premier (gauche/haut)
}

/// Bord d'une fenêtre, pour désigner la frontière (fence) à déplacer. Mêmes valeurs brutes que
/// `Direction` (RoadieDaemon) : `BSPEdge(rawValue: direction.rawValue)` convertit sans table.
public enum BSPEdge: String, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

/// Arbre BSP persistant (style yabai/i3). Chaque nœud interne (`split`) coupe l'espace
/// en deux selon une orientation et un ratio ; chaque feuille (`leaf`) porte une fenêtre.
/// Contrairement aux stratégies dérivées d'une liste, cet arbre MÉMORISE la structure :
/// une nouvelle fenêtre divise uniquement la feuille focalisée, le reste ne bouge pas.
///
/// Identité des splits (SPEC-017 A9) : aucun identifiant n'est stocké (format JSON de
/// `stages.json` inchangé). Un split est identifié par la première feuille de chacun de ses
/// deux côtés : leur ancêtre commun le plus bas est ce split, dans l'arbre complet comme dans
/// toute projection où il survit. Les opérations qui prennent `excluding:` calculent sur la
/// projection puis reportent orientation et ratio sur l'arbre complet par cette identité.
///
/// Complexité (Article XVIII) : `place`, `windowIDs`, `contains`, `removing`, `projected` et
/// `balanced` sont O(n) sur le nombre de feuilles. `inserting`, `togglingSplit`, `settingSplit`
/// et `adjustingFence` sont O(n²) au pire (un `contains` par niveau pendant la descente),
/// `correctingForMinimumSize` O(d·n + n·log L) (d = profondeur, L = étendue de l'écran en points).
/// n = fenêtres d'un stage, BORNÉ par
/// construction (typiquement < 20, plafond observé ~50) → au pire ~2500 opérations, hors hot
/// path serré. Compromis accepté : la lisibilité d'un arbre immuable récursif prime sur une
/// optimisation non nécessaire à cette échelle.
public indirect enum BSPTree: Equatable, Codable, Sendable {
    case empty
    case leaf(WindowID)
    case split(orientation: BSPOrientation, ratio: Double, first: BSPTree, second: BSPTree)

    // MARK: - Lecture

    /// Feuilles dans l'ordre de parcours (first avant second) = gauche→droite, haut→bas.
    // O(n) - un seul accumulateur ; avant, `first.windowIDs + second.windowIDs` recopiait les
    // tableaux à chaque niveau (O(n²) sur un arbre en chaîne).
    public var windowIDs: [WindowID] {
        var result: [WindowID] = []
        appendWindowIDs(to: &result)
        return result
    }

    private func appendWindowIDs(to result: inout [WindowID]) {
        switch self {
        case .empty:
            break
        case .leaf(let id):
            result.append(id)
        case .split(_, _, let first, let second):
            first.appendWindowIDs(to: &result)
            second.appendWindowIDs(to: &result)
        }
    }

    public func contains(_ windowID: WindowID) -> Bool {
        switch self {
        case .empty:
            return false
        case .leaf(let id):
            return id == windowID
        case .split(_, _, let first, let second):
            return first.contains(windowID) || second.contains(windowID)
        }
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    // MARK: - Placement

    /// Calcule la frame de chaque fenêtre en répartissant `rect` selon l'arbre.
    /// `innerGap` est l'espace laissé entre deux enfants d'un split.
    public func place(in rect: CGRect, innerGap: CGFloat) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        place(in: rect, innerGap: innerGap, into: &result)
        return result
    }

    private func place(in rect: CGRect, innerGap: CGFloat, into result: inout [WindowID: CGRect]) {
        switch self {
        case .empty:
            return
        case .leaf(let id):
            result[id] = rect.integral
        case .split(let orientation, let ratio, let first, let second):
            let rects = Self.childRects(of: rect, orientation: orientation, ratio: ratio, innerGap: innerGap)
            first.place(in: rects.first, innerGap: innerGap, into: &result)
            second.place(in: rects.second, innerGap: innerGap, into: &result)
        }
    }

    /// Bornes du ratio appliqué au placement (et des ratios calculés depuis une frame).
    static let ratioBounds: ClosedRange<Double> = 0.05...0.95

    /// Écart minimal entre deux fenêtres empilées : la barre de titre du bas ne touche pas la
    /// fenêtre du haut (même valeur que `BSPLayoutStrategy.titleBarSeamGap`).
    static let titleBarSeamGap: CGFloat = 1

    /// Étendue minimale (points) gardée par chaque enfant quand l'espacement est trop grand pour
    /// le conteneur. Même valeur que `MasterStackLayoutStrategy.minimumTileExtent` (REL-031).
    static let minimumChildExtent: CGFloat = 10

    static func gap(for orientation: BSPOrientation, innerGap: CGFloat) -> CGFloat {
        orientation == .horizontal ? max(innerGap, titleBarSeamGap) : innerGap
    }

    /// Écart réellement appliqué dans `rect` : sans borne, un espacement plus grand que le
    /// conteneur poussait le second enfant hors de `rect`. Il est borné pour laisser
    /// `minimumChildExtent` à chaque enfant ; un écart qui tient déjà reste inchangé.
    static func gap(for orientation: BSPOrientation, in rect: CGRect, innerGap: CGFloat) -> CGFloat {
        let extent = orientation == .vertical ? rect.width : rect.height
        return min(gap(for: orientation, innerGap: innerGap), max(0, extent - 2 * minimumChildExtent))
    }

    /// Longueur partageable d'un split (son étendue sur l'axe coupé, moins l'écart).
    static func usableExtent(of rect: CGRect, orientation: BSPOrientation, innerGap: CGFloat) -> CGFloat {
        let extent = orientation == .vertical ? rect.width : rect.height
        return max(0, extent - gap(for: orientation, in: rect, innerGap: innerGap))
    }

    /// Rectangles des deux enfants d'un split, au ratio borné.
    static func childRects(
        of rect: CGRect,
        orientation: BSPOrientation,
        ratio: Double,
        innerGap: CGFloat
    ) -> (first: CGRect, second: CGRect) {
        let clamped = min(max(ratio, ratioBounds.lowerBound), ratioBounds.upperBound)
        let gap = gap(for: orientation, in: rect, innerGap: innerGap)
        let usable = usableExtent(of: rect, orientation: orientation, innerGap: innerGap)
        let firstExtent = floor(usable * clamped)
        let secondExtent = usable - firstExtent
        switch orientation {
        case .vertical:
            return (CGRect(x: rect.minX, y: rect.minY, width: firstExtent, height: rect.height),
                    CGRect(x: rect.minX + firstExtent + gap, y: rect.minY, width: secondExtent, height: rect.height))
        case .horizontal:
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstExtent),
                    CGRect(x: rect.minX, y: rect.minY + firstExtent + gap, width: rect.width, height: secondExtent))
        }
    }

    // MARK: - Mutations

    /// Insère `window` en divisant la feuille `anchor` (première feuille visible si `anchor` est
    /// nil, inconnue ou dans `absent`). Le sens de coupe suit la dimension dominante du rectangle VISIBLE de cette feuille
    /// dans `container` (split auto de yabai, `view.c:148`, SPEC-013 EF-004) : une feuille large
    /// est coupée en deux colonnes, une feuille haute en deux rangées. Ratio 0,5. `absent` désigne
    /// les feuilles gardées mais non affichées (A9) : le rectangle est mesuré sur la projection.
    // O(n²) au pire - n = feuilles (voir l'en-tête du type).
    public func inserting(
        _ window: WindowID,
        at anchor: WindowID?,
        side: BSPInsertionSide,
        in container: CGRect,
        innerGap: CGFloat = 0,
        excluding absent: Set<WindowID> = []
    ) -> BSPTree {
        let visible = projected(excluding: absent)
        let target = anchor.flatMap { visible.contains($0) ? $0 : nil } ?? visible.windowIDs.first
        let rect = target.flatMap { visible.place(in: container, innerGap: innerGap)[$0] } ?? container
        return inserting(window, nextTo: target, side: side, containerIsWide: rect.width >= rect.height)
    }

    /// Insère `window` en divisant la feuille `focus`. Si `focus` est absent (ou nil), insère
    /// sur la première feuille rencontrée ; si l'arbre est vide, `window` devient la racine.
    /// `side` détermine si la nouvelle fenêtre prend la moitié droite/bas (`right`) ou
    /// gauche/haut (`left`). `containerIsWide` impose l'orientation du nouveau split (vertical
    /// si vrai). Préférer `inserting(_:at:side:in:)`, qui la déduit de la feuille coupée (R3).
    public func inserting(
        _ window: WindowID,
        nextTo focus: WindowID?,
        side: BSPInsertionSide,
        containerIsWide: Bool
    ) -> BSPTree {
        switch self {
        case .empty:
            return .leaf(window)
        case .leaf(let id):
            // Une feuille n'est atteinte qu'avec son propre focus, nil, ou un focus absent de
            // l'arbre (feuille racine) : ce dernier cas se traite comme nil, sinon la fenêtre
            // serait perdue (ex. focus = la nouvelle fenêtre elle-même).
            let orientation: BSPOrientation = containerIsWide ? .vertical : .horizontal
            switch side {
            case .right:
                return .split(orientation: orientation, ratio: 0.5, first: .leaf(id), second: .leaf(window))
            case .left:
                return .split(orientation: orientation, ratio: 0.5, first: .leaf(window), second: .leaf(id))
            }
        case .split(let orientation, let ratio, let first, let second):
            if let focus, first.contains(focus) {
                return .split(orientation: orientation, ratio: ratio,
                              first: first.inserting(window, nextTo: focus, side: side, containerIsWide: containerIsWide),
                              second: second)
            }
            if let focus, second.contains(focus) {
                return .split(orientation: orientation, ratio: ratio,
                              first: first,
                              second: second.inserting(window, nextTo: focus, side: side, containerIsWide: containerIsWide))
            }
            // Pas de focus précis : insérer sur la première feuille (descente à gauche).
            return .split(orientation: orientation, ratio: ratio,
                          first: first.inserting(window, nextTo: nil, side: side, containerIsWide: containerIsWide),
                          second: second)
        }
    }

    /// Retire `window`. Le frère du nœud supprimé remonte à la place du parent.
    public func removing(_ window: WindowID) -> BSPTree {
        switch self {
        case .empty:
            return .empty
        case .leaf(let id):
            return id == window ? .empty : self
        case .split(let orientation, let ratio, let first, let second):
            if first.contains(window) {
                let newFirst = first.removing(window)
                return newFirst.isEmpty ? second : .split(orientation: orientation, ratio: ratio, first: newFirst, second: second)
            }
            if second.contains(window) {
                let newSecond = second.removing(window)
                return newSecond.isEmpty ? first : .split(orientation: orientation, ratio: ratio, first: first, second: newSecond)
            }
            return self
        }
    }

    // MARK: - Manipulation interactive (SPEC-014)

    /// Échange la position de deux feuilles dans l'arbre. La structure (splits, ratios) est
    /// préservée ; seules les fenêtres aux feuilles permutent. Utilisé par `move`/`swap`.
    public func swapping(_ a: WindowID, _ b: WindowID) -> BSPTree {
        guard a != b, contains(a), contains(b) else { return self }
        return relabelling(a, b)
    }

    /// Remplace toute feuille `a` par `b` et inversement, récursivement. Suppose que les
    /// deux fenêtres existent (vérifié par `swapping`).
    private func relabelling(_ a: WindowID, _ b: WindowID) -> BSPTree {
        switch self {
        case .empty:
            return self
        case .leaf(let id):
            if id == a { return .leaf(b) }
            if id == b { return .leaf(a) }
            return self
        case .split(let orientation, let ratio, let first, let second):
            return .split(orientation: orientation, ratio: ratio,
                          first: first.relabelling(a, b),
                          second: second.relabelling(a, b))
        }
    }

    // MARK: - Projection (SPEC-017 A9)

    /// Copie de l'arbre sans les feuilles `absent` (fenêtres gardées pendant leur grâce mais non
    /// affichées). Un split dont un côté devient vide est replié : l'autre côté prend sa place.
    /// Les splits restants gardent orientation et ratio, donc leur identité (voir l'en-tête).
    // O(n)
    public func projected(excluding absent: Set<WindowID>) -> BSPTree {
        guard !absent.isEmpty else { return self }
        switch self {
        case .empty:
            return self
        case .leaf(let id):
            return absent.contains(id) ? .empty : self
        case .split(let orientation, let ratio, let first, let second):
            let newFirst = first.projected(excluding: absent)
            let newSecond = second.projected(excluding: absent)
            if newFirst.isEmpty { return newSecond }
            if newSecond.isEmpty { return newFirst }
            return .split(orientation: orientation, ratio: ratio, first: newFirst, second: newSecond)
        }
    }

    /// Applique `operation` (qui ne change ni les feuilles ni la structure) sur la projection
    /// sans `absent`, puis reporte ses splits sur l'arbre complet : les feuilles absentes ne sont
    /// jamais perdues et les splits repliés restent inchangés.
    private func onProjection(excluding absent: Set<WindowID>, _ operation: (BSPTree) -> BSPTree?) -> BSPTree? {
        guard !absent.isEmpty else { return operation(self) }
        return operation(projected(excluding: absent)).map(adoptingSplits(from:))
    }

    /// Reporte sur l'arbre complet l'orientation et le ratio de chaque split de `projection`
    /// (table temporaire indexée par l'identité des splits, voir l'en-tête).
    // O(n)
    private func adoptingSplits(from projection: BSPTree) -> BSPTree {
        var splits: [SplitKey: (orientation: BSPOrientation, ratio: Double)] = [:]
        projection.collectSplits(into: &splits)
        guard !splits.isEmpty else { return self }
        return adoptingSplits(splits, present: Set(projection.windowIDs)).tree
    }

    /// Identité d'un split : première feuille de son côté `first` et de son côté `second`.
    private struct SplitKey: Hashable {
        let first: WindowID
        let second: WindowID
    }

    /// Recense les splits ; rend la première feuille du sous-arbre.
    @discardableResult
    private func collectSplits(into splits: inout [SplitKey: (orientation: BSPOrientation, ratio: Double)]) -> WindowID? {
        switch self {
        case .empty:
            return nil
        case .leaf(let id):
            return id
        case .split(let orientation, let ratio, let first, let second):
            let a = first.collectSplits(into: &splits)
            let b = second.collectSplits(into: &splits)
            if let a, let b { splits[SplitKey(first: a, second: b)] = (orientation, ratio) }
            return a ?? b
        }
    }

    /// Rend l'arbre mis à jour et la première feuille présente (dans `present`) du sous-arbre.
    private func adoptingSplits(
        _ splits: [SplitKey: (orientation: BSPOrientation, ratio: Double)],
        present: Set<WindowID>
    ) -> (tree: BSPTree, firstPresent: WindowID?) {
        switch self {
        case .empty:
            return (self, nil)
        case .leaf(let id):
            return (self, present.contains(id) ? id : nil)
        case .split(let orientation, let ratio, let first, let second):
            let newFirst = first.adoptingSplits(splits, present: present)
            let newSecond = second.adoptingSplits(splits, present: present)
            var adopted = (orientation: orientation, ratio: ratio)
            if let a = newFirst.firstPresent, let b = newSecond.firstPresent,
               let match = splits[SplitKey(first: a, second: b)] {
                adopted = match
            }
            return (.split(orientation: adopted.orientation, ratio: adopted.ratio,
                           first: newFirst.tree, second: newSecond.tree),
                    newFirst.firstPresent ?? newSecond.firstPresent)
        }
    }

    // MARK: - Commandes sur les splits (SPEC-017 R12)

    /// Remet tous les ratios à 0,5 (`balance`, `layout flatten`). Structure inchangée.
    // O(n)
    public func balanced() -> BSPTree {
        switch self {
        case .empty, .leaf:
            return self
        case .split(let orientation, _, let first, let second):
            return .split(orientation: orientation, ratio: 0.5, first: first.balanced(), second: second.balanced())
        }
    }

    /// Inverse le sens du split parent VISIBLE de `window` (`layout toggle-split`, comme yabai).
    /// Arbre inchangé si `window` est absente ou seule.
    // O(n²) au pire (recherche du chemin), n borné.
    public func togglingSplit(of window: WindowID, excluding absent: Set<WindowID> = []) -> BSPTree {
        onProjection(excluding: absent) { tree in
            guard let parent = tree.ancestors(of: window, in: .zero, innerGap: 0).last else { return tree }
            return tree.updatingSplit(at: parent.path[...]) { ($0 == .vertical ? .horizontal : .vertical, $1) }
        } ?? self
    }

    /// Impose `orientation` au split parent VISIBLE de `window` (`layout split horizontal|vertical`).
    // O(n²) au pire (recherche du chemin), n borné.
    public func settingSplit(of window: WindowID, to orientation: BSPOrientation, excluding absent: Set<WindowID> = []) -> BSPTree {
        onProjection(excluding: absent) { tree in
            guard let parent = tree.ancestors(of: window, in: .zero, innerGap: 0).last else { return tree }
            return tree.updatingSplit(at: parent.path[...]) { _, ratio in (orientation, ratio) }
        } ?? self
    }

    // MARK: - Frontières et tailles minimales (SPEC-017 R6, R12, A2)

    /// Déplace la frontière (fence) entre `window` et sa voisine du côté `edge` pour qu'elle
    /// passe par le bord correspondant de `frame` (frame demandée par un geste ou un resize).
    /// La frontière est celle du split ancêtre VISIBLE le plus proche qui sépare `window` de ce
    /// côté ; géométrie mesurée sans les feuilles `absent`. Le ratio est recalculé depuis `frame`,
    /// borné à [0,05 ; 0,95]. Arbre inchangé s'il n'y a pas de frontière de ce côté.
    /// Avec `knownMinimums`, limite la frontière avant qu'une voisine refuse sa taille.
    // O(n²) au pire (recherche du chemin), n borné.
    public func adjustingFence(
        of window: WindowID,
        edge: BSPEdge,
        to frame: CGRect,
        in container: CGRect,
        innerGap: CGFloat = 0,
        excluding absent: Set<WindowID> = [],
        knownMinimums: [WindowID: CGSize] = [:]
    ) -> BSPTree {
        let orientation: BSPOrientation = (edge == .left || edge == .right) ? .vertical : .horizontal
        // La fenêtre est du côté `first` quand la frontière est à sa droite ou en dessous.
        let windowInFirst = edge == .right || edge == .down
        return onProjection(excluding: absent) { tree in
            guard let split = tree.ancestors(of: window, in: container, innerGap: innerGap)
                .last(where: { $0.orientation == orientation && $0.windowInFirst == windowInFirst })
            else { return tree }
            let usable = Self.usableExtent(of: split.rect, orientation: orientation, innerGap: innerGap)
            guard usable > 0 else { return tree }
            let gap = Self.gap(for: orientation, in: split.rect, innerGap: innerGap)
            let origin = orientation == .vertical ? split.rect.minX : split.rect.minY
            // Étendue du côté `first` = position de la frontière depuis l'origine du split.
            let firstExtent: CGFloat = switch edge {
            case .right: frame.maxX - origin
            case .down: frame.maxY - origin
            case .left: frame.minX - gap - origin
            case .up: frame.minY - gap - origin
            }
            let ratio = min(max(Double(firstExtent / usable), Self.ratioBounds.lowerBound), Self.ratioBounds.upperBound)
            let requested = tree.updatingSplit(at: split.path[...]) { orientation, _ in (orientation, ratio) }
            guard !knownMinimums.isEmpty else { return requested }
            let before = tree.place(in: container, innerGap: innerGap)
            func fits(_ candidate: BSPTree) -> Bool {
                let frames = candidate.place(in: container, innerGap: innerGap)
                return knownMinimums.allSatisfy { id, minimum in
                    guard let original = before[id], let actual = frames[id] else { return true }
                    // Une contrainte déjà infaisable ne doit pas empêcher tout geste,
                    // mais la fenêtre concernée ne doit pas rétrécir davantage.
                    return actual.width >= min(minimum.width, original.width)
                        && actual.height >= min(minimum.height, original.height)
                }
            }
            if fits(requested) { return requested }
            var low = 0.0, high = 1.0
            var accepted = tree
            // O(16n) de plus : borne de 16 essais, uniquement au relâchement du geste.
            // Les autres ratios et les feuilles absentes restent fixes.
            for _ in 0..<16 {
                let fraction = (low + high) / 2
                let value = split.ratio + (ratio - split.ratio) * fraction
                let candidate = tree.updatingSplit(at: split.path[...]) { orientation, _ in (orientation, value) }
                if fits(candidate) { low = fraction; accepted = candidate }
                else { high = fraction }
            }
            return accepted
        } ?? self
    }

    /// Corrige l'arbre pour que `window` obtienne au moins `minimum` (taille refusée par
    /// l'application, A2). Pour chaque axe en déficit, calcule les besoins des sous-arbres, puis
    /// choisit l'ancêtre VISIBLE faisable le plus proche. Les splits du chemin peuvent partager
    /// l'effort : chacun garde sa séparation actuelle tant qu'elle couvre les besoins calculés.
    /// Les autres ratios restent fixes. Faisable = ratios dans [0,05 ; 0,95] et, au placement
    /// réel, `window` atteint `minimum` sans qu'une voisine rétrécie passe sous son minimum connu.
    /// Rend `nil` si c'est infaisable (fenêtre absente ou non visible, aucun ancêtre faisable),
    /// l'arbre inchangé si aucun axe n'est en déficit.
    // O(d·n + n·log L) - recherches bornées sur les points de l'écran, n = feuilles, d = profondeur.
    public func correctingForMinimumSize(
        of window: WindowID,
        minimum: CGSize,
        in container: CGRect,
        innerGap: CGFloat = 0,
        excluding absent: Set<WindowID> = [],
        knownMinimums: [WindowID: CGSize] = [:]
    ) -> BSPTree? {
        onProjection(excluding: absent) { visible in
            var tree = visible
            for axis in [BSPOrientation.vertical, .horizontal] {
                let extent = { (rect: CGRect) in axis == .vertical ? rect.width : rect.height }
                let need = ceil(axis == .vertical ? minimum.width : minimum.height)
                let before = tree.place(in: container, innerGap: innerGap)
                guard let current = before[window] else { return nil }
                guard extent(current) < need else { continue }
                let chain = tree.ancestors(of: window, in: container, innerGap: innerGap)
                var requirements: [[Bool]: CGFloat] = [:]

                func withExtent(_ value: CGFloat, in rect: CGRect) -> CGRect {
                    var result = rect
                    if axis == .vertical { result.size.width = value }
                    else { result.size.height = value }
                    return result
                }

                // Les coupes first sont entières. Les fractions des origines et étendues de
                // chaque sous-arbre restent donc fixes quand les ratios changent, même avec
                // un gap fractionnaire. Sur ces points successifs, les tailles sont monotones.
                func minimumExtent(in rect: CGRect, fits: (CGRect) -> Bool) -> CGFloat? {
                    let fraction = extent(rect) - floor(extent(rect))
                    var low = 0
                    var high = Int(max(0, floor(extent(container) - fraction)))
                    guard fits(withExtent(CGFloat(high) + fraction, in: rect)) else { return nil }
                    while low < high {
                        let middle = low + (high - low) / 2
                        if fits(withExtent(CGFloat(middle) + fraction, in: rect)) { high = middle }
                        else { low = middle + 1 }
                    }
                    return CGFloat(low) + fraction
                }

                // Intervalle des étendues entières first compatibles avec les deux besoins
                // et les bornes du ratio. second reçoit exactement usable - first, comme place.
                func firstExtentRange(usable: CGFloat, first: CGFloat, second: CGFloat) -> ClosedRange<CGFloat>? {
                    let lower = max(ceil(first), floor(usable * Self.ratioBounds.lowerBound))
                    let upper = min(floor(usable - second), floor(usable * Self.ratioBounds.upperBound))
                    return lower <= upper ? lower...upper : nil
                }

                func requiredExtent(of node: BSPTree, in rect: CGRect, path: [Bool]) -> CGFloat? {
                    let required: CGFloat?
                    switch node {
                    case .empty:
                        required = 0
                    case .leaf(let id):
                        let known = knownMinimums[id].map { ceil(axis == .vertical ? $0.width : $0.height) } ?? 0
                        // Une voisine déjà sous son minimum peut rester identique, mais pas rétrécir.
                        let leafNeed = id == window ? need : min(known, before[id].map(extent) ?? 0)
                        required = minimumExtent(in: rect) { extent($0.integral) >= leafNeed }
                    case .split(let orientation, let ratio, let first, let second):
                        let rects = Self.childRects(of: rect, orientation: orientation, ratio: ratio, innerGap: innerGap)
                        guard let a = requiredExtent(of: first, in: rects.first, path: path + [true]),
                              let b = requiredExtent(of: second, in: rects.second, path: path + [false])
                        else { return nil }
                        if orientation != axis {
                            required = max(a, b)
                        } else if node.contains(window) {
                            required = minimumExtent(in: rect) {
                                firstExtentRange(usable: Self.usableExtent(of: $0, orientation: axis, innerGap: innerGap),
                                                 first: a, second: b) != nil
                            }
                        } else {
                            // Les sous-arbres voisins gardent leurs ratios, donc aussi leurs coupes internes.
                            required = minimumExtent(in: rect) {
                                let children = Self.childRects(of: $0, orientation: orientation, ratio: ratio, innerGap: innerGap)
                                return extent(children.first) >= a && extent(children.second) >= b
                            }
                        }
                    }
                    if let required { requirements[path] = required }
                    return required
                }

                guard requiredExtent(of: tree, in: container, path: []) != nil,
                      let anchor = chain.reversed().first(where: {
                          $0.orientation == axis && extent($0.rect) >= (requirements[$0.path] ?? .infinity)
                      })
                else { return nil }

                func correcting(_ node: BSPTree, in rect: CGRect, path: [Bool]) -> BSPTree? {
                    guard case .split(let orientation, let ratio, let first, let second) = node else { return node }
                    let inFirst = first.contains(window)
                    var newRatio = ratio
                    if orientation == axis, path.count >= anchor.path.count {
                        let usable = Self.usableExtent(of: rect, orientation: axis, innerGap: innerGap)
                        guard usable > 0,
                              let a = requirements[path + [true]], let b = requirements[path + [false]],
                              let allowed = firstExtentRange(usable: usable, first: a, second: b)
                        else { return nil }
                        let oldExtent = floor(usable * min(max(ratio, Self.ratioBounds.lowerBound), Self.ratioBounds.upperBound))
                        let newExtent = min(max(oldExtent, allowed.lowerBound), allowed.upperBound)
                        if newExtent != oldExtent {
                            // Le milieu de l'intervalle qui produit cet entier évite les erreurs d'arrondi.
                            newRatio = min(max(Double((newExtent + 0.5) / usable), Self.ratioBounds.lowerBound), Self.ratioBounds.upperBound)
                        }
                    }
                    let rects = Self.childRects(of: rect, orientation: orientation, ratio: newRatio, innerGap: innerGap)
                    if inFirst {
                        guard let child = correcting(first, in: rects.first, path: path + [true]) else { return nil }
                        return .split(orientation: orientation, ratio: newRatio, first: child, second: second)
                    }
                    guard let child = correcting(second, in: rects.second, path: path + [false]) else { return nil }
                    return .split(orientation: orientation, ratio: newRatio, first: first, second: child)
                }

                guard let corrected = correcting(tree, in: container, path: []) else { return nil }
                let after = corrected.place(in: container, innerGap: innerGap)
                guard let reached = after[window], extent(reached) >= need,
                      knownMinimums.allSatisfy({ id, known in
                          guard let old = before[id], let new = after[id], extent(new) < extent(old) else { return true }
                          return extent(new) >= ceil(axis == .vertical ? known.width : known.height)
                      })
                else { return nil }
                tree = corrected
            }
            return tree
        }
    }

    /// Split ancêtre d'une fenêtre : chemin depuis la racine (`true` = côté `first`), orientation,
    /// ratio, rectangle du split et côté de la fenêtre.
    private struct Ancestor {
        let path: [Bool]
        let orientation: BSPOrientation
        let ratio: Double
        let rect: CGRect
        let windowInFirst: Bool
    }

    /// Splits ancêtres de `window`, de la racine vers la feuille, avec leur rectangle dans `rect`.
    /// Vide si `window` est absente ou seule.
    // O(n·d) - un `contains` par niveau.
    private func ancestors(of window: WindowID, in rect: CGRect, innerGap: CGFloat) -> [Ancestor] {
        var result: [Ancestor] = []
        var node = self
        var nodeRect = rect
        var path: [Bool] = []
        while case .split(let orientation, let ratio, let first, let second) = node {
            let inFirst = first.contains(window)
            guard inFirst || second.contains(window) else { return [] }
            result.append(Ancestor(path: path, orientation: orientation, ratio: ratio, rect: nodeRect, windowInFirst: inFirst))
            let rects = Self.childRects(of: nodeRect, orientation: orientation, ratio: ratio, innerGap: innerGap)
            node = inFirst ? first : second
            nodeRect = inFirst ? rects.first : rects.second
            path.append(inFirst)
        }
        return node == .leaf(window) ? result : []
    }

    /// Remplace orientation et ratio du split au bout de `path` (depuis la racine).
    private func updatingSplit(
        at path: ArraySlice<Bool>,
        _ transform: (BSPOrientation, Double) -> (BSPOrientation, Double)
    ) -> BSPTree {
        guard case .split(let orientation, let ratio, let first, let second) = self else { return self }
        guard let step = path.first else {
            let (newOrientation, newRatio) = transform(orientation, ratio)
            return .split(orientation: newOrientation, ratio: newRatio, first: first, second: second)
        }
        let rest = path.dropFirst()
        return step
            ? .split(orientation: orientation, ratio: ratio, first: first.updatingSplit(at: rest, transform), second: second)
            : .split(orientation: orientation, ratio: ratio, first: first, second: second.updatingSplit(at: rest, transform))
    }

    // MARK: - Arbre initial déduit de la géométrie (migration SPEC-017 A8)

    /// Construit l'arbre initial d'une stage depuis ses membres DANS L'ORDRE et leurs frames
    /// actuelles, pour éviter un saut visuel à la migration. Coupe la liste en deux moitiés
    /// (politique `balanced`) et déduit de la géométrie le sens et le ratio de chaque coupe.
    /// Repli déterministe si une frame manque ou est inutilisable (hors du conteneur,
    /// chevauchement) : chaque membre est inséré dans l'ordre à côté du précédent.
    /// L'ordre des feuilles est celui de `ordered` ; aucun membre n'est perdu (doublons ignorés).
    // O(n²) - vérification des chevauchements deux à deux ; n = membres d'une stage, borné (< 50).
    public static func inferred(
        from ordered: [(WindowID, CGRect?)],
        in container: CGRect,
        innerGap: CGFloat = 0
    ) -> BSPTree {
        var seen = Set<WindowID>()
        let members = ordered.filter { seen.insert($0.0).inserted }
        let ids = members.map(\.0)
        let known = members.compactMap { id, frame in frame.map { (id, $0) } }
        let frames = Dictionary(known, uniquingKeysWith: { first, _ in first })
        guard known.count == ids.count, InferredCuts.framesAreUsable(known.map(\.1), in: container) else {
            var tree = BSPTree.empty
            var previous: WindowID?
            for id in ids {
                tree = tree.inserting(id, at: previous, side: .right, in: container, innerGap: innerGap)
                previous = id
            }
            return tree
        }
        return InferredCuts(frames: frames, innerGap: innerGap).tree(for: ids[...], in: container)
    }
}

/// Détection des coupes nettes depuis la géométrie, reprise de l'ancienne stratégie `mutableBsp`
/// (supprimée par la SPEC-017, FR-018) : seule la migration des stages `mutableBsp` en a besoin.
private struct InferredCuts {
    let frames: [WindowID: CGRect]
    let innerGap: CGFloat

    /// Frames exploitables : chacune non vide et au moins à moitié dans le conteneur, et pas de
    /// chevauchement de plus de 10 % de la plus petite de deux frames.
    // O(n²) - n borné (membres d'une stage).
    static func framesAreUsable(_ frames: [CGRect], in container: CGRect) -> Bool {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        for frame in frames {
            guard frame.width > 0, frame.height > 0,
                  area(frame.intersection(container)) >= area(frame) * LayoutTolerance.halfCoverage
            else { return false }
        }
        for (index, lhs) in frames.enumerated() {
            for rhs in frames[(index + 1)...] where area(lhs.intersection(rhs)) > min(area(lhs), area(rhs)) * 0.1 {
                return false
            }
        }
        return true
    }

    func tree(for windows: ArraySlice<WindowID>, in rect: CGRect) -> BSPTree {
        guard let first = windows.first else { return .empty }
        guard windows.count > 1 else { return .leaf(first) }
        let left = windows.prefix(windows.count / 2)
        let right = windows.dropFirst(windows.count / 2)
        let orientation: BSPOrientation = splitHorizontally(left: left, right: right, rect: rect) ? .vertical : .horizontal
        let ratio = Double(splitRatio(left: left, right: right, rect: rect, orientation: orientation))
        let rects = BSPTree.childRects(of: rect, orientation: orientation, ratio: ratio, innerGap: innerGap)
        return .split(orientation: orientation, ratio: ratio,
                      first: tree(for: left, in: rects.first),
                      second: tree(for: right, in: rects.second))
    }

    /// Vrai si les deux groupes sont côte à côte (coupe verticale), faux s'ils sont empilés.
    private func splitHorizontally(left: ArraySlice<WindowID>, right: ArraySlice<WindowID>, rect: CGRect) -> Bool {
        guard let leftFrame = unionFrame(for: left, in: frames),
              let rightFrame = unionFrame(for: right, in: frames)
        else { return rect.width >= rect.height }

        let tolerance = LayoutTolerance.edgeAlignment
        let xOverlap = overlap(leftFrame.minX...leftFrame.maxX, rightFrame.minX...rightFrame.maxX)
        let yOverlap = overlap(leftFrame.minY...leftFrame.maxY, rightFrame.minY...rightFrame.maxY)
        let xOverlapRatio = xOverlap / max(1, min(leftFrame.width, rightFrame.width))
        let yOverlapRatio = yOverlap / max(1, min(leftFrame.height, rightFrame.height))

        let sideBySide = yOverlapRatio >= 0.45
            && (leftFrame.maxX <= rightFrame.minX + tolerance || rightFrame.maxX <= leftFrame.minX + tolerance)
        if sideBySide { return true }

        let stacked = xOverlapRatio >= 0.45
            && (leftFrame.maxY <= rightFrame.minY + tolerance || rightFrame.maxY <= leftFrame.minY + tolerance)
        if stacked { return false }

        if abs(xOverlapRatio - yOverlapRatio) >= 0.15 {
            return yOverlapRatio > xOverlapRatio
        }
        return rect.width >= rect.height
    }

    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        orientation: BSPOrientation
    ) -> CGFloat {
        guard let leftFrame = unionFrame(for: left, in: frames),
              let rightFrame = unionFrame(for: right, in: frames)
        else { return 0.5 }
        let horizontal = orientation == .vertical
        let gap = BSPTree.gap(for: orientation, in: rect, innerGap: innerGap)
        let usableExtent = BSPTree.usableExtent(of: rect, orientation: orientation, innerGap: innerGap)
        guard usableExtent > 0 else { return 0.5 }

        if managedSplitLooksUsable(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal, gap: gap) {
            let edge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
            return (edge / usableExtent).clamped(to: 0.1...0.9)
        }

        let leftExtent = horizontal ? leftFrame.width : leftFrame.height
        let rightExtent = horizontal ? rightFrame.width : rightFrame.height
        let totalObserved = leftExtent + rightExtent
        guard totalObserved > 0 else { return 0.5 }
        return (leftExtent / totalObserved).clamped(to: 0.1...0.9)
    }

    private func overlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    // L'écart signé entre les deux côtés (négatif = chevauchement) doit rester proche de la
    // marge intérieure configurée ; la tolérance en dérive (SPEC-016 FR-041).
    private func managedSplitLooksUsable(
        leftFrame: CGRect,
        rightFrame: CGRect,
        rect: CGRect,
        horizontal: Bool,
        gap: CGFloat
    ) -> Bool {
        let edgeTolerance = LayoutTolerance.edgeAlignment
        let gapTolerance = LayoutTolerance.innerGapTolerance(gapsInner: gap)
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX, tolerance: edgeTolerance)
                && rightFrame.maxX.isClose(to: rect.maxX, tolerance: edgeTolerance)
                && abs(rightFrame.minX - leftFrame.maxX - gap) <= gapTolerance
        }
        return leftFrame.minY.isClose(to: rect.minY, tolerance: edgeTolerance)
            && rightFrame.maxY.isClose(to: rect.maxY, tolerance: edgeTolerance)
            && abs(rightFrame.minY - leftFrame.maxY - gap) <= gapTolerance
    }
}
