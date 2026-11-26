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

    /// Retourne `true` si une cible AX recouvrant déjà cette boîte porte déjà le même texte recherchable.
    private static func isRedundantWithExisting(
        _ candidate: Rect,
        normalizedText: String,
        existingTargets: [(frame: Rect, matchText: String)]
    ) -> Bool {
        let candRect = candidate.cgRect
        let candArea = candRect.width * candRect.height
        guard candArea > 0 else { return true }
        for existing in existingTargets {
            let existingRect = existing.frame.cgRect
            let existingArea = existingRect.width * existingRect.height
            guard existingArea > 0 else { continue }
            let inter = candRect.intersection(existingRect)
            guard !inter.isNull, !inter.isEmpty else { continue }
            let interArea = inter.width * inter.height
            let candRatio = interArea / candArea
            let existingRatio = interArea / existingArea
            // Même bouton/libellé (tailles comparables) OU conteneur AX qui expose déjà exactement ce texte.
            if candRatio >= 0.6 && (existingRatio >= 0.35 || (!normalizedText.isEmpty && existing.matchText.contains(normalizedText))) {
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
            let scale = min(2.0, max(1.0, 2560.0 / max(1.0, Double(window.frame.width))))
            let config = SCStreamConfiguration()
            config.width = max(1, Int((Double(window.frame.width) * scale).rounded()))
            config.height = max(1, Int((Double(window.frame.height) * scale).rounded()))
            config.showsCursor = false
            box.image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            )
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(750))
        return box.image
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
        maxTargets: Int = 160
    ) -> (targets: [RoadieTarget], metrics: OCRScanMetrics) {
        let startFootprint = currentPhysFootprintKB()
        let startedAt = CFAbsoluteTimeGetCurrent()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        // 0.005 (~7 pt sur un écran 1440p) pour lire aussi le corps de texte 12–14 pt des apps et navigateurs.
        request.minimumTextHeight = 0.005

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
        let existingEntries: [(frame: Rect, matchText: String)] = existingTargets.compactMap { target in
            guard let frame = target.clickFrame ?? target.frame else { return nil }
            return (frame, target.matchText)
        }
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
            let normalizedText = RoadieTarget.normalizedMatchText([text])
            guard !isRedundantWithExisting(frame, normalizedText: normalizedText, existingTargets: existingEntries) else { continue }

            let id = "app:\(pid)/ocr:\(windowID)/\(index)"
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
        let ocrCap = min(160, max(80, config.maxTargets))
        let result = recognize(
            image: image,
            windowFrame: windowFrame,
            windowID: UInt32(windowID),
            pid: pid,
            appName: appName,
            existingTargets: existingTargets,
            maxTargets: ocrCap
        )
        return (result.targets, result.metrics)
    }
}
