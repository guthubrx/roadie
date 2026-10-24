import AppKit
import CoreImage

/// Fond d’écran flouté de la vue d’ensemble, partagé avec l’aperçu des paramètres pour un rendu identique.
@MainActor
enum OverviewWallpaper {
    /// Voile posé sur le fond flouté, dans la vue comme dans l’aperçu.
    static let veil = NSColor(srgbRed: 10.0 / 255, green: 18.0 / 255, blue: 24.0 / 255, alpha: 0.42)
    /// Flou maximal (100 %), exprimé pour une image de 960 pixels de large.
    static let maximumSigma: CGFloat = 24

    private static var thumbnails: [String: CGImage] = [:]
    private static var blurredCache: (key: String, image: CGImage)?
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Miniature du fond d’écran, décodée une fois par fichier et par taille. nil si l’image est illisible.
    static func thumbnail(for screen: NSScreen, maxPixel: Int) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(modified)#\(maxPixel)"
        if let cached = thumbnails[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        thumbnails[key] = small
        return small
    }

    /// Fond flouté à `percent` (0–100). Même rendu quelle que soit la taille : le flou suit la largeur.
    /// Coût O(pixels de la miniature).
    static func blurred(for screen: NSScreen, percent: Double, maxPixel: Int) -> CGImage? {
        guard let small = thumbnail(for: screen, maxPixel: maxPixel) else { return nil }
        let sigma = maximumSigma * CGFloat(min(100, max(0, percent)) / 100) * CGFloat(small.width) / 960
        let key = "\(ObjectIdentifier(small))#\(sigma)"
        if let cache = blurredCache, cache.key == key { return cache.image }
        guard sigma > 0.05 else { return small }
        let input = CIImage(cgImage: small)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: input.extent)
        guard let image = context.createCGImage(output, from: input.extent) else { return nil }
        if maxPixel >= 960 { blurredCache = (key, image) }
        return image
    }
}
