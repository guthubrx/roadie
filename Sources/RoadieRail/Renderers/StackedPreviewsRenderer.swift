import SwiftUI
import AppKit

// SPEC-019 — Renderer "stacked-previews" (default).
// Extrait fidèlement de l'ancien `WindowStack.swift`. Comportement identique
// (cascade de previews avec halo si stage actif). C'est l'implémentation de
// référence du design "Stage Manager natif" SPEC-014.

public final class StackedPreviewsRenderer: StageRenderer {
    public static let rendererID:  String = "stacked-previews"
    public static let displayName: String = "Stacked previews"

    public init() {}

    @MainActor
    public func render(context: StageRenderContext,
                       callbacks: StageRendererCallbacks) -> AnyView {
        AnyView(StackedPreviewsView(context: context, callbacks: callbacks))
    }
}

// MARK: - Constantes locales

private let maxVisible:    Int     = 5
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)
private let appIconSize:        CGFloat = 24

/// Pseudo-random déterministe : la même wid donne TOUJOURS le même décalage
/// → la vignette ne saute pas à chaque refresh (toutes les 2 s). Bornes passées
/// en paramètre pour permettre la configuration via [fx.rail.stacked] TOML.
private func scatterFor(wid: CGWindowID,
                        idx: Int,
                        mode: String,
                        maxOffsetX: CGFloat,
                        maxOffsetY: CGFloat,
                        maxRotation: Double) -> (dx: CGFloat, dy: CGFloat, angle: Double) {
    let h = UInt64(wid &* 2654435761)
    let ang = Double(Int((h / 1000000) % 1000)) / 1000 * (maxRotation * 2) - maxRotation
    if mode == "compass" {
        // 4 quadrants cardinaux : chaque vignette idx=1..4 va dans un coin distinct.
        // Cela maximise la portion visible de chaque thumbnail (la « hero » centrée
        // reste pleinement visible, les 4 autres ne se recouvrent que partiellement).
        // idx=0 est traité par l'appelant (vignette hero centrée, dx=dy=0).
        // Ordre : BR, BL, TL, TR (sens horaire à partir du coin bas-droite).
        let quadrants: [(CGFloat, CGFloat)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
        let q = quadrants[max(0, (idx - 1)) % 4]
        return (q.0 * maxOffsetX, q.1 * maxOffsetY, ang)
    }
    // mode "random" : hash-based, position imprévisible mais déterministe par wid.
    let dx  = CGFloat(Int(h % 1000)        ) / 1000 * (maxOffsetX * 2) - maxOffsetX
    let dy  = CGFloat(Int((h / 1000)  % 1000)) / 1000 * (maxOffsetY * 2) - maxOffsetY
    return (dx, dy, ang)
}

// MARK: - View

private struct StackedPreviewsView: View {
    let context:   StageRenderContext
    let callbacks: StageRendererCallbacks

    @State private var isDropTargeted: Bool   = false
    @State private var renameSheet:    Bool   = false
    @State private var renameField:    String = ""
    @State private var deleteConfirm:  Bool   = false

    private var stage:       StageVM                       { context.stage }
    private var thumbnails:  [CGWindowID: ThumbnailVM]     { context.thumbnails }
    private var windows:     [CGWindowID: WindowVM]        { context.windows }

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
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $renameSheet) { renameSheetView }
        .alert("Delete \(stage.displayName)?", isPresented: $deleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { callbacks.onDelete(stage.id) }
        } message: {
            Text("Windows will be moved back to stage 1.")
        }
        // SPEC-019 — paddings outer driven by context (override possible via [fx.rail.stacked]).
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
            ZStack(alignment: .bottomLeading) {
                stackedPreviews
                appIconBadge
                    .offset(x: -8, y: -8)
            }
        }
    }

    // MARK: - Placeholder (SPEC-022 : not rendered, kept for potential debug mode)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.white.opacity(0.25))
            Text("Empty stage")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(width: 220, height: 140)
    }

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

    private var visibleWids: [CGWindowID] {
        // Aligné sur Hero/Mosaic/Parallax : ne rendre QUE les wids dont on a la
        // metadata `windows[wid]`. Sans ce strict filter, les wids fantômes (présents
        // dans le cache thumbnails mais absents de `windows`) étaient rendus avec
        // pid=0/bundleID="" → WindowPreview tombait sur son fallback icône → effet
        // « icone » au lieu d'un vrai preview. Single source de vérité = state.windows.
        let known = stage.windowIDs.filter { windows[$0] != nil }
        let sorted = known.sorted { a, b in
            // SPEC-019 — priorité 1 : la fenêtre focused devient la « hero » (idx=0
            // → centrée, pleinement visible, sans rotation/offset).
            let fa = windows[a]?.isFocused ?? false
            let fb = windows[b]?.isFocused ?? false
            if fa != fb { return fa }
            let ta = !(windows[a]?.isFloating ?? false)
            let tb = !(windows[b]?.isFloating ?? false)
            if ta != tb { return ta }
            let tha = (thumbnails[a]?.pngData.isEmpty == false)
            let thb = (thumbnails[b]?.pngData.isEmpty == false)
            if tha != thb { return tha }
            return a > b
        }
        return Array(sorted.prefix(maxVisible))
    }

    @ViewBuilder
    private var stackedPreviews: some View {
        let wids = visibleWids
        let mxX = CGFloat(context.stackedOffsetX)
        let mxY = CGFloat(context.stackedOffsetY)
        ZStack(alignment: .center) {
            ForEach(Array(wids.enumerated()), id: \.element) { idx, wid in
                // Aligné sur Hero/Mosaic/Parallax : `if let win = windows[wid]` pour
                // passer les vraies metadata (pid, bundleID, appName) à WindowPreview.
                // Sans ce wrap, les fallback "" / 0 cassaient le rendu PNG.
                if let win = windows[wid] {
                    let depth = idx
                    // idx=0 = vignette « hero » centrée. idx>=1 = polaroïds éparpillés.
                    let scatter = depth == 0 ? (dx: CGFloat(0), dy: CGFloat(0), angle: 0.0)
                                              : scatterFor(wid: wid,
                                                           idx: depth,
                                                           mode: context.stackedScatterMode,
                                                           maxOffsetX: mxX,
                                                           maxOffsetY: mxY,
                                                           maxRotation: context.stackedRotation)
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
                        borderStyle: context.borderStyle
                    )
                    .rotationEffect(.degrees(scatter.angle))
                    .scaleEffect(1.0 - CGFloat(depth) * CGFloat(context.stackedScale))
                    .opacity(1.0 - CGFloat(depth) * CGFloat(context.stackedOpacity))
                    .offset(x: scatter.dx, y: scatter.dy)
                    .zIndex(Double(wids.count - idx))
                }
            }
        }
        // Padding adapté à l'amplitude max du scatter.
        .padding(.horizontal, mxX + 4)
        .padding(.vertical,   mxY + 4)
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10)
                .fill(dropHighlightColor)
                .allowsHitTesting(false)
        }
    }

    private var dominantAppIcon: NSImage {
        guard let wid = visibleWids.first, let win = windows[wid] else {
            return NSWorkspace.shared.icon(
                forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
            )
        }
        return resolveAppIcon(pid: win.pid, bundleID: win.bundleID,
                              appName: win.appName, size: appIconSize)
    }

    private var appIconBadge: some View {
        Image(nsImage: dominantAppIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: appIconSize, height: appIconSize)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename stage…") {
            renameField = stage.displayName
            renameSheet = true
        }
        Button("Add focused window") { callbacks.onAddFocused(stage.id) }
        Divider()
        Button("Delete stage", role: .destructive) {
            if stage.id != "1" { deleteConfirm = true }
        }.disabled(stage.id == "1")
    }

    private var renameSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename stage \(stage.id)").font(.headline)
            TextField("Stage name", text: $renameField)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button("Cancel") { renameSheet = false }
                Button("Save") { commitRename() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func commitRename() {
        let trimmed = renameField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.count <= 32 {
            callbacks.onRename(stage.id, trimmed)
        }
        renameSheet = false
    }
}
