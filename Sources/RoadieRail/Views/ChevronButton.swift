import SwiftUI

/// Direction du chevron (utilisée pour le system image SF Symbols).
enum ChevronDirection: String {
    case up    = "chevron.up"
    case right = "chevron.right"
    case down  = "chevron.down"
}

/// Bouton chevron générique 18×14, style HUD sombre. Réutilisé par :
/// - WindowPreview (chevrons up/right/down de move-window) — SPEC-028
/// - StageStackView (chevrons up/down de reorder-stage) — SPEC-027
///
/// Le clic est natif (NSEvent souris) — sur Tahoe, ce mouseDown global est
/// ce qui réveille le compositor pour qu'il re-render après un setBounds AX.
struct ChevronButton: View {
    let direction: ChevronDirection
    var enabled: Bool = true
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(systemName: direction.rawValue)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 14)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(enabled ? (isHovering ? 1.0 : 0.85) : 0.20)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering && enabled { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                guard enabled else { return }
                onTap()
            }
    }
}
