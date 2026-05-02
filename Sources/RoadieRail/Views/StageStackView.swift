import SwiftUI

// SPEC-014 T028 — Vue racine SwiftUI du rail. Design "Stage Manager natif".
// Reçoit RailState en @Bindable (pattern @Observable macOS 14+).
// Pas de header, stacks centrés verticalement, hint discret en bas.

private let stackSpacing: CGFloat = 32
private let hintOpacity:  CGFloat = 0.28

struct StageStackView: View {
    @Bindable var state: RailState
    // SPEC-014 T041 (US2) : callback de tap, câblé par RailController.
    var onTapStage:   (String) -> Void              = { _ in }
    // SPEC-014 T052 (US3) : callback de drop, (wid, target_stage_id).
    var onDropAssign: (CGWindowID, String) -> Void  = { _, _ in }
    // SPEC-014 T070 (US5) : callbacks menu contextuel.
    var onRename:     (String, String) -> Void      = { _, _ in }
    var onAddFocused: (String) -> Void              = { _ in }
    var onDelete:     (String) -> Void              = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            stageList
            Spacer(minLength: 0)
            hintText
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Fond strictement transparent (demande utilisateur explicite, 3x).
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stageList: some View {
        let nonEmpty = state.stages.filter { !$0.windowIDs.isEmpty }
        if nonEmpty.isEmpty {
            Text("No stages yet")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            // Filtrage des stages virtuellement vides (wids orphelines toutes absentes).
            let visible = nonEmpty.filter { stage in
                stage.windowIDs.contains { wid in
                    state.windows[wid] != nil || state.thumbnails[wid] != nil
                }
            }
            if visible.isEmpty {
                Text("No stages yet")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.34))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // GeometryReader + frame(minHeight:alignment:) : quand peu de stacks,
                // le VStack occupe toute la hauteur visible et est centré verticalement.
                // Quand le contenu dépasse, le ScrollView prend le relais naturellement.
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: stackSpacing) {
                            ForEach(visible) { stage in
                                WindowStack(
                                    stage: stage,
                                    thumbnails: state.thumbnails,
                                    windows: state.windows,
                                    onTap: { onTapStage(stage.id) },
                                    onDropAssign: onDropAssign,
                                    onRename: onRename,
                                    onAddFocused: onAddFocused,
                                    onDelete: onDelete
                                )
                                // Aligner à gauche (vs centre) — demande utilisateur.
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.leading, 8)    // proche du bord gauche
                        .padding(.trailing, 16)
                        .padding(.vertical, 20)
                        .frame(minHeight: geo.size.height, alignment: .center)
                    }
                }
            }
        }
    }

    private var hintText: some View {
        Text("Click to switch • Drag to move")
            .font(.system(size: 9, weight: .regular).monospaced())
            .foregroundStyle(Color.white.opacity(hintOpacity))
            .multilineTextAlignment(.center)
    }

    // Fond HUD : NSVisualEffectView natif + tint sombre par-dessus.
    // Tint abaissé à 0.35 : laisse le flou natif .hudWindow dominer.
    private var hudBackground: some View {
        ZStack {
            HUDBackground()
            Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.35)
        }
        .ignoresSafeArea()
    }
}
