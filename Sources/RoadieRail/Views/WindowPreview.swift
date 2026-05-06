import SwiftUI
import AppKit
import RoadieCore

// SPEC-014 — Vignette pleine d'une seule fenêtre (~200×130 pt).
// Remplace WindowChip dans le nouveau design "Stage Manager natif".

// SPEC-019 — dimensions par défaut, override possibles via le constructeur
// (les renderers passent context.previewWidth/Height lus depuis [fx.rail.preview]).
private let defaultPreviewWidth: CGFloat = 200
private let defaultPreviewHeight: CGFloat = 130
private let previewRadius: CGFloat = 8
private let defaultBorderColor: Color   = Color.white.opacity(0.15)
private let defaultBorderWidth: CGFloat = 0.5

struct WindowPreview: View {
    let wid: CGWindowID
    let thumbnail: ThumbnailVM?
    let appName: String
    let pid: Int32
    let bundleID: String
    let sourceStageID: String
    var previewWidth: CGFloat = defaultPreviewWidth
    var previewHeight: CGFloat = defaultPreviewHeight
    // SPEC-019 — bordure paramétrable (per-renderer via [fx.rail.<id>]).
    var borderColor: Color   = defaultBorderColor
    var borderWidth: CGFloat = defaultBorderWidth
    var borderStyle: String  = "solid"  // "solid" | "dashed" | "dotted"
    /// SPEC-028 — déplacer la fenêtre vers la stage AFFICHÉE juste au-dessus
    /// dans le rail (saute les stages absentes). nil = pas de stage au-dessus.
    var onMoveUp: (() -> Void)?
    /// SPEC-028 — amener la fenêtre dans la stage active du display
    /// (= summon). nil = la vignette est déjà sur la stage active (no-op).
    /// Le clic natif souris contourne le bug compositor Tahoe (validé).
    var onSummon: (() -> Void)?
    /// SPEC-028 — déplacer vers la stage AFFICHÉE juste en-dessous dans le
    /// rail. nil = pas de stage en-dessous.
    var onMoveDown: (() -> Void)?
    /// SPEC-028 — affiche les chevrons up/right/down bas-gauche de la
    /// vignette. Lu depuis `[fx.rail].summon_button_enabled` TOML.
    var showSummonButton: Bool = true
    /// SPEC-028 — double-clic sur la vignette = summon (alternative au bouton).
    /// Lu depuis `[fx.rail].summon_double_click_enabled` TOML.
    var enableSummonDoubleClick: Bool = true
    /// SPEC-028 — true uniquement pour la vignette FRONTMOST de la stage
    /// (= idx 0 en parallax/stacked, hero en hero-preview, première en mosaic).
    /// Cette vignette porte les chevrons reorder-stage (au-dessus / en-dessous)
    /// qui héritent ainsi de la rotation 3D du renderer (parallax-45).
    var isStageRepresentative: Bool = false
    /// SPEC-028 — déplacer la stage entière une cran vers le haut dans le rail.
    /// Non-nil seulement sur la vignette frontmost ET si la stage n'est pas la
    /// première du rail.
    var onMoveStageUp: (() -> Void)?
    /// SPEC-028 — déplacer la stage entière une cran vers le bas. Non-nil
    /// seulement sur la vignette frontmost ET si la stage n'est pas la dernière.
    var onMoveStageDown: (() -> Void)?
    /// SPEC-028 — true = chevrons toujours visibles. false = visibles
    /// uniquement quand le curseur est dans la zone de proximité.
    var chevronsAlwaysVisible: Bool = false
    /// SPEC-028 — largeur (px) de la bande gauche de la vignette qui
    /// déclenche les chevrons move-window.
    var moveZoneWidth: CGFloat = 30
    /// SPEC-028 — hauteur (px) des bandes au-dessus/au-dessous qui
    /// déclenchent les chevrons reorder-stage.
    var reorderZoneHeight: CGFloat = 30
    /// SPEC-028 — délai (ms) avant masquage des chevrons après sortie de zone.
    var fadeoutMs: Int     = 200

