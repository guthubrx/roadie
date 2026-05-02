import SwiftUI
import AppKit

// SPEC-014 T030 — Vignette compacte représentant une fenêtre dans une StageCard.
// Résolution d'icône via NSRunningApplication(pid) → NSWorkspace bundle → fallback générique.

struct WindowChip: View {
    let wid: CGWindowID
    let appName: String
    let pid: Int32
    let bundleID: String
    // SPEC-014 T051 (US3) : ID du stage parent, sert au drop-target pour skip same-stage.
    var sourceStageID: String = ""

    private let appIcon: NSImage

    init(wid: CGWindowID, appName: String, pid: Int32, bundleID: String,
         sourceStageID: String = "") {
        self.wid = wid
        self.appName = appName
        self.pid = pid
        self.bundleID = bundleID
        self.sourceStageID = sourceStageID
        self.appIcon = Self.resolveIcon(pid: pid, bundleID: bundleID, appName: appName)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.08))
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        }
        .frame(width: 30, height: 30)
        .draggable(WindowDragData(wid: wid, sourceStageID: sourceStageID))
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
