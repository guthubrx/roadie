import SwiftUI

// SPEC-014 T029 — Carte représentant un stage dans le rail.
// US1 : onTap est no-op. US2 le connectera au switch.

private let maxVisibleChips = 8

struct StageCard: View {
    let stage: StageVM
    let thumbnails: [CGWindowID: ThumbnailVM]
    // windows est le dictionnaire global, filtré ici pour ce stage.
    let windows: [CGWindowID: WindowVM]
    var onTap: () -> Void = {}
    // SPEC-014 T052 (US3) : callback de drop, câblé par RailController.
    var onDropAssign: (CGWindowID, String) -> Void = { _, _ in }
    // SPEC-014 T070 (US5) : callbacks menu contextuel.
    var onRename: (String, String) -> Void = { _, _ in }      // (stageID, newName)
    var onAddFocused: (String) -> Void = { _ in }             // stageID
    var onDelete: (String) -> Void = { _ in }                 // stageID
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
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardBorder)
        .overlay(dropHighlight)
        .onTapGesture { onTap() }
        .dropDestination(for: WindowDragData.self) { items, _ in
            guard let item = items.first else { return false }
            // FR-020 : skip same-stage no-op.
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
            // FR-019 : stage 1 immortel — on désactive juste l'option.
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(windowCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if stage.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var badgeView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(stage.isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 32, height: 22)
            Text(stage.id)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(stage.isActive ? .white : .primary)
        }
    }

    private var chipRow: some View {
        let visible = Array(stage.windowIDs.prefix(maxVisibleChips))
        let overflow = stage.windowIDs.count - maxVisibleChips

        return HStack(spacing: 4) {
            ForEach(visible, id: \.self) { wid in
                WindowChip(
                    wid: wid,
                    thumbnail: thumbnails[wid],
                    appName: windows[wid]?.appName ?? "?",
                    sourceStageID: stage.id
                )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // SPEC-014 T052 : surlignage subtil quand un drag survole la carte.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.15))
                .allowsHitTesting(false)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.regularMaterial)
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                stage.isActive ? Color.accentColor : Color.secondary.opacity(0.2),
                lineWidth: stage.isActive ? 1 : 0.5
            )
    }

    private var windowCountLabel: String {
        let n = stage.windowIDs.count
        return n == 1 ? "1 window" : "\(n) windows"
    }
}
