import AppKit

/// Icônes et vignettes de la barre réduites une fois, en fond, à la taille exacte du dessin (session 123).
/// Réduire une icône de macOS ou une capture de fenêtre coûte 10 à 30 ms la première fois : payé sur le fil
/// principal, ce coût bloquait la frappe à chaque nouvelle ligne. Le dessin ne fait plus que recopier une
/// petite image prête ; une image pas encore prête est demandée en fond et la barre se redessine à son arrivée.
@MainActor
enum LauncherIconRaster {
    struct Key: Hashable, Sendable {
        let id: String
        let width: Int
        let height: Int
    }

    /// Capacité LRU bornée (Lot L) : évite de garder 800 bitmaps/vignettes en RAM au repos.
    static let limit = 160
    /// Nombre maximal d'icônes préchauffées au démarrage (les autres sont préparées en fond à la demande).
    static let prewarmLimit = 40
    private static var images: [Key: NSImage] = [:]
    private static var lastUsed: [Key: UInt64] = [:]
    private static var useClock: UInt64 = 0
    private static var transientGeneration: UInt64 = 0
    private static var pending: Set<Key> = []
    private static var redrawScheduled = false
    private static let queue = DispatchQueue(label: "roadie.launcher.icon-raster", qos: .userInitiated)
    /// Redessin de la barre ouverte quand une image arrive.
    static var redraw: (@MainActor () -> Void)?

    /// Pixels du plus fin des écrans branchés. O(écrans).
    static var scale: CGFloat { NSScreen.screens.map(\.backingScaleFactor).max() ?? 2 }

    /// Image prête, ou nil après avoir demandé sa préparation en fond. `source` est lu hors du fil principal.
    /// O(1) sur le fil principal.
    static func image(_ id: String, size: CGSize, source: @escaping @Sendable () -> NSImage?) -> NSImage? {
        let key = Key(id: id, width: max(1, Int((size.width * scale).rounded())), height: max(1, Int((size.height * scale).rounded())))
        if let ready = images[key] {
            useClock &+= 1
            lastUsed[key] = useClock
            return ready
        }
        request(key, size: size, source: source)
        return nil
    }

    /// Prépare d'avance au plus `prewarmLimit` icônes de fichiers (applications prioritaires) à la taille des lignes. O(min(n, limit)) en fond.
    static func prewarm(paths: [String], side: CGFloat, maxCount: Int = prewarmLimit) {
        let size = CGSize(width: side, height: side)
        for path in paths.prefix(max(0, maxCount)) {
            _ = image("file:\(path)", size: size) { fileIcon(path) }
        }
    }

    static func isTransient(_ id: String) -> Bool {
        id.hasPrefix("window:") || id.hasPrefix("image:")
    }

    static var currentTransientGeneration: UInt64 { transientGeneration }

    /// Libère immédiatement les vignettes temporaires (`window:*`, `image:*`) à la fermeture de la barre
    /// et incrémente la génération pour empêcher toute préparation en vol de les réinsérer (Lot L).
    static func purgeTransientThumbnails() {
        transientGeneration &+= 1
        let transient = images.keys.filter { isTransient($0.id) }
        for key in transient {
            images.removeValue(forKey: key)
            lastUsed.removeValue(forKey: key)
        }
    }

    /// Insère une entrée dans le cache LRU borné (exposé pour tests unitaires).
    /// Si `expectedTransientGeneration` ne correspond plus à la génération courante pour une clé transitoire,
    /// l'image tardive est ignorée au lieu de réoccuper la mémoire au repos.
    static func store(_ image: NSImage, for key: Key, expectedTransientGeneration: UInt64? = nil, maxLimit: Int = limit) {
        if let expectedTransientGeneration, isTransient(key.id), expectedTransientGeneration != transientGeneration {
            return
        }
        useClock &+= 1
        images[key] = image
        lastUsed[key] = useClock
        evictIfNeeded(maxLimit: maxLimit)
    }

    static var cachedCount: Int { images.count }

    static func contains(id: String) -> Bool {
        images.keys.contains { $0.id == id }
    }

    static func resetForTesting() {
        images.removeAll()
        lastUsed.removeAll()
        pending.removeAll()
        useClock = 0
        transientGeneration = 0
    }

    private static func evictIfNeeded(maxLimit: Int = limit) {
        let cap = max(1, maxLimit)
        while images.count > cap {
            guard let oldest = lastUsed.min(by: { $0.value < $1.value })?.key ?? images.keys.first else { break }
            images.removeValue(forKey: oldest)
            lastUsed.removeValue(forKey: oldest)
        }
    }

    /// Icône d'un fichier par macOS, lien résolu (Safari est un lien vers le système). Sûr hors du fil principal.
    nonisolated static func fileIcon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    private static func request(_ key: Key, size: CGSize, source: @escaping @Sendable () -> NSImage?) {
        guard pending.insert(key).inserted else { return }
        let capturedTransientGeneration = isTransient(key.id) ? transientGeneration : nil
        queue.async {
            let raster: CGImage? = autoreleasepool {
                source().flatMap { rasterize($0, width: key.width, height: key.height) }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    pending.remove(key)
                    guard let raster else { return }
                    store(NSImage(cgImage: raster, size: size), for: key, expectedTransientGeneration: capturedTransientGeneration)
                    scheduleRedraw()
                }
            }
        }
    }

    /// Un seul redessin pour une rafale d'images arrivées ensemble.
    private static func scheduleRedraw() {
        guard !redrawScheduled else { return }
        redrawScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                redrawScheduled = false
                redraw?()
            }
        }
    }

    /// Dessin de l'image entière, proportions gardées et centrée, dans une image de la taille demandée. Fil
    /// quelconque : contexte bitmap propre à l'appel. O(pixels).
    nonisolated static func rasterize(_ image: NSImage, width: Int, height: Int) -> CGImage? {
        guard image.size.width > 0, image.size.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let box = CGSize(width: width, height: height)
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: (box.width - drawn.width) / 2, y: (box.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
