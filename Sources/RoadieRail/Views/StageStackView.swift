import SwiftUI

// SPEC-014 T028 — Vue racine SwiftUI du rail.
// Reçoit RailState en @Bindable (pattern @Observable macOS 14+).

struct StageStackView: View {
    @Bindable var state: RailState
    var windows: [CGWindowID: WindowVM] = [:]
    // SPEC-014 T041 (US2) : callback de tap, câblé par RailController.
    var onTapStage: (String) -> Void = { _ in }
    // SPEC-014 T052 (US3) : callback de drop, (wid, target_stage_id).
    var onDropAssign: (CGWindowID, String) -> Void = { _, _ in }
    // SPEC-014 T070 (US5) : callbacks menu contextuel.
    var onRename: (String, String) -> Void = { _, _ in }
    var onAddFocused: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 18)
            Spacer(minLength: 8)
            stageList
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hudBackground)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("Stage Manager")
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundStyle(Color.white.opacity(0.44))
            Text("Stages")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Hover left edge. Click to switch • Drag to move.")
                .font(.system(size: 10, weight: .regular).monospaced())
                .foregroundStyle(Color.white.opacity(0.34))
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var stageList: some View {
        let nonEmpty = state.stages.filter { !$0.windowIDs.isEmpty }
        if nonEmpty.isEmpty {
            Text("No stages yet")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(nonEmpty) { stage in
                        StageCard(
                            stage: stage,
                            thumbnails: state.thumbnails,
                            windows: windows,
                            onTap: { onTapStage(stage.id) },
                            onDropAssign: onDropAssign,
                            onRename: onRename,
                            onAddFocused: onAddFocused,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // Fond HUD : NSVisualEffectView natif + tint sombre par-dessus.
    private var hudBackground: some View {
        ZStack {
            HUDBackground()
            Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.78)
        }
        .ignoresSafeArea()
    }
}
