import Foundation
import CoreGraphics

// MARK: - CGWindowBoundsCache (SPEC-013 — O(N) batched read)

/// Cache des bounds CG de toutes les fenêtres système. Construit en UN SEUL
/// appel `CGWindowListCopyWindowInfo`, puis répond aux lookups par `cgwid` en
/// O(1). Remplace la pattern précédente où `liveCGBounds(for:)` était appelé
/// dans une boucle (= N² scans).
///
/// Usage typique au boot du daemon :
/// ```
/// let cache = CGWindowBoundsCache.snapshot()
/// for state in registry.allWindows {
///     let cg = cache.bounds(for: state.cgWindowID)
///     // ...
/// }
/// ```
public struct CGWindowBoundsCache: Sendable {
    public let bounds: [UInt32: CGRect]

    public init(bounds: [UInt32: CGRect]) {
        self.bounds = bounds
    }

    /// Bounds CG pour le `cgwid` donné, ou nil si la fenêtre n'est pas listée
    /// (= elle a disparu côté système).
    public func cgBounds(for cgwid: UInt32) -> CGRect? {
        bounds[cgwid]
    }

    /// Capture instantanée de toutes les fenêtres listées par CGWindowList.
    /// Un seul syscall — coût équivalent à un appel direct, mais réutilisable.
    public static func snapshot() -> CGWindowBoundsCache {
        guard let arr = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return CGWindowBoundsCache(bounds: [:])
        }
        var dict: [UInt32: CGRect] = [:]
        dict.reserveCapacity(arr.count)
        for info in arr {
            guard let n = info[kCGWindowNumber as String] as? UInt32,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            dict[n] = CGRect(
                x: b["X"] ?? 0,
                y: b["Y"] ?? 0,
                width: b["Width"] ?? 0,
                height: b["Height"] ?? 0)
        }
        return CGWindowBoundsCache(bounds: dict)
    }
}
