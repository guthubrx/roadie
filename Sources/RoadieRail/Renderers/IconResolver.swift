import SwiftUI
import AppKit

// SPEC-019 — Helper de résolution d'icône d'app partagé entre renderers.
// Ordre : pid en cours d'exécution → match localizedName → bundleID via Workspace → fallback générique.
// Extrait de WindowStack.swift pour éviter duplication.

@MainActor
public func resolveAppIcon(pid: Int32, bundleID: String, appName: String, size: CGFloat) -> NSImage {
    if pid > 0,
       let running = NSRunningApplication(processIdentifier: pid),
       let icon = running.icon {
        icon.size = NSSize(width: size, height: size)
        return icon
    }
    if let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == appName }),
       let icon = running.icon {
        icon.size = NSSize(width: size, height: size)
        return icon
    }
    if !bundleID.isEmpty,
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
    let fallback = NSWorkspace.shared.icon(
        forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
    )
    fallback.size = NSSize(width: size, height: size)
    return fallback
}
