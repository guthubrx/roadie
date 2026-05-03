import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - WindowCaptureService

/// Capture **lazy on-demand** d'une fenêtre via `CGWindowListCreateImage`.
///
/// Pattern repris d'AltTab : pas de stream continu, pas d'indicateur "capture
/// active" sur la fenêtre cible côté macOS, pas d'activation du DRM FairPlay
/// (Netflix, Apple TV…). Le caller (rail / CommandRouter) demande une capture
/// au moment où il en a besoin (= ouverture du rail au hover edge).
///
/// **Trade-off assumé** : la vignette ne se rafraîchit pas en continu, elle est
/// figée jusqu'à la prochaine demande explicite. Comportement identique à AltTab.
/// L'utilisateur ne le perçoit pas, le rail ré-appelle à chaque ouverture.
///
/// **Sur macOS 26 (Tahoe) et apps DRM strictes** : `CGWindowListCreateImage`
/// peut retourner `nil` ou une image avec zone vidéo masquée. Le caller doit
/// alors tomber sur le fallback icône d'app — c'est le comportement de
/// `handleWindowThumbnail` côté daemon.
@MainActor
public final class WindowCaptureService {

    /// Callback historique conservé pour compat (push thumbnail vers cache).
    /// En mode on-demand pur, le caller peut aussi récupérer l'entry retournée
    /// directement par `captureNow(wid:)`.
    public var onCapture: ((ThumbnailEntry) -> Void)?

    public init() {}

    /// Capture une vignette PNG pour `wid`. Synchrone (CGWindowListCreateImage
    /// est rapide ~5-15 ms). Retourne `nil` si la fenêtre n'est plus visible
    /// ou si DRM bloque (Netflix sur macOS récent).
    @discardableResult
    public func captureNow(wid: CGWindowID) -> ThumbnailEntry? {
        // .nominalResolution : taille logique (pas Retina x2) → vignette légère.
        // .boundsIgnoreFraming : exclut barre de titre/ombre, contenu seul.
        guard let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, wid,
            [.nominalResolution, .boundsIgnoreFraming]
        ) else { return nil }

        let size = CGSize(width: cg.width, height: cg.height)
        guard let pngData = Self.encodePNG(cg) else { return nil }

        let entry = ThumbnailEntry(wid: wid, pngData: pngData, size: size,
                                   degraded: false, capturedAt: Date())
        onCapture?(entry)
        return entry
    }

    /// Compat avec l'ancien usage `observe()` : synonyme de `captureNow(wid:)`.
    /// Permet aux call-sites historiques de continuer à compiler. À retirer
    /// quand tous les appels migrent vers `captureNow`.
    public func observe(wid: CGWindowID, bundleID: String? = nil) async throws {
        _ = bundleID  // ignoré désormais (plus de pré-filtre DRM nécessaire)
        _ = captureNow(wid: wid)
    }

    /// Compat : no-op. Aucun stream à arrêter en mode on-demand.
    public func unobserve(wid: CGWindowID) async {
        _ = wid
    }

    /// Permission Screen Recording — vérifiée via une capture-test sur le bureau.
    /// Si on obtient une image, la permission est OK. Sinon (nil), il faudra
    /// demander à l'utilisateur de l'accorder dans les Réglages Système.
    public var screenRecordingGranted: Bool {
        get async {
            // Capture-test sur la fenêtre 0 (= toutes fenêtres on-screen).
            let img = CGWindowListCreateImage(
                .null, .optionOnScreenOnly, kCGNullWindowID,
                [.nominalResolution]
            )
            return img != nil
        }
    }

    // MARK: - PNG encoding

    /// Encodage PNG d'un CGImage. `nonisolated` pour appelabilité depuis
    /// queue background (héritage de l'ancien CaptureOutputHandler).
    nonisolated static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        // Cf. note NSZombie : copie les bytes dans un Data Swift indépendant
        // (le NSMutableData peut être autoreleased par le runtime CF).
        return Data(bytes: data.bytes, count: data.length)
    }
}

// MARK: - Type alias rétro-compatible

/// Ancien nom de la classe. Conservé temporairement pour ne pas casser les
/// call-sites externes pendant la transition. À supprimer dans une session
/// de cleanup ultérieure.
public typealias SCKCaptureService = WindowCaptureService
