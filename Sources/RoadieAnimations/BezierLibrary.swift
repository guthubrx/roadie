import Foundation
import RoadieFXCore

/// Registry de courbes Bézier nommées (Hyprland-style config).
/// 3 built-in (linear, ease, easeInOut) + custom enregistrables.
public final class BezierLibrary: @unchecked Sendable {
    private var curves: [String: BezierCurve]
    private let lock = NSLock()

    public static let builtIn: [String: BezierCurve] = [
        "linear": .linear,
        "ease": .ease,
        "easeInOut": .easeInOut,
        "snappy": .snappy,
        "smooth": .smooth,
        "easeOutBack": .easeOutBack,
    ]

    public init(custom: [String: BezierCurve] = [:]) {
        self.curves = BezierLibrary.builtIn
        for (k, v) in custom { self.curves[k] = v }
    }

    public func register(name: String, curve: BezierCurve) {
        lock.lock(); defer { lock.unlock() }
        curves[name] = curve
    }

    public func curve(named: String) -> BezierCurve? {
        lock.lock(); defer { lock.unlock() }
        return curves[named]
    }

    public var allNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(curves.keys)
    }
}
