import AppKit
import CoreGraphics
import Foundation
import RoadieCore
import RoadieStages
import ScreenCaptureKit

/// Cache des vignettes du rail (SPEC-016 FR-024, FR-029, FR-043).
/// - Les vignettes sont réduites à 2x la largeur d'affichage de la carte.
/// - La capture est asynchrone (ScreenCaptureKit) : le rendu ne l'attend jamais et lit seulement le cache.
/// - Sans permission Screen Recording, ou si la capture échoue, la carte affiche l'icône de l'application.
/// - Une capture vide (noire ou transparente) est ignorée.
@MainActor
final class RailThumbnailStore {
    /// Rail et sélecteur réutilisent les mêmes images et le même budget de capture par processus.
    static let shared = RailThumbnailStore(onMissingPermission: {
        EventLog().append(RoadieEvent(type: "rail_screen_recording_missing", details: ["effect": "app_icon_fallback"]))
    })
    /// Incrémenté à chaque nouvelle vignette : le rail l'inclut dans sa signature pour savoir qu'il doit redessiner.
    private(set) var version = 0
    private var revisions: [WindowID: Int] = [:]

    private var images: [WindowID: NSImage] = [:]
    private var fallbacks: [WindowID: NSImage] = [:]
    private var icons: [String: NSImage] = [:]
    private var signatures: [WindowID: String] = [:]
    private var capturedAt: [WindowID: Date] = [:]
    private var attemptedAt: [WindowID: Date] = [:]
    private var inFlight: Set<WindowID> = []
    private var retainedByOwner: [String: Set<WindowID>] = [:]
    /// Fenêtres ScreenCaptureKit déjà énumérées (SPEC-048 C-01) : un lot ne réénumère tout le
    /// système que si une fenêtre demandée manque. Une fenêtre absente n'est recherchée à nouveau
    /// qu'après `absentRetryInterval` (membres gardés 15 s après fermeture).
    private var shareableWindows: [WindowID: SCWindow] = [:]
    private var absentUntil: [WindowID: Date] = [:]
    private let absentRetryInterval: TimeInterval = 5
    private var didLogMissingPermission = false
    private let drmRefreshInterval: TimeInterval = 2
    private let refreshInterval: TimeInterval = 5
    private let onMissingPermission: () -> Void

    init(onMissingPermission: @escaping () -> Void = {}) {
        self.onMissingPermission = onMissingPermission
    }

    /// Image à afficher pour chaque membre : vignette en cache, sinon icône de l'application. Ne capture jamais.
    // O(m) - m = nombre de membres demandés.
    func images(for members: [PersistentStageMember]) -> [WindowID: NSImage] {
        var result: [WindowID: NSImage] = [:]
        for member in members {
            invalidateIfAppChanged(member)
            if let image = images[member.windowID] {
                result[member.windowID] = image
            } else if let icon = fallbackIcon(for: member) {
                fallbacks[member.windowID] = icon
                result[member.windowID] = icon
            }
        }
        return result
    }

    func prune(keeping requested: Set<WindowID>, owner: String = "rail") {
        if requested.isEmpty { retainedByOwner.removeValue(forKey: owner) }
        else { retainedByOwner[owner] = requested }
        // O(n) : un consommateur ne purge pas les vignettes encore utilisées par l'autre.
        let ids = retainedByOwner.values.reduce(into: Set<WindowID>()) { $0.formUnion($1) }
        revisions = revisions.filter { ids.contains($0.key) }
        images = images.filter { ids.contains($0.key) }
        fallbacks = fallbacks.filter { ids.contains($0.key) }
        signatures = signatures.filter { ids.contains($0.key) }
        shareableWindows = shareableWindows.filter { ids.contains($0.key) }
        absentUntil = absentUntil.filter { ids.contains($0.key) }
        capturedAt = capturedAt.filter { ids.contains($0.key) }
        attemptedAt = attemptedAt.filter { ids.contains($0.key) }
    }

    /// Une capture n'invalide que les écrans qui représentent cette fenêtre. O(m).
    func revisionSignature(for ids: [WindowID]) -> String {
        ids.map { "\($0.rawValue):\(revisions[$0, default: 0])" }.joined(separator: ",")
    }

    func hasCapturedImage(for windowID: WindowID) -> Bool { images[windowID] != nil }

    func cachedImage(for windowID: WindowID) -> NSImage? {
        images[windowID] ?? fallbacks[windowID]
    }

    /// Lance en arrière-plan la capture des vignettes périmées, au plus `budget` fenêtres, les plus anciennes d'abord.
    /// Un seul lot à la fois. Les fenêtres protégées (contenu DRM juste après un changement de focus) sont ignorées.
    // O(m log m) - m = nombre de membres affichés.
    /// `liveFrames` : cadres du relevé courant ; ils fixent les proportions de la capture.
    func requestCaptures(
        for members: [PersistentStageMember],
        protectedWindowIDs: Set<WindowID>,
        liveFrames: [WindowID: Rect],
        displayWidth: CGFloat,
        budget: Int
    ) {
        guard budget > 0, inFlight.isEmpty else { return }
        let now = Date()
        let due = members
            .filter { !protectedWindowIDs.contains($0.windowID) && isDue($0, now: now) }
            .sorted { lastActivity(of: $0.windowID) < lastActivity(of: $1.windowID) }
            .prefix(budget)
        guard !due.isEmpty else { return }
        let ids = due.map(\.windowID)
        let sizes = Dictionary(due.map {
            ($0.windowID, (liveFrames[$0.windowID] ?? $0.frame).cgRect.size)
        }, uniquingKeysWith: { first, _ in first })
        inFlight = Set(ids)
        Task { [weak self] in
            await self?.capture(ids, sizes: sizes, displayWidth: displayWidth)
        }
    }

