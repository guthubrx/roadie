import SwiftUI
import AppKit

// SPEC-014 T030 — Vignette compacte représentant une fenêtre dans une StageCard.

struct WindowChip: View {
    let wid: CGWindowID
    let thumbnail: ThumbnailVM?
    let appName: String
    // SPEC-014 T051 (US3) : ID du stage parent, sert au drop-target pour skip same-stage.
    var sourceStageID: String = ""

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)
            content
        }
        .frame(width: 64, height: 40)
        .draggable(WindowDragData(wid: wid, sourceStageID: sourceStageID))
    }

    @ViewBuilder
    private var content: some View {
        if let thumb = thumbnail, !thumb.pngData.isEmpty,
           let nsImage = NSImage(data: thumb.pngData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 40)
                .clipped()
        } else {
            // Fallback : initiales sur fond coloré.
            ZStack {
                Color(hue: appNameHue, saturation: 0.4, brightness: 0.5)
                Text(initials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initials: String {
        let words = appName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(appName.prefix(2)).uppercased()
    }

    // Dérive une teinte HSB stable depuis le nom de l'app (pas de magic number : 360 = cercle HSB).
    private var appNameHue: Double {
        let hash = abs(appName.unicodeScalars.reduce(0) { acc, c in acc &+ Int(c.value) })
        return Double(hash % 360) / 360.0
    }
}
