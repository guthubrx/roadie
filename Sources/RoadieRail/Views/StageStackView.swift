import SwiftUI

// SPEC-014 T028 — Vue racine SwiftUI du rail. Design "Stage Manager natif".
// Reçoit RailState en @Bindable (pattern @Observable macOS 14+).
// Pas de header, stacks centrés verticalement, hint discret en bas.

private let stackSpacing: CGFloat = 32
private let hintOpacity:  CGFloat = 0.28

struct StageStackView: View {
    @Bindable var state: RailState
    /// SPEC-019 — UUID du display sur lequel ce panel est posé. Utilisé pour
    /// piocher `state.stagesByDisplay[displayUUID]`. Vide → fallback `state.stages`
    /// (compat). Sans cette donnée par-panel, les 2 panels affichaient le même
    /// `state.stages` partagé (bug observé avec 2 écrans).
    var displayUUID:   String                       = ""
    // SPEC-018 polish — halo de la stage active (couleur + intensité + radius lus depuis [fx.rail]).
    var haloColorHex:  String                       = "#34C759"
    var haloIntensity: Double                       = 0.75
    var haloRadius:    Double                       = 18
    // SPEC-019 — id du renderer actif (lu depuis [fx.rail].renderer). nil → fallback default.
    var rendererID:    String?                      = nil
    // SPEC-019 — paramètres scatter renderer "stacked-previews", lus depuis
    // [fx.rail.stacked] TOML. Defaults marqués (effet polaroïds éparpillés).
    var stackedOffsetX:   Double = 60
    var stackedOffsetY:   Double = 80
    var stackedRotation:  Double = 12
    var stackedScale:     Double = 0.06
    var stackedOpacity:   Double = 0.10
    var stackedScatterMode: String = "compass"
    // SPEC-019 — paramètres renderer "parallax-45", lus depuis [fx.rail.parallax].
    var parallaxRotation: Double = 35
    var parallaxOffsetX:  Double = 18
    var parallaxOffsetY:  Double = 8
    var parallaxScale:    Double = 0.05
    var parallaxOpacity:  Double = 0.10
    // SPEC-019 — taille vignettes et distance bord gauche, lus depuis [fx.rail.preview].
    var previewWidth:    Double = 200
    var previewHeight:   Double = 130
    var leadingPadding:  Double = 8
    var trailingPadding: Double = 16
    var verticalPadding: Double = 20
    // SPEC-019 — bordure des vignettes, paramétrable par renderer.
    var borderColor: String = "#FFFFFF26"
    var borderColorInactive: String = "#80808033"
    var borderWidth: Double = 0.5
    var borderStyle: String = "solid"
    var stageBorderOverrides: [String: String] = [:]
    var haloEnabled: Bool = true
    // SPEC-019 — assombrissement par couche pour parallax.
    var parallaxDarkenPerLayer: Double = 0.0
    // SPEC-014 T041 (US2) : callback de tap, câblé par RailController.
    var onTapStage:   (String) -> Void              = { _ in }
    // SPEC-014 T052 (US3) : callback de drop, (wid, target_stage_id).
    var onDropAssign: (CGWindowID, String) -> Void  = { _, _ in }
    // SPEC-014 T070 (US5) : callbacks menu contextuel.
    var onRename:     (String, String) -> Void      = { _, _ in }
    var onAddFocused: (String) -> Void              = { _ in }
    var onDelete:     (String) -> Void              = { _ in }
    // Click bureau Apple : zone vide du rail = hide stage active du display.
    var emptyClickHideActive:   Bool       = true
    var emptyClickSafetyMargin: Double     = 12
    var onEmptyClick:           () -> Void = {}

