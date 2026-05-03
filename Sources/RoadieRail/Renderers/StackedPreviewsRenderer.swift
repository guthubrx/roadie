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

// MARK: - Constantes locales (identiques à l'ex-WindowStack)

private let maxVisible:    Int     = 5
private let stackOffsetXY: CGFloat = 6
private let stackScale:    CGFloat = 0.02
private let stackOpacity:  CGFloat = 0.10

private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)
private let appIconSize:        CGFloat = 24

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
        ZStack(alignment: .topLeading) {
            ForEach(Array(wids.enumerated()), id: \.element) { idx, wid in
                let depth = idx
                WindowPreview(
                    wid: wid,
                    thumbnail: thumbnails[wid],
                    appName: windows[wid]?.appName ?? "",
                    pid: windows[wid]?.pid ?? 0,
                    bundleID: windows[wid]?.bundleID ?? "",
                    sourceStageID: stage.id
                )
                .offset(x: CGFloat(depth) * stackOffsetXY,
                        y: CGFloat(depth) * stackOffsetXY)
                .scaleEffect(1.0 - CGFloat(depth) * stackScale,
                             anchor: .topLeading)
                .opacity(1.0 - CGFloat(depth) * stackOpacity)
                .zIndex(Double(wids.count - idx))
            }
        }
        .padding(.trailing, CGFloat(maxVisible) * stackOffsetXY)
        .padding(.bottom,   CGFloat(maxVisible) * stackOffsetXY)
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
