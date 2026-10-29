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

    /// Au-delà, le cache repart de zéro : quelques centaines d'icônes de 64 pixels, moins de 10 Mo.
    static let limit = 800
    private static var images: [Key: NSImage] = [:]
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
        if let ready = images[key] { return ready }
        request(key, size: size, source: source)
        return nil
    }

    /// Prépare d'avance les icônes de fichiers (applications du catalogue) à la taille des lignes. O(n) en fond.
    static func prewarm(paths: [String], side: CGFloat) {
        let size = CGSize(width: side, height: side)
        for path in paths {
            _ = image("file:\(path)", size: size) { fileIcon(path) }
        }
    }

    /// Icône d'un fichier par macOS, lien résolu (Safari est un lien vers le système). Sûr hors du fil principal.
    nonisolated static func fileIcon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    private static func request(_ key: Key, size: CGSize, source: @escaping @Sendable () -> NSImage?) {
        guard pending.insert(key).inserted else { return }
        queue.async {
            let raster = source().flatMap { rasterize($0, width: key.width, height: key.height) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    pending.remove(key)
                    guard let raster else { return }
                    if images.count >= limit { images.removeAll(keepingCapacity: true) }
                    images[key] = NSImage(cgImage: raster, size: size)
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
