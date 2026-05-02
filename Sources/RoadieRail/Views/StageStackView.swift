import SwiftUI

// SPEC-014 T028 — Vue racine SwiftUI du rail.
// Reçoit RailState en @Bindable (pattern @Observable macOS 14+).

struct StageStackView: View {
    @Bindable var state: RailState
    // Dictionnaire windows : sera peuplé en Phase 5+ (chips drag).
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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            stageList
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hudBackground)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stages")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Hover left edge. Click to switch • Drag to move.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stageList: some View {
        if state.stages.isEmpty {
            Text("No stages yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(state.stages) { stage in
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
            }
        }
    }

    // Fond HUD sombre semi-transparent — look cohérent avec la référence visuelle.
    private var hudBackground: some View {
        Color.black.opacity(0.72)
            .ignoresSafeArea()
    }
}
