import SwiftUI
import AppKit

// SPEC-019 T070 — Renderer "parallax-45" (US5).
// Vignettes empilées en cascade avec rotation 3D axe Y (35°),
// scale dégressive et opacity réduite par couche.
// Hover sur la cellule déclenche un micro-bounce spring.

public final class Parallax45Renderer: StageRenderer {
    public static let rendererID: String = "parallax-45"
    public static let displayName: String = "Parallax 45\u{00B0}"

    public init() {}

    @MainActor
    public func render(context: StageRenderContext,
                       callbacks: StageRendererCallbacks) -> AnyView {
        AnyView(Parallax45View(context: context, callbacks: callbacks))
    }
}

// MARK: - Constantes

private let maxVisible: Int     = 5
private let hoverScale: CGFloat = 1.04
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)

// MARK: - View

private struct Parallax45View: View {
    let context: StageRenderContext
    let callbacks: StageRendererCallbacks

    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false

    private var stage: StageVM { context.stage }
    private var windows: [CGWindowID: WindowVM] { context.windows }
    private var thumbnails: [CGWindowID: ThumbnailVM] { context.thumbnails }

    var body: some View {
        haloed(content: content)
            .scaleEffect(isHovered ? hoverScale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in isHovered = hovering }
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
    }

    @ViewBuilder
    private var content: some View {
        if stage.windowIDs.isEmpty {
            // SPEC-022 : stage vide → rien rendu (cellule reste cliquable via la VStack parent).
            EmptyView()
        } else {
            parallaxStack
        }
    }

    // MARK: - Placeholder (SPEC-022 : not rendered, kept for potential debug mode)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.white.opacity(0.25))
            Text("Empty stage")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(width: 220, height: 140)
    }

    // MARK: - Pile 3D

    private var visibleWids: [CGWindowID] {
        // SPEC-019 — la fenêtre focused devient la « hero » (idx=0, devant la pile,
        // sans rotation atténuée ni offset). Cohérent avec stacked-previews/mosaic/
        // hero-preview.
        let known = stage.windowIDs.filter { windows[$0] != nil }
        let sorted = known.sorted { a, b in
            let fa = windows[a]?.isFocused ?? false
            let fb = windows[b]?.isFocused ?? false
            if fa != fb { return fa }
            return a > b
        }
        return Array(sorted.prefix(maxVisible))
    }

    @ViewBuilder
    private var parallaxStack: some View {
        let wids = visibleWids
        let offX  = CGFloat(context.parallaxOffsetX)
        let offY  = CGFloat(context.parallaxOffsetY)
        let scl   = CGFloat(context.parallaxScale)
        let opc   = context.parallaxOpacity
        let rot   = context.parallaxRotation
        ZStack(alignment: .center) {
            ForEach(Array(wids.enumerated().reversed()), id: \.element) { idx, wid in
                if let win = windows[wid] {
                    WindowPreview(
                        wid: wid,
                        thumbnail: thumbnails[wid],
                        appName: win.appName,
                        pid: win.pid,
                        bundleID: win.bundleID,
                        sourceStageID: stage.id,
                        previewWidth: CGFloat(context.previewWidth),
                        previewHeight: CGFloat(context.previewHeight),
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
                        // SPEC-028 — la vignette idx 0 est la frontmost en
                        // parallax (pile inclinée). Elle porte les chevrons
                        // reorder-stage qui héritent ainsi de la rotation 3D
                        // appliquée à WindowPreview ci-dessous.
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
                    .rotation3DEffect(
                        .degrees(rot),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .scaleEffect(1.0 - CGFloat(idx) * scl)
                    .opacity(1.0 - Double(idx) * opc)
                    // SPEC-019 — assombrissement progressif par couche : `darken_per_layer`
                    // soustrait `idx × valeur` à la luminosité. 0 = no-op (compat).
                    .brightness(-Double(idx) * context.parallaxDarkenPerLayer)
                    .offset(
                        x: -CGFloat(idx) * offX,
                        y: -CGFloat(idx) * offY
                    )
                    .zIndex(Double(wids.count - idx))
                }
            }
        }
        // SPEC-019 — paddings « smart » : l'utilisateur configure l'espace MINIMUM
        // entre la couche la plus en arrière (idx=N-1, décalée up-left) et le bord
        // du panel. Le renderer compense automatiquement le décalage cumulé
        // (`(N-1) × offX/Y`) pour garantir cette distance.
        //   leading_padding   = bord gauche ↔ couche la plus en arrière
        //   trailing_padding  = bord droit  ↔ hero (idx=0, sans décalage à droite)
        //   vertical_padding  = haut ↔ couche en arrière, bas ↔ hero
        .padding(.leading, CGFloat(context.leadingPadding)
                          + CGFloat(max(0, visibleWids.count - 1)) * CGFloat(context.parallaxOffsetX))
        .padding(.trailing, CGFloat(context.trailingPadding))
        .padding(.top, CGFloat(context.verticalPadding)
                          + CGFloat(max(0, visibleWids.count - 1)) * CGFloat(context.parallaxOffsetY))
        .padding(.bottom, CGFloat(context.verticalPadding))
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
