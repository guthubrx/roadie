import Foundation

/// Logique pure : calcule l'alpha cible pour une fenêtre selon son focus, le baseline dim,
/// et une éventuelle règle per-app. La règle plus contraignante (alpha plus bas) gagne
/// quand la fenêtre n'est PAS focused. Si focused, la règle per-app fixe la valeur si
/// présente, sinon 1.0.
public func targetAlpha(focused: Bool,
                        baseline: Double,
                        perAppRule: Double?) -> Double {
    let baselineClamp = clamp01(baseline)
    let ruleClamp = perAppRule.map(clamp01)

    if focused {
        return ruleClamp ?? 1.0
    } else {
        if let r = ruleClamp { return min(r, baselineClamp) }
        return baselineClamp
    }
}

@inline(__always)
public func clamp01(_ d: Double) -> Double {
    max(0.0, min(1.0, d))
}
