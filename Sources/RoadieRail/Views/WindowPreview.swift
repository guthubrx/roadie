import SwiftUI
import AppKit

// SPEC-014 — Vignette pleine d'une seule fenêtre (~200×130 pt).
// Remplace WindowChip dans le nouveau design "Stage Manager natif".

private let previewWidth:    CGFloat = 200
private let previewHeight:   CGFloat = 130
private let previewRadius:   CGFloat = 8
private let borderOpacity:   CGFloat = 0.15
private let borderWidth:     CGFloat = 0.5

struct WindowPreview: View {
    let wid:          CGWindowID
    let thumbnail:    ThumbnailVM?
    let appName:      String
    let pid:          Int32
    let bundleID:     String
    let sourceStageID: String

    var body: some View {
        ZStack {
            previewContent
        }
        .frame(width: previewWidth, height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: previewRadius))
        .overlay(
            RoundedRectangle(cornerRadius: previewRadius)
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: borderWidth)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .draggable(WindowDragData(wid: wid, sourceStageID: sourceStageID))
    }

    // MARK: - Contenu

    @ViewBuilder
    private var previewContent: some View {
        if let thumb = thumbnail,
           !thumb.pngData.isEmpty,
           !thumb.degraded,
           let nsImage = NSImage(data: thumb.pngData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: previewWidth, height: previewHeight)
        } else if pid > 0,
                  let running = NSRunningApplication(processIdentifier: pid),
                  let icon = running.icon {
            // Fallback icône centrée sur fond semi-transparent (pid connu, app vivante).
            ZStack {
                RoundedRectangle(cornerRadius: previewRadius)
                    .fill(Color.white.opacity(0.05))
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            }
        } else if pid > 0 {
            // pid connu mais icône non disponible — fond neutre + icône générique.
            ZStack {
                Color(white: 0.12).opacity(0.90)
                Image(nsImage: resolvedIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .opacity(0.80)
            }
        }
        // pid == 0 (wid orpheline) : EmptyView implicite — filtré en amont dans
        // WindowStack.visibleWids, ce cas ne devrait pas atteindre ce composant.
    }

    // MARK: - Icône (même ordre de priorité que WindowChip)

    private var resolvedIcon: NSImage {
        Self.resolveIcon(pid: pid, bundleID: bundleID, appName: appName)
    }

    private static func resolveIcon(pid: Int32, bundleID: String, appName: String) -> NSImage {
        if pid > 0,
           let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName }),
           let icon = running.icon {
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        let fallback = NSWorkspace.shared.icon(
            forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
        )
        fallback.size = NSSize(width: 40, height: 40)
        return fallback
    }
}
