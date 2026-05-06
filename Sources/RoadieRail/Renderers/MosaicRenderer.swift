import SwiftUI
import AppKit

// SPEC-019 T060 — Renderer "mosaic" (US4).
// Grille adaptative : 1 → 1×1, 2 → 2×1, 3-4 → 2×2, 5-6 → 3×2, 7-9 → 3×3.
// Maximum 9 vignettes visibles, indicateur "+N" si overflow.

public final class MosaicRenderer: StageRenderer {
    public static let rendererID: String = "mosaic"
    public static let displayName: String = "Mosaic"

    public init() {}

    @MainActor
    public func render(context: StageRenderContext,
                       callbacks: StageRendererCallbacks) -> AnyView {
        AnyView(MosaicView(context: context, callbacks: callbacks))
    }
}

// MARK: - Grille adaptative

private let maxVisible: Int    = 9
private let cellPadding: CGFloat = 3
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)

private func columnCount(for total: Int) -> Int {
    switch total {
    case 1:       return 1
    case 2:       return 2
    case 3, 4:    return 2
    case 5, 6:    return 3
    default:      return 3
    }
}

// MARK: - View

private struct MosaicView: View {
    let context: StageRenderContext
    let callbacks: StageRendererCallbacks

    @State private var isDropTargeted: Bool = false

    private var stage: StageVM { context.stage }
    private var windows: [CGWindowID: WindowVM] { context.windows }
    private var thumbnails: [CGWindowID: ThumbnailVM] { context.thumbnails }

    var body: some View {
        haloed(content: content)
            .overlay(alignment: .center) { dropHighlight }
            .contentShape(Rectangle())
            .onTapGesture { callbacks.onTap() }
            .dropDestination(for: WindowDragData.self) { items, _ in
                guard let item = items.first, item.sourceStageID != stage.id else { return false }
                callbacks.onDropAssign(item.wid, stage.id)
                return true
            } isTargeted: { hovering in
                isDropTargeted = hovering
            }
            // SPEC-019 — paddings outer driven by context (override via [fx.rail.mosaic]).
            .padding(.leading, CGFloat(context.leadingPadding))
            .padding(.trailing, CGFloat(context.trailingPadding))
            .padding(.vertical, CGFloat(context.verticalPadding))
    }

    @ViewBuilder
    private var content: some View {
        if stage.windowIDs.isEmpty {
            // SPEC-022 : stage vide → rien rendu (cellule reste cliquable via la VStack parent).
            EmptyView()
        } else {
            mosaicGrid
        }
    }

    // MARK: - Placeholder (SPEC-022 : not rendered, kept for potential debug mode)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.white.opacity(0.25))
            Text("Empty stage")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(width: 200, height: 130)
    }

    // MARK: - Grille

    private var knownWids: [CGWindowID] {
        // SPEC-019 — fenêtre focused en première case de la grille.
        let known = stage.windowIDs.filter { windows[$0] != nil }
        return known.sorted { a, b in
            let fa = windows[a]?.isFocused ?? false
            let fb = windows[b]?.isFocused ?? false
            if fa != fb { return fa }
            return a > b
        }
    }

    private var visibleWids: [CGWindowID] {
        Array(knownWids.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, knownWids.count - maxVisible)
    }

    @ViewBuilder
    private var mosaicGrid: some View {
        let wids = visibleWids
        let cols = columnCount(for: wids.count)
        let columns = Array(repeating: GridItem(.flexible(), spacing: cellPadding), count: cols)

        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                LazyVGrid(columns: columns, spacing: cellPadding) {
                    ForEach(Array(wids.enumerated()), id: \.element) { idx, wid in
                        if let win = windows[wid] {
                            WindowPreview(
                                wid: wid,
                                thumbnail: thumbnails[wid],
                                appName: win.appName,
                                pid: win.pid,
                                bundleID: win.bundleID,
                                sourceStageID: stage.id,
                                borderColor: Color(hex: context.resolvedBorderColor()),
                                borderWidth: CGFloat(context.borderWidth),
                                borderStyle: context.borderStyle,
                                onMoveUp: context.prevStageID.map { id in
                                    { callbacks.onDropAssign(wid, id) }
                                },
                                onSummon: stage.isActive ? nil : {
                                    callbacks.onSummonWindow(wid)
                                },
                                onMoveDown: context.nextStageID.map { id in
                                    { callbacks.onDropAssign(wid, id) }
                                },
                                showSummonButton: context.summonButtonEnabled,
                                enableSummonDoubleClick: context.summonDoubleClickEnabled,
                                // SPEC-028 — première vignette de la grille =
                                // représentante de la stage pour les chevrons
                                // reorder-stage. Mosaic à plat → pas de rotation.
                                isStageRepresentative: idx == 0,
                                onMoveStageUp: idx == 0
                                    ? context.prevStageID.map { id in
                                        { callbacks.onReorderStages(stage.id, id) }
                                    }
                                    : nil,
                                onMoveStageDown: idx == 0
                                    ? context.nextStageID.map { id in
                                        { callbacks.onReorderStages(id, stage.id) }
                                    }
                                    : nil,
                                chevronsAlwaysVisible: context.chevronsAlwaysVisible,
                                moveZoneWidth: CGFloat(context.chevronsMoveZoneWidth),
                                reorderZoneHeight: CGFloat(context.chevronsReorderZoneHeight),
                                fadeoutMs: context.chevronsFadeoutMs
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }

                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(cellPadding)
    }

    // MARK: - Halo & drop highlight

    @ViewBuilder
    private func haloed<Content: View>(content: Content) -> some View {
        if context.shouldApplyHalo {
            content.shadow(
                color: Color(hex: context.haloColorHex).opacity(context.haloIntensity),
                radius: context.haloRadius, x: 0, y: 0)
        } else {
            content
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10)
                .fill(dropHighlightColor)
                .allowsHitTesting(false)
        }
    }
}
