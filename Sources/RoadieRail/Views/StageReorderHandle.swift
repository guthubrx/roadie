import SwiftUI

/// SPEC-027 US3 — Handle visible pour le drag-reorder des stages dans le rail.
///
/// Petite poignée (≡) en overlay top-leading de chaque cellule de stage. Seule
/// zone draggable de la cellule pour le reorder : pas de conflit avec le
/// `.draggable(WindowDragData)` des WindowChip/WindowPreview enfants, qui
/// gardent leur propre comportement (drag d'une vignette de fenêtre).
///
/// Pattern UI : opacité basse au repos (0.30) qui passe à 0.75 au survol pour
/// signaler la draggabilité. Identique aux poignées de Notion/Linear/Trello.
///
/// Au drag, on émet un NSItemProvider avec une NSString = stage_id. Le drop
/// receiver côté StageStackView accepte les UTI `[.text]` et appelle
/// `onReorderStages(source, target)`.
struct StageReorderHandle: View {
    let stageID: String
    let onReorderStages: (String, String) -> Void

    @State private var isHovering = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(isHovering ? 0.75 : 0.30))
            .padding(.leading, 4)
            .padding(.top, 4)
            .frame(width: 22, height: 22, alignment: .topLeading)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                // Curseur openHand quand on est sur le handle pour suggérer
                // qu'on peut grab. Reset au cursor par défaut quand on sort.
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDrag {
                // Pour ne pas laisser le curseur en openHand après le drag.
                NSCursor.pop()
                return NSItemProvider(object: stageID as NSString)
            }
            .help("Drag pour réordonner cette stage dans le rail")
    }
}
