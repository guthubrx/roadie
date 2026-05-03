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
/// Amplitude max du décalage pseudo-random par couche (en px). idx=0 reste
/// centré (= la vignette « hero » n'a pas d'offset), idx>=1 reçoit un offset
/// déterministe par hash(wid) borné à ±maxOffset → effet « polaroïds éparpillés ».
private let maxOffsetX:    CGFloat = 28
private let maxOffsetY:    CGFloat = 36
/// Rotation max par couche (degrés). idx=0 sans rotation, idx>=1 reçoit ±maxRotation.
private let maxRotation:   Double  = 5.0
/// Scale dégressive douce pour donner de la profondeur sans rétrécir trop.
private let stackScale:    CGFloat = 0.04
/// Opacité dégressive : la couche du fond reste visible pour qu'on reconnaisse
/// la fenêtre (vs ancienne valeur 0.10 qui gommait trop les couches arrière).
private let stackOpacity:  CGFloat = 0.06

private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)
private let appIconSize:        CGFloat = 24

/// Pseudo-random déterministe : retourne un offset (dx, dy) et un angle stable
/// pour une wid donnée. La même wid donne TOUJOURS le même décalage → la vignette
/// ne saute pas à chaque refresh (toutes les 2 s). Indépendant de la position
/// dans la cascade (idx) → si l'ordre des wids change (ex: focus change), chaque
/// vignette garde sa signature visuelle.
private func scatterFor(wid: CGWindowID) -> (dx: CGFloat, dy: CGFloat, angle: Double) {
    // Hash bête mais reproductible. Évite Random qui donnerait des sauts.
    let h = UInt64(wid &* 2654435761)
    let dx  = CGFloat(Int(h % 1000)        ) / 1000 * (maxOffsetX * 2) - maxOffsetX
    let dy  = CGFloat(Int((h / 1000)  % 1000)) / 1000 * (maxOffsetY * 2) - maxOffsetY
    let ang = Double( Int((h / 1000000) % 1000)) / 1000 * (maxRotation * 2) - maxRotation
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
        haloed(content: ZStack(alignment: .bottomLeading) {
            stackedPreviews
            appIconBadge
                .offset(x: -8, y: -8)
        })
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

    private var visibleWids: [CGWindowID] {
        let known = stage.windowIDs.filter { wid in
            windows[wid] != nil || thumbnails[wid] != nil
        }
        let sorted = known.sorted { a, b in
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
        ZStack(alignment: .center) {
            ForEach(Array(wids.enumerated()), id: \.element) { idx, wid in
                let depth = idx
                // idx=0 = vignette « hero » centrée, sans rotation, opacité pleine.
                // idx>=1 = polaroïds éparpillés derrière, offset + rotation déterministes
                // par wid (stable au refresh).
                let scatter = depth == 0 ? (dx: CGFloat(0), dy: CGFloat(0), angle: 0.0)
                                          : scatterFor(wid: wid)
                WindowPreview(
                    wid: wid,
                    thumbnail: thumbnails[wid],
                    appName: windows[wid]?.appName ?? "",
                    pid: windows[wid]?.pid ?? 0,
                    bundleID: windows[wid]?.bundleID ?? "",
                    sourceStageID: stage.id
                )
                .rotationEffect(.degrees(scatter.angle))
                .scaleEffect(1.0 - CGFloat(depth) * stackScale)
                .opacity(1.0 - CGFloat(depth) * stackOpacity)
                .offset(x: scatter.dx, y: scatter.dy)
                .zIndex(Double(wids.count - idx))   // hero (idx=0) sur le dessus
            }
        }
        // Padding suffisant pour que les polaroïds décalés ne soient pas clippés.
        .padding(.horizontal, maxOffsetX + 4)
        .padding(.vertical,   maxOffsetY + 4)
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
