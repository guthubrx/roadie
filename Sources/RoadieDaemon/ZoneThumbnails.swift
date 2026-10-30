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

    /// Photo d'une zone pour le sélecteur, sans entourage (demande du 30 octobre 2026 : la bordure reste sur la vraie
    /// application) ; nil sans photo. O(1).
    func photo(for record: ZoneRecord) -> NSImage? {
        record.thumbnailCrop == nil ? nil : image(for: record.key)
    }

    func remove(_ key: String) {
        images[key] = nil
        try? FileManager.default.removeItem(atPath: path(for: key))
    }

    /// Capture du rectangle autour de la zone (relatif à la fenêtre) ; rend le rectangle découpé, ou nil si la fenêtre
    /// ne se capture pas (autorisation, fenêtre fermée). `outcome` reçoit la raison d'un échec (diagnostic) ou « ok ».
    func capture(key: String, windowID: UInt32, zone: CGRect, windowSize: CGSize, outcome: (String) -> Void = { _ in }) async -> CGRect? {
        let crop = Self.crop(zone: zone, windowSize: windowSize)
        guard let image = await Self.windowImage(windowID, region: crop, outcome: outcome) else { return nil }
        await store(image, key: key, crop: crop)
        return crop
    }

    /// Délai minimal entre deux rafraîchissements des photos d'une même fenêtre.
    nonisolated static let refreshInterval: TimeInterval = 10
    private var refreshedAt: [UInt32: Date] = [:]

    /// Rafraîchissement dû : jamais fait, ou plus vieux que `refreshInterval`. O(1).
    nonisolated static func isRefreshDue(last: Date?, now: Date, interval: TimeInterval = refreshInterval) -> Bool {
        last.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    /// Fenêtre quittée (session 136) : ses zones sont reprises en photo, dans l'état où on la laisse, par une seule
    /// capture de la fenêtre découpée pour chaque zone. Au plus une fois par `refreshInterval` par fenêtre ; rien
    /// pour une fenêtre sans zone. Aucune surveillance continue : seulement au changement de fenêtre active.
    func windowLeft(_ windowID: UInt32, now: Date = Date()) {
        let zones = ZoneHistory.shared.records.filter { $0.windowID == windowID }
        guard !zones.isEmpty, Self.isRefreshDue(last: refreshedAt[windowID], now: now) else { return }
        refreshedAt = refreshedAt.filter { now.timeIntervalSince($0.value) < Self.refreshInterval }
        refreshedAt[windowID] = now
        Task { @MainActor in
            guard let window = await Self.windowImage(windowID, region: nil, outcome: { _ in }) else { return }
            let size = window.size
            let pixelsPerPoint = CGFloat(window.cgImage.width) / max(1, size.width)
            for zone in zones {
                let crop = Self.crop(zone: zone.relative.cgRect, windowSize: size)
                let pixels = CGRect(x: crop.minX * pixelsPerPoint, y: crop.minY * pixelsPerPoint,
                                    width: crop.width * pixelsPerPoint, height: crop.height * pixelsPerPoint).integral
                guard let part = window.cgImage.cropping(to: pixels) else { continue }
                await store((part, crop.size), key: zone.key, crop: crop)
                ZoneHistory.shared.setThumbnail(crop, for: zone.key)
            }
        }
    }

    /// Image d'une fenêtre à l'écran, entière (`region` nil) ou d'une région (points, relatifs à la fenêtre), à la
    /// densité de son écran ; nil si elle ne se capture pas ou paraît vide. Rend aussi sa taille en points.
    private static func windowImage(_ windowID: UInt32, region: CGRect?, outcome: (String) -> Void) async -> (cgImage: CGImage, size: CGSize)? {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) } catch {
            outcome("shareable_failed: \(error.localizedDescription)")
            return nil
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            outcome("window_absent (\(content.windows.count) fenêtres)")
            return nil
        }
        let area = region ?? CGRect(origin: .zero, size: window.frame.size)
        let configuration = SCStreamConfiguration()
        if let region { configuration.sourceRect = region }
        // Densité réelle de l'écran de la fenêtre : ni agrandissement flou sur un écran à 1 pixel par point, ni perte
        // sur un écran Retina. La mise à l'échelle reste demandée : sans elle, un tampon plus grand que la capture la
        // laissait dans un coin (essai du 30 octobre 2026).
        let scale = scale(forWindowFrame: window.frame)
        configuration.width = Int((area.width * scale).rounded())
        configuration.height = Int((area.height * scale).rounded())
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        } catch {
            outcome("capture_failed: \(error.localizedDescription)")
            return nil
        }
        guard !image.looksBlank else {
            outcome("blank \(image.width)x\(image.height)")
            return nil
        }
        outcome("ok")
        return (image, area.size)
    }

    /// Photo gardée en mémoire et écrite hors du fil principal.
    private func store(_ image: (cgImage: CGImage, size: CGSize), key: String, crop: CGRect) async {
        images[key] = NSImage(cgImage: image.cgImage, size: crop.size)
        let target = path(for: key)
        let folder = folder
        let data = NSBitmapImageRep(cgImage: image.cgImage).representation(using: .png, properties: [:])
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? data?.write(to: URL(fileURLWithPath: target), options: .atomic)
        }.value
    }
}

/// Bordure posée sur la vraie application (session 136) : autour de la zone choisie dans ⌥Tab si sa fenêtre est à
/// l'écran, puis un instant autour de la zone cliquée à l'arrivée. Fenêtre transparente, sans clic ni clavier.
@MainActor
final class ZoneHighlight {
    static let shared = ZoneHighlight()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// Contour autour de `zone` (coordonnées de l'accessibilité), 4 points de marge ; retiré après `duration`. O(1).
    func show(_ zone: CGRect, duration: TimeInterval? = nil) {
        hideTask?.cancel()
        let frame = RoadieScreenCoordinate.axRectToNS(zone.insetBy(dx: -4, dy: -4))
        let panel = panel ?? Self.makePanel()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        if let duration {
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let border = NSView()
        border.wantsLayer = true
        border.layer?.borderWidth = 3
        border.layer?.cornerRadius = 6
        border.layer?.borderColor = NSColor.systemYellow.cgColor
        border.autoresizingMask = [.width, .height]
        panel.contentView = border
        return panel
    }
}
