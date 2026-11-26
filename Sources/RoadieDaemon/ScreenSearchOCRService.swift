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

/// Module isolé (Spec 169) : repli OCR 100 % local via Apple Vision (`VNRecognizeTextRequest`).
/// Zéro timer, zéro mémoire et zéro capture tant que `experimental.app_targets.ocr_fallback == false`
/// ou tant que le scan Accessibilité a déjà trouvé suffisamment de cibles (`> ocr_fallback_threshold`).
public enum ScreenSearchOCRService {
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

    /// Retourne `true` si la boîte OCR recouvre majoritairement une cible AX déjà trouvée (>= 60 %).
    public static func overlapsExisting(_ candidate: Rect, existingFrames: [Rect]) -> Bool {
        let candRect = candidate.cgRect
        let candArea = candRect.width * candRect.height
        guard candArea > 0 else { return true }
        for existing in existingFrames {
            let inter = candRect.intersection(existing.cgRect)
            guard !inter.isNull, !inter.isEmpty else { continue }
            let ratio = (inter.width * inter.height) / candArea
            if ratio >= 0.6 {
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

    /// Capture ponctuelle d'une fenêtre via ScreenCaptureKit, strictement conditionnée à
    /// `CGPreflightScreenCaptureAccess()` (zéro popup système si refusé, zéro warning deprecated).
    /// Appelée uniquement depuis les fils de scan hors `@MainActor` ; bornée à 350 ms.
    public static func captureWindowImage(windowID: CGWindowID) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        final class Box: @unchecked Sendable { var image: CGImage? }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let window = content.windows.first(where: { $0.windowID == windowID })
            else { return }
            let config = SCStreamConfiguration()
            config.width = max(1, Int(window.frame.width))
            config.height = max(1, Int(window.frame.height))
            config.showsCursor = false
            box.image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            )
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(350))
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
        maxTargets: Int = 80
    ) -> (targets: [RoadieTarget], metrics: OCRScanMetrics) {
        let startFootprint = currentPhysFootprintKB()
        let startedAt = CFAbsoluteTimeGetCurrent()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.minimumTextHeight = 0.012

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
            guard !overlapsExisting(frame, existingFrames: existingFrames) else { continue }

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

    /// Point d'entrée de repli pour `LiveAppTargetProvider` : capture + OCR seulement si le module est activé
    /// et si le scan AX n'a trouvé que peu ou pas de cibles sur la fenêtre.
    public static func fallbackTargetsIfNeeded(
        config: AppTargetsConfig,
        existingTargets: [RoadieTarget],
        windowID: CGWindowID,
        windowFrame: Rect,
        pid: pid_t,
        appName: String
    ) -> (targets: [RoadieTarget], metrics: OCRScanMetrics?) {
        guard config.ocrFallbackEnabled else { return ([], nil) }
        guard existingTargets.count <= config.ocrFallbackThreshold else { return ([], nil) }
        guard windowFrame.width >= 40, windowFrame.height >= 40 else { return ([], nil) }
        guard let image = captureWindowImage(windowID: windowID) else { return ([], nil) }
        let remaining = max(1, config.maxTargets - existingTargets.count)
        let result = recognize(
            image: image,
            windowFrame: windowFrame,
            windowID: UInt32(windowID),
            pid: pid,
            appName: appName,
            existingTargets: existingTargets,
            maxTargets: min(80, remaining)
        )
        return (result.targets, result.metrics)
    }
}
