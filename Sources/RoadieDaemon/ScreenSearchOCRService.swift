import CoreGraphics
import Darwin
import Foundation
import RoadieCore
import ScreenCaptureKit
import Vision

/// Métriques mesurées lors d'une passe OCR locale `Vision` (Spec 169).
/// Aucune chaîne reconnue n'est stockée dans ces métriques (zéro donnée privée dans les logs).
public struct OCRScanMetrics: Codable, Equatable, Sendable {
    public let elapsedMs: Int
    public let imageWidth: Int
    public let imageHeight: Int
    public let observationsCount: Int
    public let retainedTargets: Int
    public let footprintDeltaKB: Int

    public init(
        elapsedMs: Int,
        imageWidth: Int,
        imageHeight: Int,
        observationsCount: Int,
        retainedTargets: Int,
        footprintDeltaKB: Int
    ) {
        self.elapsedMs = elapsedMs
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.observationsCount = observationsCount
        self.retainedTargets = retainedTargets
        self.footprintDeltaKB = footprintDeltaKB
    }
}

/// Boîte englobante exacte d'un mot reconnu par Vision dans une ligne OCR (Spec 169).
public struct OCRWordBox: Equatable, Sendable {
    public let normalized: String
    public let frame: Rect

    public init(normalized: String, frame: Rect) {
        self.normalized = normalized
        self.frame = frame
    }
}

/// Table mémoire légère associant chaque cible OCR (`app:<pid>/ocr:<win>/<idx>`) aux boîtes exactes
/// de ses mots (`VNRecognizedText.boundingBox(for:)`). Vidée au début de chaque nouveau scan.
public final class ScreenSearchOCRWordMap: @unchecked Sendable {
    public static let shared = ScreenSearchOCRWordMap()

    private let lock = NSLock()
    private var entries: [String: [OCRWordBox]] = [:]

    public init() {}

    public func reset() {
        lock.withLock { entries.removeAll(keepingCapacity: true) }
    }

    public func register(targetID: String, words: [OCRWordBox]) {
        guard !words.isEmpty else { return }
        lock.withLock { entries[targetID] = words }
    }

    public func highlightFrame(for targetID: String, query: String) -> Rect? {
        let words = lock.withLock { entries[targetID] }
        guard let words, !words.isEmpty else { return nil }
        return Self.matchingFrame(in: words, query: query)
    }

    /// Trouve la boîte exacte du mot (ou de la séquence contiguë minimale de mots) correspondant à `query`.
    public static func matchingFrame(in words: [OCRWordBox], query: String) -> Rect? {
        let needle = TargetSearchModel.compact(query)
        guard !needle.isEmpty, needle != "*", needle != ";" else { return nil }
        // 1. Correspondance directe sur un mot unique (cas le plus courant, ex. « localement »).
        if let exact = words.first(where: { $0.normalized == needle }) {
            return exact.frame
        }
        if let partial = words.first(where: { $0.normalized.contains(needle) }) {
            return partial.frame
        }
        // 2. Requête multi-mots (ex. « texte localement ») : plus petite plage contiguë couvrant `needle`.
        for start in words.indices {
            var combined = ""
            var union = words[start].frame.cgRect
            for end in start..<min(words.count, start + 8) {
                combined += words[end].normalized
                union = union.union(words[end].frame.cgRect)
                if combined.contains(needle) {
                    return Rect(union)
                }
            }
        }
        return nil
    }
}

/// Module isolé (Spec 169) : OCR 100 % local via Apple Vision (`VNRecognizeTextRequest`).
/// Zéro timer, zéro mémoire et zéro capture tant que `experimental.app_targets.ocr_fallback == false`.
/// Quand `ocr_fallback_threshold == 0` (défaut), complète toujours l'Accessibilité sur chaque fenêtre
/// visible afin de trouver et surligner n'importe quel texte affiché à l'écran.
public enum ScreenSearchOCRService {
    /// Décide si une passe OCR doit tourner sur cette fenêtre selon la configuration et le nombre
    /// de cibles AX déjà collectées. `ocr_fallback_threshold == 0` signifie toujours actif.
    public static func shouldRunOCR(config: AppTargetsConfig, existingAXCount: Int) -> Bool {
        guard config.ocrFallbackEnabled else { return false }
        return config.ocrFallbackThreshold == 0 || existingAXCount <= config.ocrFallbackThreshold
    }

