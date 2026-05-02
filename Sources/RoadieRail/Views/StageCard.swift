import SwiftUI

// SPEC-014 T029 — Carte représentant un stage dans le rail.
// Palette de couleurs alignée sur le legacy yabai_stage_rail.swift (lignes 289-401).

private let maxVisibleChips = 8

// MARK: - Couleurs legacy (constantes nommées, 0 magic number inline)

private let borderActive      = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.78)
private let borderInactive    = Color.white.opacity(0.10)
private let bgActive          = Color(red: 0.12, green: 0.20, blue: 0.30).opacity(0.98)
private let bgInactive        = Color(white: 0.06).opacity(0.86)
private let badgeBgActive     = Color(red: 0.21, green: 0.34, blue: 0.44)
private let badgeBgInactive   = Color.white.opacity(0.07)
private let badgeTextActive   = Color(red: 0.65, green: 0.88, blue: 1.0)
private let badgeTextInactive = Color.white.opacity(0.56)
private let dotActive         = Color(red: 0.47, green: 0.90, blue: 0.80)
private let dotInactive       = Color.white.opacity(0.18)
private let subtitleColor     = Color.white.opacity(0.46)
private let promptActive      = Color(red: 0.65, green: 0.88, blue: 1.0).opacity(0.82)
private let promptInactive    = Color.white.opacity(0.30)

struct StageCard: View {
    let stage: StageVM
    let thumbnails: [CGWindowID: ThumbnailVM]
    let windows: [CGWindowID: WindowVM]
    var onTap: () -> Void = {}
    // SPEC-014 T052 (US3) : callback de drop, câblé par RailController.
    var onDropAssign: (CGWindowID, String) -> Void = { _, _ in }
    // SPEC-014 T070 (US5) : callbacks menu contextuel.
    var onRename: (String, String) -> Void = { _, _ in }
    var onAddFocused: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    @State private var isDropTargeted: Bool = false
    @State private var renameSheet: Bool = false
    @State private var renameField: String = ""
    @State private var deleteConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if !stage.windowIDs.isEmpty {
                chipRow
            }
            promptRow
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardBorder)
        .overlay(dropHighlight)
        .onTapGesture { onTap() }
        .dropDestination(for: WindowDragData.self) { items, _ in
            guard let item = items.first else { return false }
            if item.sourceStageID == stage.id { return false }
            onDropAssign(item.wid, stage.id)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
        }
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $renameSheet) { renameSheetView }
        .alert("Delete \(stage.displayName)?", isPresented: $deleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete(stage.id) }
        } message: {
            Text("Windows will be moved back to stage 1.")
        }
    }

    // MARK: - SPEC-014 T070 (US5) : menu contextuel.

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename stage…") {
            renameField = stage.displayName
            renameSheet = true
        }
        Button("Add focused window") { onAddFocused(stage.id) }
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
            onRename(stage.id, trimmed)
        }
        renameSheet = false
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 10) {
            badgeView
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(windowCountLabel)
                    .font(.system(size: 10, weight: .regular).monospaced())
                    .foregroundStyle(subtitleColor)
            }
            Spacer()
            Circle()
                .fill(stage.isActive ? dotActive : dotInactive)
                .frame(width: 8, height: 8)
        }
    }

    private var badgeView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(stage.isActive ? badgeBgActive : badgeBgInactive)
                .frame(width: 32, height: 22)
            Text(stage.id)
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(stage.isActive ? badgeTextActive : badgeTextInactive)
        }
    }

    private var chipRow: some View {
        let visible = Array(stage.windowIDs.prefix(maxVisibleChips))
        let overflow = stage.windowIDs.count - maxVisibleChips

        return HStack(spacing: 4) {
            ForEach(visible, id: \.self) { wid in
                WindowChip(
                    wid: wid,
                    appName: windows[wid]?.appName ?? "",
                    pid: windows[wid]?.pid ?? 0,
                    bundleID: windows[wid]?.bundleID ?? "",
                    thumbnail: thumbnails[wid],
                    sourceStageID: stage.id
                )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(Color.white.opacity(0.56))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var promptRow: some View {
        Text(promptText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(stage.isActive ? promptActive : promptInactive)
    }

    // SPEC-014 T052 : surlignage subtil quand un drag survole la carte.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.12))
                .allowsHitTesting(false)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(stage.isActive ? bgActive : bgInactive)
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                stage.isActive ? borderActive : borderInactive,
                lineWidth: stage.isActive ? 1.0 : 0.5
            )
    }

    private var windowCountLabel: String {
        let n = stage.windowIDs.count
        let base = n == 1 ? "1 window" : "\(n) windows"
        return stage.isActive ? base + " • active" : base
    }

    private var promptText: String {
        stage.isActive
            ? "Active stage — click another to switch"
            : "Click to switch • drag a window here to move it"
    }
}
