import SwiftUI
import AppKit

// SPEC-019 T050 — Renderer "hero-preview" (US3).
// Affiche la fenêtre focused/frontmost en grand (WindowPreview plein cadre)
// et les autres fenêtres du stage comme une rangée d'icônes d'app dessous.

public final class HeroPreviewRenderer: StageRenderer {
    public static let rendererID:  String = "hero-preview"
    public static let displayName: String = "Hero preview"

    public init() {}

    @MainActor
    public func render(context: StageRenderContext,
                       callbacks: StageRendererCallbacks) -> AnyView {
        AnyView(HeroPreviewView(context: context, callbacks: callbacks))
    }
}

// MARK: - Constantes

// Hero size lue depuis context.previewWidth/Height (TOML [fx.rail.preview]).
private let thumbIconSize: CGFloat = 24
private let maxSideIcons:  Int    = 6
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)

// MARK: - View

private struct HeroPreviewView: View {
    let context:   StageRenderContext
    let callbacks: StageRendererCallbacks

    @State private var isDropTargeted: Bool = false

    private var stage:      StageVM                  { context.stage }
    private var windows:    [CGWindowID: WindowVM]   { context.windows }
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
            // SPEC-019 — paddings outer driven by context (override via [fx.rail.hero-preview]).
            .padding(.leading,  CGFloat(context.leadingPadding))
            .padding(.trailing, CGFloat(context.trailingPadding))
            .padding(.vertical, CGFloat(context.verticalPadding))
    }

    @ViewBuilder
    private var content: some View {
        if stage.windowIDs.isEmpty {
            // SPEC-022 : stage vide → rien rendu (cellule reste cliquable via la VStack parent).
            EmptyView()
        } else {
            VStack(spacing: 6) {
                heroPreview
                sideIconRow
            }
            .padding(6)
        }
    }

    // MARK: - Placeholder stage vide (SPEC-022 : not rendered, kept for potential debug mode)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .resizable().scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(Color.white.opacity(0.25))
            Text("Empty stage")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(width: CGFloat(context.previewWidth), height: CGFloat(context.previewHeight))
    }

    // MARK: - Grande vignette (fenêtre focused ou première disponible)

    private var heroWid: CGWindowID? {
        let known = stage.windowIDs.filter { windows[$0] != nil }
        return known.first(where: { windows[$0]?.isFocused == true }) ?? known.first
    }

    @ViewBuilder
    private var heroPreview: some View {
        if let wid = heroWid, let win = windows[wid] {
            WindowPreview(
                wid: wid,
                thumbnail: thumbnails[wid],
                appName: win.appName,
                pid: win.pid,
                bundleID: win.bundleID,
                sourceStageID: stage.id,
                borderColor: Color(hex: context.resolvedBorderColor()),
                borderWidth: CGFloat(context.borderWidth),
                borderStyle: context.borderStyle
            )
            .frame(width: CGFloat(context.previewWidth), height: CGFloat(context.previewHeight))
        }
    }

    // MARK: - Rangée d'icônes des autres fenêtres

    private var sideWids: [CGWindowID] {
        let hero = heroWid
        let others = stage.windowIDs.filter { $0 != hero && windows[$0] != nil }
        return Array(others.prefix(maxSideIcons))
    }

    @ViewBuilder
    private var sideIconRow: some View {
        let extra = stage.windowIDs.filter { $0 != heroWid && windows[$0] != nil }.count - sideWids.count
        HStack(spacing: 4) {
            ForEach(sideWids, id: \.self) { wid in
                if let win = windows[wid] {
                    Image(nsImage: resolveAppIcon(pid: win.pid, bundleID: win.bundleID,
                                                 appName: win.appName, size: thumbIconSize))
                        .resizable().scaledToFit()
                        .frame(width: thumbIconSize, height: thumbIconSize)
                }
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
        }
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