    /// Convertit une boîte normalisée Vision (`[0,1]×[0,1]`, origine en bas-gauche) vers le repère
    /// Accessibilité macOS (points logiques, origine en haut-gauche, compatible coordonnées négatives).
    public static func normalizedBoxToAXRect(_ box: CGRect, in windowFrame: Rect) -> Rect {
        let clampedX = min(max(box.minX, 0), 1)
        let clampedY = min(max(box.minY, 0), 1)
        let clampedW = min(max(box.width, 0), 1 - clampedX)
        let clampedH = min(max(box.height, 0), 1 - clampedY)
        let x = windowFrame.x + Double(clampedX) * windowFrame.width
        let y = windowFrame.y + Double(1.0 - clampedY - clampedH) * windowFrame.height
        let width = Double(clampedW) * windowFrame.width
        let height = Double(clampedH) * windowFrame.height
        return Rect(x: x, y: y, width: width, height: height)
    }

    /// Retourne `true` si la boîte OCR correspond sensiblement à la même zone qu'une cible AX existante
    /// (recouvrement mutuel : évite d'écarter une ligne de texte située dans un grand conteneur AX).
    public static func overlapsExisting(_ candidate: Rect, existingFrames: [Rect]) -> Bool {
        let candRect = candidate.cgRect
        let candArea = candRect.width * candRect.height
        guard candArea > 0 else { return true }
        for existing in existingFrames {
            let existingRect = existing.cgRect
            let existingArea = existingRect.width * existingRect.height
            guard existingArea > 0 else { continue }
            let inter = candRect.intersection(existingRect)
            guard !inter.isNull, !inter.isEmpty else { continue }
            let interArea = inter.width * inter.height
            if (interArea / candArea) >= 0.6 && (interArea / existingArea) >= 0.35 {
                return true
            }
        }
        return false
    }

