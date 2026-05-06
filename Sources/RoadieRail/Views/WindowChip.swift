import SwiftUI
import AppKit

// SPEC-014 T030 — Vignette compacte représentant une fenêtre dans une StageCard.
// Résolution d'icône via NSRunningApplication(pid) → NSWorkspace bundle → fallback générique.

struct WindowChip: View {
    let wid: CGWindowID
    let appName: String
    let pid: Int32
    let bundleID: String
    /// SPEC-014 : vignette ScreenCaptureKit. Si présente, affichée à la place de l'icône.
    let thumbnail: ThumbnailVM?
    // SPEC-014 T051 (US3) : ID du stage parent, sert au drop-target pour skip same-stage.
    var sourceStageID: String = ""

    /// Icône résolue à chaque rendu : un `let` set dans init resterait stale
    /// quand SwiftUI met à jour les props sans recréer la struct (id stable).
    private var appIcon: NSImage {
        Self.resolveIcon(pid: pid, bundleID: bundleID, appName: appName)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.08))
            content
        }
        .frame(width: 56, height: 36)
        .draggable(WindowDragData(wid: wid, sourceStageID: sourceStageID)) {
            // SPEC-028 — preview du drag. Sert aussi à notifier le tracker
            // qu'un drag de wid démarre (pour summoner si drop hors-rail).
            // La preview elle-même reproduit la vignette pour visuel.
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.15))
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 56, height: 36)
            .onAppear {
                DragSummonTracker.shared.startDrag(wid: wid)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Priorité : vraie vignette ScreenCaptureKit si non-vide ET non-degraded.
        // Le mode degraded retombe sur l'icône d'app (fallback gracieux).
        if let thumb = thumbnail, !thumb.pngData.isEmpty, !thumb.degraded,
           let nsImage = NSImage(data: thumb.pngData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        }
    }

    // MARK: - Résolution d'icône (ordre de priorité : pid → nom → bundle → fallback)

    private static func resolveIcon(pid: Int32, bundleID: String, appName: String) -> NSImage {
        if pid > 0,
           let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName }),
           let icon = running.icon {
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        let fallback = NSWorkspace.shared.icon(
            forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
        )
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }
}
