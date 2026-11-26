import AppKit
import CoreGraphics
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 169 — Repli OCR local macOS Vision (`ocr_fallback`) + mesure réelle de charge CPU/RAM.
@Suite(.serialized)
struct Spec169ScreenSearchOCRTests {
    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec169-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Génère une image synthétique réaliste avec des boutons/textes nets pour tester et mesurer Vision.
    private func renderSyntheticWindowImage(width: Int, height: Int, labels: [(text: String, x: CGFloat, y: CGFloat)]) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Fond clair façon interface native/web
        ctx.setFillColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        for item in labels {
            let pill = CGRect(x: item.x - 16, y: item.y - 10, width: 260, height: 52)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
            NSColor.darkGray.setStroke()
            let border = NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10)
            border.lineWidth = 2
            border.stroke()
            (item.text as NSString).draw(at: NSPoint(x: item.x, y: item.y), withAttributes: attrs)
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    @Test func ocrFallbackIsDisabledByDefaultAndLoadsFromToml() throws {
        let defaults = RoadieConfig()
        #expect(!defaults.experimental.appTargets.ocrFallbackEnabled)
        #expect(defaults.experimental.appTargets.ocrFallbackThreshold == 0)

        let dir = try tempDir("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roadies.toml")
        try """
        [experimental.app_targets]
        ocr_fallback = true
        ocr_fallback_threshold = 5
        """.write(to: file, atomically: true, encoding: .utf8)

        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(loaded.experimental.appTargets.ocrFallbackEnabled)
        #expect(loaded.experimental.appTargets.ocrFallbackThreshold == 5)
        #expect(!RoadieConfigLoader.validate(path: file.path).hasErrors)

        let descToggle = try #require(SettingsCatalog.find(id: "app_targets.ocr_fallback"))
        #expect(descToggle.defaultValue == .bool(false))
        let descThreshold = try #require(SettingsCatalog.find(id: "app_targets.ocr_fallback_threshold"))
        #expect(descThreshold.defaultValue == .int(0))
    }

    @Test func visionNormalizedBoxConvertsAccuratelyToAXMultiDisplayCoordinates() {
        // Écran secondaire à coordonnées négatives (ex. LG 4K x=1800, y=-1266)
        let win = Rect(x: 1800, y: -1200, width: 1000, height: 800)
        // Boîte en haut à gauche dans Vision : x=0.1, y=0.8, w=0.2, h=0.1 -> en AX y = -1200 + (1 - 0.8 - 0.1)*800 = -1120
        let ax = ScreenSearchOCRService.normalizedBoxToAXRect(CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1), in: win)
        #expect(abs(ax.x - 1900) < 0.01)
        #expect(abs(ax.y - (-1120)) < 0.01)
        #expect(abs(ax.width - 200) < 0.01)
        #expect(abs(ax.height - 80) < 0.01)
    }

    @Test func ocrSkipsWhenDisabledOrAboveThresholdAndDeduplicatesAXTargets() {
        let disabledCfg = AppTargetsConfig(ocrFallbackEnabled: false, ocrFallbackThreshold: 3)
        let resDisabled = ScreenSearchOCRService.fallbackTargetsIfNeeded(
            config: disabledCfg,
            existingTargets: [],
            windowID: 1,
            windowFrame: Rect(x: 0, y: 0, width: 800, height: 600),
            pid: 100,
            appName: "Test"
        )
        #expect(resDisabled.targets.isEmpty)
        #expect(resDisabled.metrics == nil)

        // Seuil 0 = complète toujours l'AX même si la fenêtre expose 50 boutons ; seuil > 0 = borne haute
        #expect(!ScreenSearchOCRService.shouldRunOCR(config: AppTargetsConfig(ocrFallbackEnabled: false, ocrFallbackThreshold: 0), existingAXCount: 0))
        #expect(ScreenSearchOCRService.shouldRunOCR(config: AppTargetsConfig(ocrFallbackEnabled: true, ocrFallbackThreshold: 0), existingAXCount: 50))
        #expect(ScreenSearchOCRService.shouldRunOCR(config: AppTargetsConfig(ocrFallbackEnabled: true, ocrFallbackThreshold: 3), existingAXCount: 3))
        #expect(!ScreenSearchOCRService.shouldRunOCR(config: AppTargetsConfig(ocrFallbackEnabled: true, ocrFallbackThreshold: 3), existingAXCount: 4))

        // Déduplication contre une cible AX de taille comparable au même endroit, mais PAS contre un grand conteneur
        let axFrame = Rect(x: 100, y: 200, width: 120, height: 30)
        #expect(ScreenSearchOCRService.overlapsExisting(Rect(x: 105, y: 202, width: 110, height: 26), existingFrames: [axFrame]))
        #expect(!ScreenSearchOCRService.overlapsExisting(Rect(x: 400, y: 200, width: 120, height: 30), existingFrames: [axFrame]))
        let giantContainer = Rect(x: 0, y: 0, width: 1200, height: 900)
        #expect(!ScreenSearchOCRService.overlapsExisting(Rect(x: 105, y: 202, width: 140, height: 18), existingFrames: [giantContainer]))
    }

    @Test func visionOCRRecognizesControlsAndMeasuresLatencyAndMemory() throws {
        let labels: [(String, CGFloat, CGFloat)] = [
            ("Enregistrer", 120, 820),
            ("Annuler", 500, 820),
            ("Parametres", 120, 500),
            ("Connect", 500, 500),
            ("Exporter", 900, 200)
        ]

        // 1. Fenêtre 1920x1080
        let img1080 = try #require(renderSyntheticWindowImage(width: 1920, height: 1080, labels: labels))
        let win1080 = Rect(x: 100, y: 50, width: 1920, height: 1080)
        let r1080 = ScreenSearchOCRService.recognize(
            image: img1080,
            windowFrame: win1080,
            windowID: 991,
            pid: 4242,
            appName: "SyntheticCanvas"
        )
        let titles1080 = r1080.targets.map { $0.title.lowercased() }
        #expect(titles1080.contains(where: { $0.contains("enregistrer") }))
        #expect(titles1080.contains(where: { $0.contains("connect") }))
        #expect(r1080.targets.allSatisfy { $0.id.hasPrefix("app:4242/ocr:991/") })
        #expect(r1080.metrics.elapsedMs < 3000)

        // 2. Fenêtre 2560x1440 (2e passe à chaud)
        let img1440 = try #require(renderSyntheticWindowImage(width: 2560, height: 1440, labels: labels))
        let win1440 = Rect(x: 1800, y: -1200, width: 2560, height: 1440)
        let r1440 = ScreenSearchOCRService.recognize(
            image: img1440,
            windowFrame: win1440,
            windowID: 992,
            pid: 4242,
            appName: "SyntheticCanvas"
        )
        #expect(r1440.targets.count >= 3)
        print("[SPEC169_BENCH] 1080p_cold: \(r1080.metrics.elapsedMs)ms deltaRAM=\(r1080.metrics.footprintDeltaKB)KB obs=\(r1080.metrics.observationsCount) | 1440p_warm: \(r1440.metrics.elapsedMs)ms deltaRAM=\(r1440.metrics.footprintDeltaKB)KB obs=\(r1440.metrics.observationsCount)")
    }
}