    /// Empreinte mémoire physique du processus courant (`phys_footprint`) en Ko, pour mesurer la charge OCR.
    public static func currentPhysFootprintKB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1024)
    }

    /// Liste en un seul appel ScreenCaptureKit les fenêtres visibles capturables (0 appel si non autorisé).
    public static func shareableWindowsByID() -> [CGWindowID: SCWindow] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        final class Box: @unchecked Sendable { var windows: [CGWindowID: SCWindow] = [:] }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
            var map: [CGWindowID: SCWindow] = [:]
            map.reserveCapacity(content.windows.count)
            for window in content.windows {
                map[window.windowID] = window
            }
            box.windows = map
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(450))
        return box.windows
    }

    /// Capture ponctuelle d'une fenêtre via ScreenCaptureKit, strictement conditionnée à
    /// `CGPreflightScreenCaptureAccess()` (zéro popup système si refusé, zéro warning deprecated).
    /// Utilise `ignoreShadowsSingleWindow = true` et `scalesToFit = true` afin que l'image capturée
    /// corresponde exactement 1:1 à `window.frame` (sans marge d'ombre ni bande vide sur écran 1x).
    /// Appelée uniquement depuis les fils de scan hors `@MainActor` ; bornée à 750 ms.
    public static func captureWindowImage(windowID: CGWindowID, preloadedWindow: SCWindow? = nil) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        final class Box: @unchecked Sendable { var image: CGImage? }
        final class WindowRef: @unchecked Sendable {
            let window: SCWindow?
            init(_ window: SCWindow?) { self.window = window }
        }
        let box = Box()
        let ref = WindowRef(preloadedWindow)
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            let targetWindow: SCWindow?
            if let preloaded = ref.window {
                targetWindow = preloaded
            } else {
                let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                targetWindow = content?.windows.first(where: { $0.windowID == windowID })
            }
            guard let window = targetWindow else { return }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // Sans `ignoreShadowsSingleWindow`, macOS ajoute 50-100 px d'ombre autour de la fenêtre.
            // Sans `scalesToFit`, une fenêtre 1x n'est pas agrandie et se retrouve décalée dans un coin.
            config.ignoreShadowsSingleWindow = true
            config.scalesToFit = true
            config.preservesAspectRatio = false
            config.showsCursor = false
            let pixelScale = max(1.0, Double(filter.pointPixelScale))
            let rawW = Double(window.frame.width) * pixelScale
            let rawH = Double(window.frame.height) * pixelScale
            let downscale = min(1.0, 2560.0 / max(1.0, max(rawW, rawH)))
            config.width = max(1, Int((rawW * downscale).rounded()))
            config.height = max(1, Int((rawH * downscale).rounded()))
            box.image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(750))
        return box.image
    }

    /// Extrait les boîtes englobantes exactes mot par mot d'une observation Vision (`boundingBox(for:)`).
    private static func extractWordBoxes(from candidate: VNRecognizedText, in windowFrame: Rect) -> [OCRWordBox] {
        let text = candidate.string
        guard !text.isEmpty else { return [] }
        var result: [OCRWordBox] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring else { return }
            let compact = TargetSearchModel.compact(substring)
            guard !compact.isEmpty else { return }
            guard let box = try? candidate.boundingBox(for: range) else { return }
            let frame = normalizedBoxToAXRect(box.boundingBox, in: windowFrame)
            guard frame.width >= 4, frame.height >= 4 else { return }
            result.append(OCRWordBox(normalized: compact, frame: frame))
        }
        return result
    }

    /// Exécute une passe OCR locale Vision (`.fast`, sans correction linguistique coûteuse) sur `image`
    /// et renvoie les cibles `RoadieTarget` prêtes pour la recherche à l'écran + les métriques mesurées.
    public static func recognize(
        image: CGImage,
        windowFrame: Rect,
        windowID: UInt32,
        pid: pid_t,
        appName: String,
        existingTargets: [RoadieTarget] = [],
        maxTargets: Int = 240,
        wordMap: ScreenSearchOCRWordMap? = nil
    ) -> (targets: [RoadieTarget], metrics: OCRScanMetrics) {
        let startFootprint = currentPhysFootprintKB()
        let startedAt = CFAbsoluteTimeGetCurrent()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        // 0.004 (~5-6 pt sur un écran 1440p) pour lire aussi le corps de texte 11-14 pt des apps et navigateurs.
        request.minimumTextHeight = 0.004

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            let delta = max(0, currentPhysFootprintKB() - startFootprint)
            return ([], OCRScanMetrics(
                elapsedMs: elapsed,
                imageWidth: image.width,
                imageHeight: image.height,
                observationsCount: 0,
                retainedTargets: 0,
                footprintDeltaKB: delta
            ))
        }

        let observations = request.results ?? []
        let existingFrames = existingTargets.compactMap { $0.clickFrame ?? $0.frame }
        let subtitle = appName.isEmpty ? "OCR" : "OCR · \(appName)"
        var retained: [RoadieTarget] = []
        retained.reserveCapacity(min(observations.count, maxTargets))

        for (index, observation) in observations.enumerated() {
            guard retained.count < maxTargets else { break }
            guard let top = observation.topCandidates(1).first else { continue }
            let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { continue }
            let frame = normalizedBoxToAXRect(observation.boundingBox, in: windowFrame)
            guard frame.width >= 6, frame.height >= 6 else { continue }
            // Ne déduplique que contre un contrôle AX de taille comparable (bouton/onglet),
            // jamais contre un grand conteneur (bulle de discussion, panneau, carte) afin de
            // conserver un surlignage précis au mot près.
            guard !overlapsExisting(frame, existingFrames: existingFrames) else { continue }

            let id = "app:\(pid)/ocr:\(windowID)/\(index)"
            if let wordMap {
                let words = extractWordBoxes(from: top, in: windowFrame)
                wordMap.register(targetID: id, words: words)
            }
            retained.append(RoadieTarget(
                id: id,
                kind: .appElement,
                title: text,
                subtitle: subtitle,
                source: .app,
                matchText: RoadieTarget.normalizedMatchText([text, subtitle, "ocr"]),
                scope: TargetScopeSnapshot(windowId: windowID),
                frame: frame,
                actions: [.click, .doubleClick, .rightClick, .commandClick],
                clickFrame: frame
            ))
        }

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        let delta = max(0, currentPhysFootprintKB() - startFootprint)
        let metrics = OCRScanMetrics(
            elapsedMs: elapsed,
            imageWidth: image.width,
            imageHeight: image.height,
            observationsCount: observations.count,
            retainedTargets: retained.count,
            footprintDeltaKB: delta
        )
        return (retained, metrics)
    }

    /// Point d'entrée pour `LiveAppTargetProvider` : capture + OCR seulement si le module est activé
    /// et si le seuil (`0` = toujours, `1..30` = si `<= seuil`) l'autorise.
    public static func fallbackTargetsIfNeeded(
        config: AppTargetsConfig,
        existingTargets: [RoadieTarget],
        windowID: CGWindowID,
        windowFrame: Rect,
        pid: pid_t,
        appName: String,
        preloadedWindow: SCWindow? = nil
    ) -> (targets: [RoadieTarget], metrics: OCRScanMetrics?) {
        guard shouldRunOCR(config: config, existingAXCount: existingTargets.count) else { return ([], nil) }
        guard windowFrame.width >= 40, windowFrame.height >= 40 else { return ([], nil) }
        guard let image = captureWindowImage(windowID: windowID, preloadedWindow: preloadedWindow) else { return ([], nil) }
        let ocrCap = min(240, max(120, config.maxTargets))
        let result = recognize(
            image: image,
            windowFrame: windowFrame,
            windowID: UInt32(windowID),
            pid: pid,
            appName: appName,
            existingTargets: existingTargets,
            maxTargets: ocrCap,
            wordMap: .shared
        )
        return (result.targets, result.metrics)
    }
}