    private func isDue(_ member: PersistentStageMember, now: Date) -> Bool {
        let interval = Self.isDRMSensitiveBundle(member.bundleID) ? drmRefreshInterval : refreshInterval
        return now.timeIntervalSince(lastActivity(of: member.windowID)) >= interval
    }

    private func lastActivity(of windowID: WindowID) -> Date {
        max(capturedAt[windowID] ?? .distantPast, attemptedAt[windowID] ?? .distantPast)
    }

    /// Vrai si une fenêtre demandée n'est ni en cache ni en attente après une absence. O(k).
    nonisolated static func needsEnumeration(
        requested ids: [WindowID],
        cached: Set<WindowID>,
        absentUntil: [WindowID: Date],
        now: Date
    ) -> Bool {
        ids.contains { !cached.contains($0) && (absentUntil[$0].map { now >= $0 } ?? true) }
    }

    private func capture(_ ids: [WindowID], sizes: [WindowID: CGSize], displayWidth: CGFloat) async {
        defer { inFlight.removeAll() }
        let startedAt = Date()
        ids.forEach { attemptedAt[$0] = startedAt }
        // Preflight sans fenêtre de demande : l'absence de permission est journalisée une seule fois.
        guard CGPreflightScreenCaptureAccess() else {
            if !didLogMissingPermission {
                didLogMissingPermission = true
                onMissingPermission()
            }
            return
        }
        if Self.needsEnumeration(requested: ids, cached: Set(shareableWindows.keys),
                                 absentUntil: absentUntil, now: startedAt) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
                return
            }
            shareableWindows = Dictionary(
                content.windows.map { (WindowID(rawValue: $0.windowID), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for id in ids where shareableWindows[id] == nil {
                absentUntil[id] = startedAt.addingTimeInterval(absentRetryInterval)
            }
        }
        for id in ids {
            guard let window = shareableWindows[id], let size = sizes[id] else { continue }
            guard let cgImage = await screenshot(of: window, size: size, displayWidth: displayWidth) else {
                // Fenêtre fermée ou changée : la prochaine demande la recherche à nouveau.
                shareableWindows.removeValue(forKey: id)
                continue
            }
            guard !cgImage.looksBlank else { continue }
            // Taille en points = pixels / 2 : la vignette garde sa netteté sur un écran Retina.
            images[id] = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
            capturedAt[id] = Date()
            version += 1
            revisions[id] = version
        }
    }

    private func screenshot(of window: SCWindow, size: CGSize, displayWidth: CGFloat) async -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let pixelWidth = min(displayWidth * 2, size.width * 2)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(pixelWidth.rounded()))
        configuration.height = max(1, Int((pixelWidth * size.height / size.width).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    // Le titre change souvent pour une même fenêtre (prompt de terminal, onglet) : seul le bundle identifie l'application.
    private func invalidateIfAppChanged(_ member: PersistentStageMember) {
        guard signatures[member.windowID] != member.bundleID else { return }
        images.removeValue(forKey: member.windowID)
        fallbacks.removeValue(forKey: member.windowID)
        capturedAt.removeValue(forKey: member.windowID)
        signatures[member.windowID] = member.bundleID
    }

    private func fallbackIcon(for member: PersistentStageMember) -> NSImage? {
        if let cached = icons[member.bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: member.bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage ?? NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)
        let size = NSSize(width: 160, height: 104)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        let border = NSBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
        icon.draw(
            in: CGRect(x: (size.width - 52) / 2, y: (size.height - 52) / 2, width: 52, height: 52),
            from: CGRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        icons[member.bundleID] = image
        return image
    }

    nonisolated static func isDRMSensitiveBundle(_ bundleID: String) -> Bool {
        [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "org.mozilla.firefox",
        ].contains(bundleID)
    }
}

extension CGImage {
    /// Vrai pour une capture sans contenu utile : quasi transparente, ou presque entièrement noire et uniforme.
    /// Calculé une seule fois, à la capture (jamais au rendu).
    var looksBlank: Bool {
        guard width > 0, height > 0 else { return true }

        let sampleWidth = 32
        let sampleHeight = 32
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: sampleWidth,
                  height: sampleHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return true }

        context.interpolationQuality = .low
        context.draw(self, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var opaqueSamples = 0
        var darkSamples = 0
        var brightSamples = 0
        var totalSamples = 0
        var previousLuma: Int?
        var lumaChanges = 0
        var index = 0
        while index + 3 < pixels.count {
            let r = Int(pixels[index])
            let g = Int(pixels[index + 1])
            let b = Int(pixels[index + 2])
            let alpha = Int(pixels[index + 3])
            if alpha > 8 {
                opaqueSamples += 1
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                if luma < 10 { darkSamples += 1 }
                if luma > 32 { brightSamples += 1 }
                if let previousLuma, abs(previousLuma - luma) > 8 { lumaChanges += 1 }
                previousLuma = luma
            }
            totalSamples += 1
            index += bytesPerPixel
        }
        guard totalSamples > 0 else { return true }
        // Capture transparente : moins de 2 % de pixels visibles.
        if Double(opaqueSamples) / Double(totalSamples) < 0.02 {
            return true
        }
        return Double(darkSamples) / Double(totalSamples) > 0.96
            && Double(brightSamples) / Double(totalSamples) < 0.01
            && lumaChanges < 8
    }
}
