import Foundation
import CoreGraphics

// SPEC-014 T031 — Récupère les vignettes depuis le daemon et invalide le cache
// sur réception de l'événement thumbnail_updated.

/// Récupère et met en cache les vignettes de fenêtres depuis le daemon.
@MainActor
final class ThumbnailFetcher {
    private let ipc: RailIPCClient
    // NSCache gère automatiquement l'éviction sous pression mémoire.
    private var cache: [CGWindowID: ThumbnailVM] = [:]

    init(ipc: RailIPCClient) {
        self.ipc = ipc
    }

    /// Retourne la vignette en cache ou la récupère depuis le daemon.
    func fetch(wid: CGWindowID) async -> ThumbnailVM? {
        if let cached = cache[wid] { return cached }
        let vm = await fetchFromDaemon(wid: wid)
        if let vm = vm { cache[wid] = vm }
        return vm
    }

    /// Invalide le cache pour une fenêtre et refetch immédiatement.
    func invalidate(wid: CGWindowID) {
        cache.removeValue(forKey: wid)
        Task {
            _ = await fetch(wid: wid)
        }
    }

    // MARK: - Private

    private func fetchFromDaemon(wid: CGWindowID) async -> ThumbnailVM? {
        let payload: [String: Any]
        do {
            payload = try await ipc.send(command: "window.thumbnail", args: ["wid": String(wid)])
        } catch {
            FileHandle.standardError.write(Data("thumbnailFetcher: ipc error wid=\(wid): \(error)\n".utf8))
            return nil
        }
        let keys = payload.keys.sorted().joined(separator: ",")
        FileHandle.standardError.write(Data("thumbnailFetcher: wid=\(wid) keys=[\(keys)]\n".utf8))
        guard let b64 = payload["png_base64"] as? String else {
            FileHandle.standardError.write(Data("thumbnailFetcher: wid=\(wid) png_base64 missing or not String, type=\(type(of: payload["png_base64"] ?? "nil"))\n".utf8))
            return nil
        }
        guard let pngData = Data(base64Encoded: b64) else {
            FileHandle.standardError.write(Data("thumbnailFetcher: wid=\(wid) base64 decode failed (len=\(b64.count))\n".utf8))
            return nil
        }
        guard !pngData.isEmpty else { return nil }

        // Le daemon renvoie size sous forme d'array [w, h] (cf CommandRouter.thumbnailResponse).
        let sizeArr = (payload["size"] as? [Int]) ?? []
        let width = Double(sizeArr.first ?? 64)
        let height = Double(sizeArr.dropFirst().first ?? 40)
        let degraded = payload["degraded"] as? Bool ?? false

        return ThumbnailVM(
            wid: wid,
            pngData: pngData,
            size: CGSize(width: width, height: height),
            degraded: degraded
        )
    }
}
