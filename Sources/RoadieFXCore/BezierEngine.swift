import Foundation

/// Courbe Bézier 4 points (CSS standard).
/// `sample(t)` retourne la valeur eased pour `t` ∈ [0, 1].
/// Implémentation : table de lookup 256 samples + interpolation linéaire.
/// Précision garantie ≥ 0.005 (cf SPEC-004 SC).
public struct BezierCurve: Sendable, Hashable {
    public let p1x: Double
    public let p1y: Double
    public let p2x: Double
    public let p2y: Double
    private let lookup: [Double]

    public init(p1x: Double, p1y: Double, p2x: Double, p2y: Double) {
        self.p1x = max(0.0, min(1.0, p1x))
        self.p1y = p1y
        self.p2x = max(0.0, min(1.0, p2x))
        self.p2y = p2y
        self.lookup = Self.buildLookup(p1x: self.p1x, p1y: self.p1y,
                                       p2x: self.p2x, p2y: self.p2y)
    }

    /// Échantillonne la courbe à `t`. Retourne la valeur y eased.
    public func sample(_ t: Double) -> Double {
        let clampedT = max(0.0, min(1.0, t))
        let scaled = clampedT * Double(BezierCurve.samples - 1)
        let lo = Int(scaled)
        let hi = min(lo + 1, BezierCurve.samples - 1)
        let frac = scaled - Double(lo)
        return lookup[lo] * (1.0 - frac) + lookup[hi] * frac
    }

    public static let samples = 256

    /// Pré-calcule la table de lookup [t] → y via Newton-Raphson sur la coordonnée x.
    private static func buildLookup(p1x: Double, p1y: Double,
                                    p2x: Double, p2y: Double) -> [Double] {
        var result = [Double](repeating: 0.0, count: samples)
        for i in 0..<samples {
            let t = Double(i) / Double(samples - 1)
            let paramT = solveT(forX: t, p1x: p1x, p2x: p2x)
            result[i] = bezierAxis(t: paramT, p1: p1y, p2: p2y)
        }
        return result
    }

    /// Bézier 1D : (1-t)³·0 + 3·(1-t)²·t·p1 + 3·(1-t)·t²·p2 + t³·1
    /// = 3·(1-t)²·t·p1 + 3·(1-t)·t²·p2 + t³
    private static func bezierAxis(t: Double, p1: Double, p2: Double) -> Double {
        let omt = 1.0 - t
        return 3.0 * omt * omt * t * p1
             + 3.0 * omt * t * t * p2
             + t * t * t
    }

    /// Newton-Raphson : trouve `t` tel que `bezierAxis(t, p1x, p2x) = x`.
    /// Précision : ≤ 1e-6 sur 8 itérations max + bisection fallback.
    private static func solveT(forX x: Double, p1x: Double, p2x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let currentX = bezierAxis(t: t, p1: p1x, p2: p2x)
            let dx = currentX - x
            if abs(dx) < 1e-6 { return t }
            let derivative = bezierDerivative(t: t, p1: p1x, p2: p2x)
            if abs(derivative) < 1e-6 { break }
            t -= dx / derivative
        }
        // Fallback bisection 16 itérations
        var lo = 0.0
        var hi = 1.0
        var mid = x
        for _ in 0..<16 {
            mid = (lo + hi) / 2.0
            let currentX = bezierAxis(t: mid, p1: p1x, p2: p2x)
            if abs(currentX - x) < 1e-6 { return mid }
            if currentX < x { lo = mid } else { hi = mid }
        }
        return mid
    }

    private static func bezierDerivative(t: Double, p1: Double, p2: Double) -> Double {
        let omt = 1.0 - t
        return 3.0 * omt * omt * p1
             + 6.0 * omt * t * (p2 - p1)
             + 3.0 * t * t * (1.0 - p2)
    }
}

/// Built-in courbes communes (CSS).
extension BezierCurve {
    public static let linear = BezierCurve(p1x: 0.0, p1y: 0.0, p2x: 1.0, p2y: 1.0)
    public static let ease = BezierCurve(p1x: 0.25, p1y: 0.1, p2x: 0.25, p2y: 1.0)
    public static let easeInOut = BezierCurve(p1x: 0.42, p1y: 0.0, p2x: 0.58, p2y: 1.0)
    public static let snappy = BezierCurve(p1x: 0.05, p1y: 0.9, p2x: 0.1, p2y: 1.05)
    public static let smooth = BezierCurve(p1x: 0.4, p1y: 0.0, p2x: 0.2, p2y: 1.0)
    public static let easeOutBack = BezierCurve(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0)
}
