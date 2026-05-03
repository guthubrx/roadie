import SwiftUI
import AppKit

// SPEC-014 — Stack de captures représentant un stage (design "Stage Manager natif").
// Remplace StageCard. Pas de carte englobante : fenêtres flottantes empilées en Z.

private let maxVisible:    Int     = 3
private let stackOffsetXY: CGFloat = 6   // décalage X et Y entre couches
private let stackScale:    CGFloat = 0.02 // réduction de scale par couche
private let stackOpacity:  CGFloat = 0.10 // transparence additionnelle par couche

private let activeDotColor:   Color = Color(red: 0.20, green: 0.85, blue: 0.55)
private let activeGlowColor:  Color = Color(red: 0.20, green: 0.85, blue: 0.55).opacity(0.45)
private let dropHighlightColor: Color = Color(red: 0.47, green: 0.76, blue: 0.95).opacity(0.15)

private let appIconSize: CGFloat = 24

struct WindowStack: View {
    let stage:      StageVM
    let thumbnails: [CGWindowID: ThumbnailVM]
    let windows:    [CGWindowID: WindowVM]
    // SPEC-018 polish — halo paramétrique (couleur hex + intensité 0..1) lus depuis [fx.rail].
    var haloColorHex:  String                       = "#34C759"
    var haloIntensity: Double                       = 0.65
    var onTap:         () -> Void         = {}
    var onDropAssign:  (CGWindowID, String) -> Void = { _, _ in }
    var onRename:      (String, String) -> Void     = { _, _ in }
    var onAddFocused:  (String) -> Void             = { _ in }
    var onDelete:      (String) -> Void             = { _ in }

    @State private var isDropTargeted: Bool  = false
    @State private var renameSheet:    Bool  = false
    @State private var renameField:    String = ""
    @State private var deleteConfirm:  Bool  = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            stackedPreviews
            appIconBadge
                .offset(x: -8, y: -8)
        }
        // Pas de dot vert (redondant avec le halo).
        // SPEC-018 polish — halo paramétrique [fx.rail] halo_color/halo_intensity.
        .shadow(
            color: stage.isActive ? Color(hex: haloColorHex).opacity(haloIntensity) : .clear,
            radius: 14,
            x: 0,
            y: 0
        )
        .overlay(alignment: .center) { dropHighlight }
        .onTapGesture { onTap() }
        .dropDestination(for: WindowDragData.self) { items, _ in
            guard let item = items.first, item.sourceStageID != stage.id else { return false }
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

    // MARK: - Stack de previews

    // Filtrage des wids orphelines : wid connue si présente dans windows OU si
    // une thumbnail valide existe. Évite les chips blancs (fenêtres déjà fermées).
    private var visibleWids: [CGWindowID] {
        let known = stage.windowIDs.filter { wid in
            windows[wid] != nil || thumbnails[wid] != nil
        }
        return Array(known.prefix(maxVisible))
    }

    // Les fenêtres du fond (index élevé) sont dessinées en premier (ZStack LIFO).
    // reversed() + enumerated() donne : index 0 = couche de fond, n-1 = couche de premier plan.
    @ViewBuilder
    private var stackedPreviews: some View {
        let wids = visibleWids
        ZStack(alignment: .topLeading) {
            ForEach(Array(wids.enumerated()), id: \.element) { idx, wid in
                let depth = (wids.count - 1) - idx // 0 = avant-plan
                WindowPreview(
                    wid: wid,
                    thumbnail: thumbnails[wid],
                    appName: windows[wid]?.appName ?? "",
                    pid: windows[wid]?.pid ?? 0,
                    bundleID: windows[wid]?.bundleID ?? "",
                    sourceStageID: stage.id
                )
                .offset(
                    x: CGFloat(depth) * stackOffsetXY,
                    y: CGFloat(depth) * stackOffsetXY
                )
                .scaleEffect(
                    1.0 - CGFloat(depth) * stackScale,
                    anchor: .topLeading
                )
                .opacity(1.0 - CGFloat(depth) * stackOpacity)
                .zIndex(Double(idx))
            }
        }
        // Padding pour absorber le débordement des couches du fond.
        .padding(.trailing, CGFloat(maxVisible) * stackOffsetXY)
        .padding(.bottom,   CGFloat(maxVisible) * stackOffsetXY)
    }

    // MARK: - Dot actif

    @ViewBuilder
    private var activeDot: some View {
        if stage.isActive {
            Circle()
                .fill(activeDotColor)
                .frame(width: 6, height: 6)
                .offset(x: 4, y: -4)
        }
    }

    // MARK: - Drop highlight

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10)
                .fill(dropHighlightColor)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Icône d'app dominante

    private var dominantAppIcon: NSImage {
        guard let wid = visibleWids.first, let win = windows[wid] else {
            return NSWorkspace.shared.icon(
                forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
            )
        }
        return resolveIcon(pid: win.pid, bundleID: win.bundleID, appName: win.appName)
    }

    private var appIconBadge: some View {
        Image(nsImage: dominantAppIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: appIconSize, height: appIconSize)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
    }

    // MARK: - Menu contextuel

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

    // MARK: - Résolution icône (ordre : pid → nom → bundle → fallback)

    private func resolveIcon(pid: Int32, bundleID: String, appName: String) -> NSImage {
        if pid > 0,
           let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            icon.size = NSSize(width: appIconSize, height: appIconSize)
            return icon
        }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName }),
           let icon = running.icon {
            icon.size = NSSize(width: appIconSize, height: appIconSize)
            return icon
        }
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: appIconSize, height: appIconSize)
            return icon
        }
        let fallback = NSWorkspace.shared.icon(
            forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
        )
        fallback.size = NSSize(width: appIconSize, height: appIconSize)
        return fallback
    }
}

// MARK: - Color(hex:) helper

// SPEC-018 polish — parsing hex "#RRGGBB" ou "#RRGGBBAA". Fallback gris neutre si malformé.
// Tolérant : accepte avec ou sans #, lowercase ou uppercase.
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16)
        else {
            self = Color(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >>  8) & 0xFF) / 255.0
            b = Double( value        & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >>  8) & 0xFF) / 255.0
            a = Double( value        & 0xFF) / 255.0
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
