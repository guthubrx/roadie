import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Wrapper ScreenCaptureKit — capture périodique 0.5 Hz, encode PNG 320×200.
/// Un stream SCStream par fenêtre observée. Idempotent : observe() sur un wid déjà
/// observé est un no-op.
///
/// Thread-safety : @MainActor — toutes les méthodes publiques doivent être appelées
/// depuis le MainActor. Les callbacks SCStream arrivent sur des queues background
/// et sont redirigés vers MainActor via Task { @MainActor in ... }.
///
/// TODO V2 : mock complet SCStream pour tests unitaires du flow observe/capture/unobserve.
/// En V1 les tests vérifient uniquement init/observe/unobserve sans crash.
@MainActor
public final class SCKCaptureService {
    private var streams: [CGWindowID: SCStream] = [:]

    /// Callback déclenché à chaque frame capturée. Le caller câble vers ThumbnailCache.put.
    public var onCapture: ((ThumbnailEntry) -> Void)?

    public init() {}

    /// Vérifie si la permission Screen Recording est accordée.
    /// Tente SCShareableContent.current et interprète l'erreur de permission.
    public var screenRecordingGranted: Bool {
        get async {
            do {
                _ = try await SCShareableContent.current
                return true
            } catch {
                // SCStreamError.userDeclined ou noWindowList = permission refusée.
                return false
            }
        }
    }

    /// Démarre la capture périodique de la fenêtre `wid`. No-op si déjà observée.
    /// Throws si ScreenCaptureKit ne peut pas localiser la fenêtre ou si permission absente.
    public func observe(wid: CGWindowID) async throws {
        guard streams[wid] == nil else { return }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            logWarn("sck: SCShareableContent.current failed — Screen Recording denied?",
                    ["wid": String(wid), "error": "\(error)"])
            throw error
        }

        guard let scWindow = content.windows.first(where: { $0.windowID == wid }) else {
            logWarn("sck: window not found in shareable content", ["wid": String(wid)])
            return
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let cfg = SCStreamConfiguration()
        cfg.width = 320
        cfg.height = 200
        // 0.5 Hz = 1 frame toutes les 2 secondes
        cfg.minimumFrameInterval = CMTime(seconds: 2, preferredTimescale: 600)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false

        let outputHandler = CaptureOutputHandler(wid: wid) { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.onCapture?(entry)
            }
        }

        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        do {
            try stream.addStreamOutput(outputHandler, type: .screen,
                                       sampleHandlerQueue: .global(qos: .utility))
            try await stream.startCapture()
        } catch {
            logWarn("sck: stream start failed", ["wid": String(wid), "error": "\(error)"])
            throw error
        }
        streams[wid] = stream
        logInfo("sck: observe started", ["wid": String(wid)])
    }

    /// Stoppe l'observation d'une fenêtre. No-op si non observée.
    public func unobserve(wid: CGWindowID) async {
        guard let stream = streams.removeValue(forKey: wid) else { return }
        do {
            try await stream.stopCapture()
        } catch {
            logWarn("sck: stopCapture error (non-fatal)", ["wid": String(wid), "error": "\(error)"])
        }
        logInfo("sck: observe stopped", ["wid": String(wid)])
    }
}

// MARK: - Output handler

/// SCStreamOutput implémenté comme classe séparée pour garder SCKCaptureService sous 200 LOC.
private final class CaptureOutputHandler: NSObject, SCStreamOutput {
    private let wid: CGWindowID
    private let onEntry: (ThumbnailEntry) -> Void
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(wid: CGWindowID, onEntry: @escaping (ThumbnailEntry) -> Void) {
        self.wid = wid
        self.onEntry = onEntry
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // Callback invoqué sur .global(qos: .utility). Sans pool local, les objets
        // autoreleased (CIImage, NSMutableData, Date, NS/CF bridges) peuvent fuiter
        // vers le pool main et déclencher un SIGSEGV objc_release au drain de NSApp.run.
        // Pratique recommandée Apple pour tout callback CoreImage hors main thread.
        autoreleasepool {
            guard type == .screen,
                  let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

            let ci = CIImage(cvImageBuffer: imageBuffer)
            guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }

            let size = CGSize(width: cg.width, height: cg.height)
            guard let pngData = encodePNG(cg) else { return }

            let entry = ThumbnailEntry(wid: wid, pngData: pngData, size: size,
                                       degraded: false, capturedAt: Date())
            onEntry(entry)
        }
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        // FIX NSZombie : `data as Data` est un toll-free bridging (wrap, pas copie).
        // Le NSMutableData vit dans l'autoreleasepool du callback SCStream ; à la
        // sortie du pool il est release. Le Data retourné devient zombie au prochain
        // accès depuis main thread → crash récurrent à uptime ≈ 140s (~70 frames).
        // Solution : copier les bytes dans un buffer Swift indépendant.
        return Data(bytes: data.bytes, count: data.length)
    }
}
