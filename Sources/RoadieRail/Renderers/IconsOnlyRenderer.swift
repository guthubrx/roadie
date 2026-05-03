import SwiftUI
import AppKit

// SPEC-019 — Renderer "icons-only" (US2 MVP).
// Affiche pour chaque stage une grille verticale d'icônes d'app (1 par fenêtre,
// jusqu'à 6 visibles, puis "+N"). Pas de capture pixel — uniquement les icônes.
// Style "inventaire" hérité de l'ancien yabai_stage_rail.swift.

public final class IconsOnlyRenderer: StageRenderer {
    public static let rendererID:  String = "icons-only"
    public static let displayName: String = "Icons only"

    public init() {}

    @MainActor
    public func render(context: StageRenderContext,
                       callbacks: StageRendererCallbacks) -> AnyView {
        AnyView(IconsOnlyView(context: context, callbacks: callbacks))
    }
}

private let iconSize:    CGFloat = 32
private let maxVisible:  Int     = 6
private let cellWidth:   CGFloat = 200
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.18)

private struct IconsOnlyView: View {
    let context:   StageRenderContext
    let callbacks: StageRendererCallbacks

    @State private var isDropTargeted: Bool = false

    private var stage:   StageVM                  { context.stage }
    private var windows: [CGWindowID: WindowVM]   { context.windows }

    var body: some View {
        haloed(content: VStack(alignment: .leading, spacing: 6) {
            iconRow
            stageLabel
        })
        .padding(8)
        .frame(width: cellWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(stage.isActive ? 0.08 : 0.04))
        )
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
        .contextMenu {
            Button("Add focused window") { callbacks.onAddFocused(stage.id) }
            Divider()
            Button("Delete stage", role: .destructive) { callbacks.onDelete(stage.id) }
                .disabled(stage.id == "1")
        }
    }

    @ViewBuilder
    private func haloed<Content: View>(content: Content) -> some View {
        if stage.isActive {
            content.shadow(
                color: Color(hex: context.haloColorHex).opacity(context.haloIntensity),
                radius: context.haloRadius, x: 0, y: 0)
        } else {
            content
        }
    }

    @ViewBuilder
    private var iconRow: some View {
        let known = stage.windowIDs.compactMap { wid -> WindowVM? in windows[wid] }
        if known.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .resizable().scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Color.white.opacity(0.30))
                Text("Empty")
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.40))
            }
        } else {
            HStack(spacing: 6) {
                ForEach(Array(known.prefix(maxVisible).enumerated()), id: \.offset) { _, win in
                    Image(nsImage: resolveAppIcon(pid: win.pid, bundleID: win.bundleID,
                                                  appName: win.appName, size: iconSize))
                        .resizable().scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                }
                if known.count > maxVisible {
                    Text("+\(known.count - maxVisible)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
    }

    private var stageLabel: some View {
        let count = stage.windowIDs.filter { windows[$0] != nil }.count
        let suffix = stage.isActive ? " • active" : ""
        return Text("\(stage.displayName) — \(count) \(count == 1 ? "window" : "windows")\(suffix)")
            .font(.system(size: 10, weight: .regular).monospaced())
            .foregroundStyle(Color.white.opacity(stage.isActive ? 0.75 : 0.45))
            .lineLimit(1)
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10)
                .fill(dropHighlightColor).allowsHitTesting(false)
        }
    }
}
