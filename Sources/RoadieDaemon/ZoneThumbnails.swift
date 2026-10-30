import AppKit
import Foundation
import RoadieCore
import ScreenCaptureKit

/// Vignettes des zones de ⌥Tab (session 135) : un rectangle de la fenêtre autour de la zone, capturé juste après le
/// clic par ScreenCaptureKit (même autorisation que les vignettes du rail), gardé dans `~/.roadies/zone-thumbs/`.
@MainActor
final class ZoneThumbnails {
    static let shared = ZoneThumbnails()
    /// Taille du rectangle découpé autour de la zone, en points : celle de la vignette des cartes, affichée à
    /// l'échelle 1 pour que le texte reste lisible (essai du 30 octobre 2026 : réduit de moitié, il ne l'était pas).
    static let area = CGSize(width: 300, height: 180)

    /// Densité (pixels par point) de l'écran qui montre la plus grande part de la fenêtre ; 2 par défaut. O(é).
    static func scale(forWindowFrame frame: CGRect) -> CGFloat {
        let screens = NSScreen.screens.compactMap { screen -> (CGRect, CGFloat)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (CGDisplayBounds(number), screen.backingScaleFactor)
        }
        let best = screens.max { $0.0.intersection(frame).width * $0.0.intersection(frame).height
            < $1.0.intersection(frame).width * $1.0.intersection(frame).height }
        return best.flatMap { $0.0.intersects(frame) ? $0.1 : nil } ?? 2
    }

    let folder: String
    private var images: [String: NSImage] = [:]

    init(folder: String = NSString(string: TestEnvironment.launcherFile("zone-thumbs")).expandingTildeInPath) {
        self.folder = folder
    }

    /// Rectangle à découper, relatif à la fenêtre : `area` centré sur la zone, décalé pour rester dans la fenêtre,
    /// réduit à la fenêtre si elle est plus petite. O(1).
    static func crop(zone: CGRect, windowSize: CGSize, area: CGSize = ZoneThumbnails.area) -> CGRect {
        let width = min(area.width, windowSize.width), height = min(area.height, windowSize.height)
        let x = min(max(0, zone.midX - width / 2), max(0, windowSize.width - width))
        let y = min(max(0, zone.midY - height / 2), max(0, windowSize.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Nom de fichier d'une zone : sa clé, sans séparateur de chemin. O(k).
    static func fileName(_ key: String) -> String {
        key.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined() + ".png"
    }

    func path(for key: String) -> String { (folder as NSString).appendingPathComponent(Self.fileName(key)) }

    func image(for key: String) -> NSImage? {
        if let cached = images[key] { return cached }
        let image = NSImage(contentsOfFile: path(for: key))
        images[key] = image
        return image
    }

    /// Photo d'une zone avec la zone entourée en jaune (sélecteur, session 136) ; nil sans photo. O(1).
    func framedImage(for record: ZoneRecord) -> NSImage? {
        guard let photo = image(for: record.key), let crop = record.thumbnailCrop?.cgRect else { return nil }
        guard let ring = Self.ring(zone: record.relative.cgRect, crop: crop) else { return photo }
        return NSImage(size: crop.size, flipped: false) { bounds in
            photo.draw(in: bounds)
            let path = NSBezierPath(roundedRect: ring, xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            NSColor.systemYellow.setStroke()
            path.stroke()
            return true
        }
    }

    /// Entourage de la zone dans la photo, en points de la photo (origine en bas à gauche), avec 3 points de marge,
    /// gardé dans la photo : une zone aussi large qu'elle ne laissait voir que deux traits (essai du 30 octobre 2026).
    /// nil si la zone est hors de la photo. O(1).
    static func ring(zone: CGRect, crop: CGRect) -> CGRect? {
        let local = zone.offsetBy(dx: -crop.minX, dy: -crop.minY)
        let ring = CGRect(x: local.minX, y: crop.height - local.maxY, width: local.width, height: local.height).insetBy(dx: -3, dy: -3)
        let kept = ring.intersection(CGRect(origin: .zero, size: crop.size).insetBy(dx: 1, dy: 1))
        return kept.isNull || kept.isEmpty ? nil : kept
    }

    func remove(_ key: String) {
        images[key] = nil
        try? FileManager.default.removeItem(atPath: path(for: key))
    }

    /// Capture du rectangle autour de la zone (relatif à la fenêtre) ; rend le rectangle découpé, ou nil si la fenêtre
    /// ne se capture pas (autorisation, fenêtre fermée). Une capture à la fois, hors du fil principal pour la copie.
    /// `outcome` reçoit la raison d'un échec (diagnostic, essai du 30 octobre 2026) ou « ok ».
    func capture(key: String, windowID: UInt32, zone: CGRect, windowSize: CGSize, outcome: (String) -> Void = { _ in }) async -> CGRect? {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) } catch {
            outcome("shareable_failed: \(error.localizedDescription)")
            return nil
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            outcome("window_absent (\(content.windows.count) fenêtres)")
            return nil
        }
        let crop = Self.crop(zone: zone, windowSize: windowSize)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = crop
        // Densité réelle de l'écran de la fenêtre : ni agrandissement flou sur un écran à 1 pixel par point, ni perte
        // sur un écran Retina. La mise à l'échelle reste demandée : sans elle, un tampon plus grand que la capture la
        // laissait dans un coin (essai du 30 octobre 2026).
        let scale = Self.scale(forWindowFrame: window.frame)
        configuration.width = Int((crop.width * scale).rounded())
        configuration.height = Int((crop.height * scale).rounded())
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cgImage: CGImage
        do { cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) } catch {
            outcome("capture_failed: \(error.localizedDescription)")
            return nil
        }
        guard !cgImage.looksBlank else {
            outcome("blank \(cgImage.width)x\(cgImage.height)")
            return nil
        }
        outcome("ok")
        let image = NSImage(cgImage: cgImage, size: crop.size)
        images[key] = image
        let target = path(for: key)
        let folder = folder
        let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? data?.write(to: URL(fileURLWithPath: target), options: .atomic)
        }.value
        return crop
    }
}