    // États de proximité (un par zone). Pilotés par onHover + delayed-hide.
    @State private var moveZoneActive: Bool = false
    @State private var reorderTopZoneActive: Bool = false
    @State private var reorderBottomZoneActive: Bool = false
    @State private var moveZoneHideTask: Task<Void, Never>?
    @State private var reorderTopHideTask: Task<Void, Never>?
    @State private var reorderBottomHideTask: Task<Void, Never>?

    private var moveChevronsVisible: Bool { chevronsAlwaysVisible || moveZoneActive }
    private var reorderTopVisible: Bool { chevronsAlwaysVisible || reorderTopZoneActive }
    private var reorderBottomVisible: Bool { chevronsAlwaysVisible || reorderBottomZoneActive }

    var body: some View {
        ZStack {
            previewContent
        }
        .frame(width: previewWidth, height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: previewRadius))
        .overlay(borderShape)
        // ── Zone trigger move-window (bande gauche) + 3 chevrons IMBRIQUÉS ──
        // Les chevrons sont placés DANS la zone trigger pour que le hover sur
        // un chevron ne fasse pas sortir le curseur de la zone (= bug v2 : la
        // zone et les chevrons étaient des overlays frères, l'enfant absorbait
        // le hover et la zone-mère recevait "ended" → les chevrons clignotaient).
        .overlay(alignment: .leading) {
            if showSummonButton, hasAnyMoveChevron {
                ZStack(alignment: .leading) {
                    Color.clear  // surface hit-test
                    if moveChevronsVisible {
                        VStack(alignment: .leading, spacing: 0) {
                            if let onMoveUp {
                                ChevronButton(direction: .up) {
                                    logInfo("rail_window_move_up", ["wid": String(wid)])
                                    onMoveUp()
                                }
                                .padding([.leading, .top], 4)
                            }
                            Spacer(minLength: 0)
                            if let onSummon {
                                ChevronButton(direction: .right) {
                                    logInfo("rail_window_summon", ["wid": String(wid)])
                                    onSummon()
                                }
                                .padding(.leading, 4)
                            }
                            Spacer(minLength: 0)
                            if let onMoveDown {
                                ChevronButton(direction: .down) {
                                    logInfo("rail_window_move_down", ["wid": String(wid)])
                                    onMoveDown()
                                }
                                .padding([.leading, .bottom], 4)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: moveZoneWidth, height: previewHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    scheduleHover(active: $moveZoneActive,
                                  task: $moveZoneHideTask,
                                  hovering: hovering)
                }
            }
        }
        // ── Zone trigger reorder TOP + chevron IMBRIQUÉ ──
        // Pas d'offset : .offset modifie le rendu visuel mais pas la layout
        // SwiftUI utilisée pour le hit-test → le hover ne déclenche pas.
        // Zone DANS la cellule, top de la vignette. Empiète légèrement sur le
        // contenu visuel (~10px) en échange d'un hover fiable.
        .overlay(alignment: .top) {
            if isStageRepresentative, onMoveStageUp != nil {
                ZStack {
                    Color.clear
                    if reorderTopVisible, let onMoveStageUp {
                        ChevronButton(direction: .up) {
                            logInfo("rail_arrow_tap", ["arrow": "chevron.up"])
                            onMoveStageUp()
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: previewWidth, height: reorderZoneHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    scheduleHover(active: $reorderTopZoneActive,
                                  task: $reorderTopHideTask,
                                  hovering: hovering)
                }
            }
        }
        // ── Zone trigger reorder BOTTOM + chevron IMBRIQUÉ ──
        .overlay(alignment: .bottom) {
            if isStageRepresentative, onMoveStageDown != nil {
                ZStack {
                    Color.clear
                    if reorderBottomVisible, let onMoveStageDown {
                        ChevronButton(direction: .down) {
                            logInfo("rail_arrow_tap", ["arrow": "chevron.down"])
                            onMoveStageDown()
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: previewWidth, height: reorderZoneHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    scheduleHover(active: $reorderBottomZoneActive,
                                  task: $reorderBottomHideTask,
                                  hovering: hovering)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: moveChevronsVisible)
        .animation(.easeInOut(duration: 0.15), value: reorderTopVisible)
        .animation(.easeInOut(duration: 0.15), value: reorderBottomVisible)
        // SPEC-028 — double-clic sur la vignette = summon. Le clic-droit reste
        // libre (futur menu contextuel plus riche).
        .onTapGesture(count: 2) {
            guard let onSummon, enableSummonDoubleClick else { return }
            onSummon()
        }
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .draggable(WindowDragData(wid: wid, sourceStageID: sourceStageID)) {
            // Preview du drag : reproduit la vignette pour le drag inter-stage
            // (drop sur une autre cellule = réassignation via dropDestination).
            ZStack {
                RoundedRectangle(cornerRadius: previewRadius)
                    .fill(Color.white.opacity(0.15))
                previewContent
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: previewRadius))
        }
    }

    /// Au moins un chevron move-window est dispo → la zone trigger gauche
    /// existe. Sinon la zone est inutile (= no-op).
    private var hasAnyMoveChevron: Bool {
        onMoveUp != nil || onSummon != nil || onMoveDown != nil
    }

    /// Hover-true → activer immédiatement. Hover-false → attendre `fadeoutMs`
    /// avant de désactiver (annulé si re-entrée dans la zone). Évite le
    /// clignotement quand le curseur rase les bords.
    private func scheduleHover(active: Binding<Bool>,
                               task: Binding<Task<Void, Never>?>,
                               hovering: Bool) {
        task.wrappedValue?.cancel()
        if hovering {
            active.wrappedValue = true
        } else {
            let delayMs = fadeoutMs
            task.wrappedValue = Task {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                if !Task.isCancelled {
                    await MainActor.run { active.wrappedValue = false }
                }
            }
        }
    }

    /// Bordure : tracé continu, pointillé long, ou pointillé fin selon `borderStyle`.
    @ViewBuilder
    private var borderShape: some View {
        let shape = RoundedRectangle(cornerRadius: previewRadius)
        switch borderStyle {
        case "dashed":
            shape.strokeBorder(borderColor,
                               style: StrokeStyle(lineWidth: borderWidth,
                                                  lineCap: .butt,
                                                  dash: [borderWidth * 8, borderWidth * 4]))
        case "dotted":
            shape.strokeBorder(borderColor,
                               style: StrokeStyle(lineWidth: borderWidth,
                                                  lineCap: .round,
                                                  dash: [0.1, borderWidth * 3]))
        default:
            shape.strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var previewContent: some View {
        if let thumb = thumbnail,
           !thumb.pngData.isEmpty,
           !thumb.degraded,
           let nsImage = NSImage(data: thumb.pngData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: previewWidth, height: previewHeight)
        } else if pid > 0,
                  let running = NSRunningApplication(processIdentifier: pid),
                  let icon = running.icon {
            // Fallback icône centrée sur fond semi-transparent (pid connu, app vivante).
            ZStack {
                RoundedRectangle(cornerRadius: previewRadius)
                    .fill(Color.white.opacity(0.05))
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            }
        } else if pid > 0 {
            // pid connu mais icône non disponible — fond neutre + icône générique.
            ZStack {
                Color(white: 0.12).opacity(0.90)
                Image(nsImage: resolvedIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .opacity(0.80)
            }
        }
        // pid == 0 (wid orpheline) : EmptyView implicite — filtré en amont dans
        // WindowStack.visibleWids, ce cas ne devrait pas atteindre ce composant.
    }

    // MARK: - Icône (même ordre de priorité que WindowChip)

    private var resolvedIcon: NSImage {
        Self.resolveIcon(pid: pid, bundleID: bundleID, appName: appName)
    }

    private static func resolveIcon(pid: Int32, bundleID: String, appName: String) -> NSImage {
        if pid > 0,
           let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName }),
           let icon = running.icon {
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        if !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
            return icon
        }
        let fallback = NSWorkspace.shared.icon(
            forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
        )
        fallback.size = NSSize(width: 40, height: 40)
        return fallback
    }
}