    /// Rects des thumbnails dans le coordinate space du rail. Mis à jour par
    /// `ThumbRectsKey` quand les renderers se rendent. Sert à filtrer les taps
    /// "click vide" qui tombent dans la ceinture de sécurité d'une thumbnail.
    @State private var thumbRects: [CGRect] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            stageList
            Spacer(minLength: 0)
            hintText
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "rail")
        .contentShape(Rectangle())
        // SwiftUI propage le tap aux enfants en priorité : si une thumbnail
        // l'absorbe via son propre `.onTapGesture`, ce handler racine n'est pas
        // appelé. Sinon, on vérifie si le tap tombe dans la ceinture de sécurité
        // d'une thumb (à `emptyClickSafetyMargin` px près) — si oui, ignoré.
        .onTapGesture(coordinateSpace: .named("rail")) { location in
            guard emptyClickHideActive else { return }
            let m = CGFloat(emptyClickSafetyMargin)
            for rect in thumbRects {
                if rect.insetBy(dx: -m, dy: -m).contains(location) { return }
            }
            onEmptyClick()
        }
        .onPreferenceChange(ThumbRectsKey.self) { rects in
            thumbRects = rects
        }
        // Fond strictement transparent (demande utilisateur explicite, 3x).
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stageList: some View {
        // Invariant utilisateur : si le daemon a au moins une stage, le rail DOIT
        // l'afficher — peu importe que les wids du rail (state.windows/thumbnails)
        // soient déjà arrivées en async ou non. Le double-filtre précédent créait
        // une fenêtre de race au boot où "No stages yet" s'affichait alors que
        // stage 1 existait pourtant. Le renderer gère le placeholder pour stage vide.
        // SPEC-019 — chaque panel lit ses propres stages via son UUID display.
        // Fallback sur `state.stages` (compat) si UUID vide ou pas encore peuplé
        // dans `stagesByDisplay`.
        let allStages: [StageVM] = {
            if !displayUUID.isEmpty, let scoped = state.stagesByDisplay[displayUUID] {
                return scoped
            }
            return state.stages
        }()
        if allStages.isEmpty {
            // Cas pathologique : daemon n'a pas encore répondu OU stages réellement
            // vides. Stage 1 est immortelle côté daemon donc ce cas est transitoire.
            Text("No stages yet")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            // GeometryReader + frame(minHeight:alignment:) : quand peu de stacks,
            // le VStack occupe toute la hauteur visible et est centré verticalement.
            // Quand le contenu dépasse, le ScrollView prend le relais naturellement.
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: stackSpacing) {
                        ForEach(allStages) { stage in
                            // SPEC-019 — délégation au renderer actif (récupéré depuis le registre
                            // via l'id [fx.rail].renderer, fallback "stacked-previews"). Le consommateur
                            // ne connaît pas la stratégie concrète du rendu de cellule.
                            let renderer = StageRendererRegistry.makeOrFallback(id: rendererID)
                            let context = StageRenderContext(
                                stage: stage,
                                windows: state.windows,
                                thumbnails: state.thumbnails,
                                haloColorHex: haloColorHex,
                                haloIntensity: haloIntensity,
                                haloRadius: haloRadius,
                                stackedOffsetX: stackedOffsetX,
                                stackedOffsetY: stackedOffsetY,
                                stackedRotation: stackedRotation,
                                stackedScale: stackedScale,
                                stackedOpacity: stackedOpacity,
                                stackedScatterMode: stackedScatterMode,
                                parallaxRotation: parallaxRotation,
                                parallaxOffsetX: parallaxOffsetX,
                                parallaxOffsetY: parallaxOffsetY,
                                parallaxScale: parallaxScale,
                                parallaxOpacity: parallaxOpacity,
                                previewWidth: previewWidth,
                                previewHeight: previewHeight,
                                leadingPadding: leadingPadding,
                                trailingPadding: trailingPadding,
                                verticalPadding: verticalPadding,
                                borderColor: borderColor,
                                borderColorInactive: borderColorInactive,
                                borderWidth: borderWidth,
                                borderStyle: borderStyle,
                                stageBorderOverrides: stageBorderOverrides,
                                haloEnabled: haloEnabled,
                                parallaxDarkenPerLayer: parallaxDarkenPerLayer
                            )
                            let cb = StageRendererCallbacks(
                                onTap:        { onTapStage(stage.id) },
                                onDropAssign: onDropAssign,
                                onRename:     onRename,
                                onAddFocused: onAddFocused,
                                onDelete:     onDelete
                            )
                            renderer.render(context: context, callbacks: cb)
                            // Aligner à gauche (vs centre) — demande utilisateur.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Expose le rect de cette cellule dans le coordinate
                            // space "rail" pour le hit-test "click vide" du body.
                            // Le tap geste racine ignore les clicks tombés dans la
                            // ceinture de `emptyClickSafetyMargin` autour de ce rect.
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ThumbRectsKey.self,
                                        value: [proxy.frame(in: .named("rail"))]
                                    )
                                }
                            )
                        }
                    }
                    // SPEC-019 — pas de padding ici : chaque renderer gère son propre
                    // padding via context.leadingPadding/trailingPadding/verticalPadding
                    // (résolus avec overrides per-renderer). Évite le double-padding.
                    .frame(minHeight: geo.size.height, alignment: .center)
                }
            }
        }
    }

    private var hintText: some View {
        Text("Click to switch • Drag to move")
            .font(.system(size: 9, weight: .regular).monospaced())
            .foregroundStyle(Color.white.opacity(hintOpacity))
            .multilineTextAlignment(.center)
    }

    // Fond HUD : NSVisualEffectView natif + tint sombre par-dessus.
    // Tint abaissé à 0.35 : laisse le flou natif .hudWindow dominer.
    private var hudBackground: some View {
        ZStack {
            HUDBackground()
            Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

/// Collecte les rects (dans le coordinate space "rail") de toutes les
/// thumbnails rendues. Le body de `StageStackView` les consomme pour
/// décider si un tap "click vide" doit être ignoré (ceinture de sécurité)
/// ou déclencher `onEmptyClick`.
private struct ThumbRectsKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
