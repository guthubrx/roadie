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
    /// Timers de snapshot one-shot pour fenêtres DRM (CGWindowListCreateImage).
    /// Les bundles DRM (Netflix etc.) refusent la lecture si SCStream actif → on
    /// se rabat sur des snapshots ponctuels qui ne sont pas détectés comme stream.
    private var drmTimers: [CGWindowID: Timer] = [:]
    /// Intervalle de rafraîchissement des snapshots DRM (en secondes).
    /// Compromis : trop court → CPU + risque que macOS détecte le pattern,
    /// trop long → vignette pas à jour. 15s = 1 frame/15s, suffisant pour le rail.
    public var drmSnapshotInterval: TimeInterval = 15

    /// Callback déclenché à chaque frame capturée. Le caller câble vers ThumbnailCache.put.
    public var onCapture: ((ThumbnailEntry) -> Void)?

    /// Bundles dont la capture est refusée par le DRM FairPlay/Widevine.
    /// Activer SCStream sur leur fenêtre fait passer la vidéo en noir côté app
    /// (protection DRM). On skip silencieusement la capture, le rail tombera
    /// sur le fallback icône d'app.
    public static let defaultDRMBundles: Set<String> = [
        "com.netflix.Netflix",
        "com.apple.TV",                  // Apple TV+ / iTunes
        "com.disney.disneyplus",
        "com.amazon.aiv.AIVApp",         // Amazon Prime Video
        "com.spotify.client",            // Spotify (DRM audio mais aussi vidéos artistes)
        "com.warner.hbomax",             // HBO Max
        "com.hulu.plus",
    ]

    /// Bundles exclus en plus des DRM par défaut. Utilisable par l'utilisateur
    /// pour étendre la liste via config (ex: appli spécifique qui détecte
    /// SCStream comme menace). Modifiable à chaud.
    public var additionalExcludedBundles: Set<String> = []

    /// Liste effective des bundles exclus = défauts DRM + ajouts utilisateur.
    public var excludedBundles: Set<String> {
        Self.defaultDRMBundles.union(additionalExcludedBundles)
    }

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
    /// Le `bundleID` (optionnel) permet de filtrer les apps DRM AVANT tout appel
    /// ScreenCaptureKit. macOS 26 (Tahoe) signale au DRM dès `SCShareableContent.current`
    /// → on doit pré-filtrer côté caller.
    public func observe(wid: CGWindowID, bundleID: String? = nil) async throws {
        guard streams[wid] == nil, drmTimers[wid] == nil else { return }

        // Pré-filtre DRM SANS toucher à ScreenCaptureKit — sinon SCShareableContent.current
        // suffit pour signaler au système une intent de capture, ce qui coupe la lecture
        // Netflix sur macOS 26 Tahoe.
        if let bundleID = bundleID, excludedBundles.contains(bundleID) {
            logInfo("sck: DRM bundle (pre-filter) — no SCK call, no snapshot to avoid lecture cut", [
                "wid": String(wid), "bundle": bundleID,
            ])
            // Sur macOS 26+ Apple coupe même sur CGWindowListCreateImage si le DRM est strict.
            // Mode safe : pas de capture du tout, le rail tombe sur l'icône d'app.
            return
        }

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

        // Filet de sécurité : si le bundleID n'a pas été passé en pré-filtre par le caller,
        // on filtre quand même ici. Sur Tahoe ça arrive trop tard (DRM déjà alerté), mais
        // ça reste utile sur macOS antérieur.
        if let bundleID = scWindow.owningApplication?.bundleIdentifier,
           excludedBundles.contains(bundleID) {
            logInfo("sck: DRM bundle (post-filter) — skip", [
                "wid": String(wid), "bundle": bundleID,
            ])
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
    /// Couvre les 2 modes : SCStream et timer DRM snapshot.
    public func unobserve(wid: CGWindowID) async {
        if let timer = drmTimers.removeValue(forKey: wid) {
            timer.invalidate()
            logInfo("sck: DRM snapshot loop stopped", ["wid": String(wid)])
            return
        }
        guard let stream = streams.removeValue(forKey: wid) else { return }
        do {
            try await stream.stopCapture()
        } catch {
            logWarn("sck: stopCapture error (non-fatal)", ["wid": String(wid), "error": "\(error)"])
        }
        logInfo("sck: observe stopped", ["wid": String(wid)])
    }

    /// Démarre une boucle de snapshots one-shot pour une fenêtre DRM.
    /// Capture immédiate puis Timer périodique tant que la fenêtre est observée.
    /// Pattern repris d'AltTab : `CGWindowListCreateImage` ne déclenche pas
    /// FairPlay parce qu'il n'y a pas de stream actif, juste un read ponctuel.
    private func startDRMSnapshotLoop(wid: CGWindowID) {
        captureDRMSnapshot(wid: wid)
        let timer = Timer.scheduledTimer(withTimeInterval: drmSnapshotInterval,
                                          repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureDRMSnapshot(wid: wid)
            }
        }
        drmTimers[wid] = timer
    }

    /// Capture one-shot via API legacy. Encodage PNG identique au SCStream path.
    private func captureDRMSnapshot(wid: CGWindowID) {
        // .nominalResolution : taille logique (pas Retina x2). .boundsIgnoreFraming :
        // exclut la barre de titre/ombre, on ne capture que le contenu.
        guard let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, wid,
            [.nominalResolution, .boundsIgnoreFraming]
        ) else {
            // Sur macOS récent, le DRM peut bloquer même CGWindowListCreateImage.
            // Pas d'erreur — la prochaine itération du timer retentera.
            return
        }
        let size = CGSize(width: cg.width, height: cg.height)
        guard let pngData = Self.encodePNG(cg) else { return }
        let entry = ThumbnailEntry(wid: wid, pngData: pngData, size: size,
                                   degraded: true,  // marquer pour distinction côté rail
                                   capturedAt: Date())
        onCapture?(entry)
    }

    /// Helper PNG partagé entre SCStream et DRM snapshot path.
    /// Cf. note NSZombie : `Data(bytes:count:)` copie indépendamment du
    /// NSMutableData source pour survivre aux drains autoreleasepool.
    /// `nonisolated` : appelable depuis SCStream callback sur queue background.
    fileprivate nonisolated static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Data(bytes: data.bytes, count: data.length)
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
        // Délégué au helper static partagé (DRM path utilise le même encodage).
        SCKCaptureService.encodePNG(image)
    }
}
