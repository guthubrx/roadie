import AppKit
import Foundation
import RoadieCore
import ScreenCaptureKit

/// Vignettes des zones de ⌥Tab (session 135) : un rectangle de la fenêtre autour de la zone, capturé juste après le
/// clic par ScreenCaptureKit (même autorisation que les vignettes du rail), gardé dans `~/.roadies/zone-thumbs/`.
@MainActor
final class ZoneThumbnails {
    static let shared = ZoneThumbnails()
    /// Taille du rectangle découpé autour de la zone, en points.
    static let area = CGSize(width: 440, height: 260)

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

    func remove(_ key: String) {
        images[key] = nil
        try? FileManager.default.removeItem(atPath: path(for: key))
    }

    /// Capture du rectangle autour de la zone (relatif à la fenêtre) ; rend le rectangle découpé, ou nil si la fenêtre
    /// ne se capture pas (autorisation, fenêtre fermée). Une capture à la fois, hors du fil principal pour la copie.
    func capture(key: String, windowID: UInt32, zone: CGRect, windowSize: CGSize) async -> CGRect? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let crop = Self.crop(zone: zone, windowSize: windowSize)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = crop
        configuration.width = Int(crop.width * 2)
        configuration.height = Int(crop.height * 2)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              !cgImage.looksBlank else { return nil }
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
