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

/// Arbre BSP persistant (style yabai/i3). Chaque nœud interne (`split`) coupe l'espace
/// en deux selon une orientation et un ratio ; chaque feuille (`leaf`) porte une fenêtre.
/// Contrairement aux stratégies dérivées d'une liste, cet arbre MÉMORISE la structure :
/// une nouvelle fenêtre divise uniquement la feuille focalisée, le reste ne bouge pas.
///
/// Complexité (Article XVIII) : `place`, `windowIDs`, `contains`, `removing` sont O(n) sur le
/// nombre de feuilles. `inserting` est O(n²) au pire (un `contains` par niveau pendant la
/// descente) et `reconciled` O(k·n) (k fenêtres à insérer). n = fenêtres d'un stage, BORNÉ par
/// construction (typiquement < 20, plafond observé ~50) → au pire ~2500 opérations, hors hot
/// path serré (appelé à la fréquence du tiling, pas par fenêtre). Compromis accepté : la
/// lisibilité d'un arbre immuable récursif prime sur une optimisation non nécessaire à cette
/// échelle.
public indirect enum BSPTree: Equatable, Codable, Sendable {
    case empty
    case leaf(WindowID)
    case split(orientation: BSPOrientation, ratio: Double, first: BSPTree, second: BSPTree)

    // MARK: - Lecture

    /// Feuilles dans l'ordre de parcours (first avant second) = gauche→droite, haut→bas.
    public var windowIDs: [WindowID] {
        switch self {
        case .empty:
            return []
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.windowIDs + second.windowIDs
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
            let clamped = min(max(ratio, 0.05), 0.95)
            switch orientation {
            case .vertical:
                let usable = max(0, rect.width - innerGap)
                let firstWidth = floor(usable * clamped)
                let secondWidth = usable - firstWidth
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
                let secondRect = CGRect(x: rect.minX + firstWidth + innerGap, y: rect.minY, width: secondWidth, height: rect.height)
                first.place(in: firstRect, innerGap: innerGap, into: &result)
                second.place(in: secondRect, innerGap: innerGap, into: &result)
            case .horizontal:
                let usable = max(0, rect.height - innerGap)
                let firstHeight = floor(usable * clamped)
                let secondHeight = usable - firstHeight
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
                let secondRect = CGRect(x: rect.minX, y: rect.minY + firstHeight + innerGap, width: rect.width, height: secondHeight)
                first.place(in: firstRect, innerGap: innerGap, into: &result)
                second.place(in: secondRect, innerGap: innerGap, into: &result)
            }
        }
    }

    // MARK: - Mutations

    /// Insère `window` en divisant la feuille `focus`. Si `focus` est absent (ou nil), insère
    /// sur la première feuille rencontrée ; si l'arbre est vide, `window` devient la racine.
    /// `side` détermine si la nouvelle fenêtre prend la moitié droite/bas (`right`) ou
    /// gauche/haut (`left`). `containerIsWide` choisit l'orientation par défaut quand on ne
    /// peut pas la déduire (split vertical si large, horizontal sinon — comportement yabai).
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
            // Insère ici si c'est la feuille focus, ou si aucun focus précis n'est demandé.
            guard focus == nil || focus == id else { return self }
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

    /// Ajuste le ratio du split dont le `first` contient directement `window` (resize manuel).
    /// Cherche le plus petit split englobant `window` et applique `ratio`.
    public func adoptingRatio(_ newRatio: Double, forSplitContaining window: WindowID, onFirstSide: Bool) -> BSPTree {
        switch self {
        case .empty, .leaf:
            return self
        case .split(let orientation, let ratio, let first, let second):
            let target = onFirstSide ? first.contains(window) : second.contains(window)
            if target {
                return .split(orientation: orientation, ratio: newRatio, first: first, second: second)
            }
            return .split(orientation: orientation, ratio: ratio,
                          first: first.adoptingRatio(newRatio, forSplitContaining: window, onFirstSide: onFirstSide),
                          second: second.adoptingRatio(newRatio, forSplitContaining: window, onFirstSide: onFirstSide))
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

    /// Déplace `window` à côté de `neighbor` : retire `window` (son frère récupère l'espace)
    /// puis l'insère en divisant le pane de `neighbor`. Change la structure. Utilisé par `warp`.
    public func warping(_ window: WindowID, nextTo neighbor: WindowID, side: BSPInsertionSide, containerIsWide: Bool) -> BSPTree {
        guard window != neighbor, contains(window), contains(neighbor) else { return self }
        return removing(window).inserting(window, nextTo: neighbor, side: side, containerIsWide: containerIsWide)
    }

    /// Ajuste le ratio du split ancêtre le plus profond de l'orientation donnée qui contient
    /// `window`. `delta` est signé : positif agrandit le `first`, négatif le `second`.
    /// Utilisé par `resize` (orientation `.vertical` pour gauche/droite, `.horizontal` pour haut/bas).
    public func resizing(window: WindowID, orientation: BSPOrientation, delta: Double) -> BSPTree {
        resizing(window: window, orientation: orientation, delta: delta, applied: false).tree
    }

    private func resizing(window: WindowID, orientation: BSPOrientation, delta: Double, applied: Bool) -> (tree: BSPTree, applied: Bool) {
        switch self {
        case .empty, .leaf:
            return (self, false)
        case .split(let splitOrientation, let ratio, let first, let second):
            let windowInFirst = first.contains(window)
            let windowInSecond = second.contains(window)
            guard windowInFirst || windowInSecond else { return (self, false) }

            // Descendre d'abord pour ajuster le split le plus PROFOND de la bonne orientation.
            if windowInFirst {
                let child = first.resizing(window: window, orientation: orientation, delta: delta, applied: applied)
                if child.applied {
                    return (.split(orientation: splitOrientation, ratio: ratio, first: child.tree, second: second), true)
                }
            } else {
                let child = second.resizing(window: window, orientation: orientation, delta: delta, applied: applied)
                if child.applied {
                    return (.split(orientation: splitOrientation, ratio: ratio, first: first, second: child.tree), true)
                }
            }

            // Aucun descendant n'a appliqué : ce nœud le fait s'il est de la bonne orientation.
            if splitOrientation == orientation {
                // Si la fenêtre est dans `first`, agrandir = augmenter le ratio ; sinon l'inverse.
                let signed = windowInFirst ? delta : -delta
                let newRatio = min(max(ratio + signed, 0.05), 0.95)
                return (.split(orientation: splitOrientation, ratio: newRatio, first: first, second: second), true)
            }
            return (self, false)
        }
    }

    // MARK: - Construction depuis une liste (migration)

    /// Construit un arbre équilibré à partir d'une liste ordonnée de fenêtres.
    /// Utilisé pour migrer un stage existant (liste de membres) vers un arbre.
    public static func balanced(from windowIDs: [WindowID], containerIsWide: Bool) -> BSPTree {
        guard let first = windowIDs.first else { return .empty }
        guard windowIDs.count > 1 else { return .leaf(first) }
        let mid = windowIDs.count / 2
        let left = Array(windowIDs[..<mid])
        let right = Array(windowIDs[mid...])
        let orientation: BSPOrientation = containerIsWide ? .vertical : .horizontal
        return .split(
            orientation: orientation,
            ratio: 0.5,
            first: balanced(from: left, containerIsWide: containerIsWide),
            second: balanced(from: right, containerIsWide: containerIsWide)
        )
    }

    /// Reconcilie l'arbre avec l'ensemble des fenêtres réellement présentes : retire les
    /// feuilles orphelines, puis insère les fenêtres manquantes à côté du focus.
    public func reconciled(
        liveWindowIDs: [WindowID],
        focus: WindowID?,
        side: BSPInsertionSide,
        containerIsWide: Bool
    ) -> BSPTree {
        let live = Set(liveWindowIDs)
        var tree = self
        // 1. Retirer les feuilles dont la fenêtre n'existe plus.
        for id in windowIDs where !live.contains(id) {
            tree = tree.removing(id)
        }
        // 2. Insérer les fenêtres présentes mais absentes de l'arbre, dans l'ordre fourni.
        let present = Set(tree.windowIDs)
        var currentFocus = focus
        for id in liveWindowIDs where !present.contains(id) {
            tree = tree.inserting(id, nextTo: currentFocus, side: side, containerIsWide: containerIsWide)
            currentFocus = id // la fenêtre suivante se greffe à côté de la dernière insérée
        }
        return tree
    }
}
