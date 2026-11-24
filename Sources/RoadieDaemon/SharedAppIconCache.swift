import AppKit
import CoreGraphics
import Foundation

/// Cache partagé d'icônes d'applications (Spec 158) pour le NavRail (`StageCardView`)
/// et les cartes de repli (`RailThumbnailStore`).
/// - Détache les bitmaps en sRGB 8 bits (évite de retenir les représentations ICNS 1024×1024).
/// - Court-circuite le flood-fill de détourage lorsque le périmètre est déjà transparent.
/// - Borne la mémoire par éviction progressive (éviction du quart le plus ancien au-delà de `maxCount`).
@MainActor
final class SharedAppIconCache {
    static let shared = SharedAppIconCache()
    static let maxCount = 64
    private static let urlCacheMaxCount = 128

    private struct CacheEntry {
        var image: NSImage
        var lastAccess: UInt64
    }

    private var cleanedIcons: [String: CacheEntry] = [:]
    private var fallbackCards: [String: CacheEntry] = [:]
    private var appURLs: [String: URL] = [:]
    private var accessCounter: UInt64 = 0

    init() {}

    var cleanedIconCount: Int { cleanedIcons.count }
    var fallbackCardCount: Int { fallbackCards.count }

    /// Icône nettoyée 64×64 (sans cadre blanc de bord) pour `bundleID`. O(1) en cache.
    func cleanedIcon(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        accessCounter &+= 1
        if var entry = cleanedIcons[bundleID] {
            entry.lastAccess = accessCounter
            cleanedIcons[bundleID] = entry
            return entry.image
        }
        guard let url = applicationURL(for: bundleID) else { return nil }
        let cleaned = autoreleasepool {
            Self.cleanEdgeWhiteBackground(of: NSWorkspace.shared.icon(forFile: url.path))
        }
        store(cleaned, for: bundleID, in: &cleanedIcons)
        return cleaned
    }

    /// Carte de repli 160×104 sombre avec icône centrée pour `RailThumbnailStore`. O(1) en cache.
    func fallbackCard(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        accessCounter &+= 1
        if var entry = fallbackCards[bundleID] {
            entry.lastAccess = accessCounter
            fallbackCards[bundleID] = entry
            return entry.image
        }
        guard let url = applicationURL(for: bundleID) else { return nil }
        let rendered: NSImage? = autoreleasepool {
            let sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
            return Self.renderFallbackCard(with: sourceIcon)
        }
        guard let rendered else { return nil }
        store(rendered, for: bundleID, in: &fallbackCards)
        return rendered
    }

    /// Libère les caches d'icônes et d'URLs résolues.
    func purge() {
        cleanedIcons.removeAll()
        fallbackCards.removeAll()
        appURLs.removeAll()
    }

    /// Injecte directement une icône nettoyée dans le cache (tests unitaires de capacité/éviction).
    func storeCleanedIconForTesting(_ image: NSImage, for bundleID: String) {
        accessCounter &+= 1
        store(image, for: bundleID, in: &cleanedIcons)
    }

    private func applicationURL(for bundleID: String) -> URL? {
        if let cached = appURLs[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        if appURLs.count >= Self.urlCacheMaxCount {
            appURLs.removeAll(keepingCapacity: true)
        }
        appURLs[bundleID] = url
        return url
    }

    private func store(_ image: NSImage, for key: String, in storage: inout [String: CacheEntry]) {
        if storage[key] == nil, storage.count >= Self.maxCount {
            let evictCount = max(1, Self.maxCount / 4)
            let victims = storage.sorted { $0.value.lastAccess < $1.value.lastAccess }.prefix(evictCount)
            for (victimKey, _) in victims {
                storage.removeValue(forKey: victimKey)
            }
        }
        storage[key] = CacheEntry(image: image, lastAccess: accessCounter)
    }

    /// Détache l'icône en bitmap sRGB 64×64 et supprime un éventuel cadre blanc contigu aux bords.
    /// Si aucun pixel du périmètre n'est blanc, le parcours BFS est entièrement évité.
    nonisolated static func cleanEdgeWhiteBackground(of image: NSImage) -> NSImage {
        let pixelWidth = 64
        let pixelHeight = 64
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)
        var proposed = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        else {
            return image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        @inline(__always)
        func isEdgeWhite(_ pixelIndex: Int) -> Bool {
            let i = pixelIndex * bytesPerPixel
            let alpha = pixels[i + 3]
            return alpha > 0 && pixels[i] >= 238 && pixels[i + 1] >= 238 && pixels[i + 2] >= 238
        }

        // Pré-scan rapide du périmètre : la majorité des icônes macOS ont déjà des bords transparents.
        var hasBorderWhite = false
        for x in 0..<pixelWidth {
            if isEdgeWhite(x) || isEdgeWhite((pixelHeight - 1) * pixelWidth + x) {
                hasBorderWhite = true
                break
            }
        }
        if !hasBorderWhite {
            for y in 1..<(pixelHeight - 1) {
                if isEdgeWhite(y * pixelWidth) || isEdgeWhite(y * pixelWidth + (pixelWidth - 1)) {
                    hasBorderWhite = true
                    break
                }
            }
        }

        if hasBorderWhite {
            let totalPixels = pixelWidth * pixelHeight
            var visited = [UInt8](repeating: 0, count: totalPixels)
            var queue: [Int] = []
            queue.reserveCapacity(256)

            @inline(__always)
            func enqueue(_ x: Int, _ y: Int) {
                guard x >= 0, x < pixelWidth, y >= 0, y < pixelHeight else { return }
                let index = y * pixelWidth + x
                guard visited[index] == 0, isEdgeWhite(index) else { return }
                visited[index] = 1
                queue.append(index)
            }

            for x in 0..<pixelWidth {
                enqueue(x, 0)
                enqueue(x, pixelHeight - 1)
            }
            for y in 1..<(pixelHeight - 1) {
                enqueue(0, y)
                enqueue(pixelWidth - 1, y)
            }

            var cursor = 0
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let i = index * bytesPerPixel
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
                let x = index % pixelWidth
                let y = index / pixelWidth
                enqueue(x + 1, y)
                enqueue(x - 1, y)
                enqueue(x, y + 1)
                enqueue(x, y - 1)
            }
        }

        guard let cleaned = context.makeImage() else {
            return image
        }
        return NSImage(cgImage: cleaned, size: NSSize(width: pixelWidth, height: pixelHeight))
    }

    private static func renderFallbackCard(with sourceIcon: NSImage) -> NSImage? {
        let size = NSSize(width: 160, height: 104)
        let scale: CGFloat = 2
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        let border = NSBezierPath(
            roundedRect: CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1),
            xRadius: 10,
            yRadius: 10
        )
        border.lineWidth = 1
        border.stroke()
        var proposed = CGRect(x: 0, y: 0, width: 104, height: 104)
        if let iconCG = sourceIcon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            context.draw(iconCG, in: CGRect(x: (size.width - 52) / 2, y: (size.height - 52) / 2, width: 52, height: 52))
        } else {
            sourceIcon.draw(
                in: CGRect(x: (size.width - 52) / 2, y: (size.height - 52) / 2, width: 52, height: 52),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: size)
    }
}
