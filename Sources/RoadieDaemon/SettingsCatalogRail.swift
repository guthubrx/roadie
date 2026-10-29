import Foundation
import RoadieCore

// Réglages du rail (75 clés scalaires). Défauts et plages relus dans `RailSettings.load(raw:)` :
// le rail lit son propre fichier ligne à ligne et borne chaque nombre à la plage ci-dessous.
// Tous les nombres sont des `.double` : le rail les lit avec `Double(...)`, entiers ou non.
// La table héritée `fx.rail.header` n'est pas décrite : elle ne sert qu'à fournir des défauts.

extension SettingsCatalog {
    static let railDescriptors: [SettingDescriptor] = railMain + railLayout + railStages + railPreview
        + railStacked + railParallax + railLabels

    private static let weights = ["regular", "medium", "semibold", "bold"]
    private static let alignments = ["left", "center", "right"]
    private static let positions = ["top", "center", "bottom"]

    private static let railMain: [SettingDescriptor] = {
        let t = "fx.rail"
        return [
            entry(.rail, t, "renderer", tr("Style du rail", "Rail style"),
                  tr("Façon d'afficher les stages : aperçus empilés (stacked-previews), mosaïque (mosaic), perspective (parallax-45) ou icônes seules (icons-only).", "How stages are shown: stacked previews (stacked-previews), mosaic (mosaic), perspective (parallax-45) or icons only (icons-only)."),
                  .choice(["stacked-previews", "mosaic", "parallax-45", "icons-only"]), .string("stacked-previews")),
            entry(.rail, t, "width", tr("Largeur du rail (points)", "Rail width (points)"),
                  tr("Largeur de la bande du rail.", "Width of the rail strip."), .double(90...320), .double(150)),
            entry(.rail, t, "background_color", tr("Couleur de fond", "Background color"),
                  tr("Couleur de fond du rail.", "Background color of the rail."), .color, .string("#000000")),
            entry(.rail, t, "background_opacity", tr("Opacité du fond", "Background opacity"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(0)),
            entry(.rail, t, "auto_hide", tr("Masquer automatiquement", "Hide automatically"),
                  tr("Cache le rail et le fait réapparaître au bord de l'écran.", "Hides the rail and brings it back at the edge of the display."), .bool, .bool(false)),
            entry(.rail, t, "edge_hit_width", tr("Zone de réveil au bord (points)", "Edge wake-up zone (points)"),
                  tr("Largeur de la bande du bord de l'écran qui fait réapparaître le rail.", "Width of the display-edge strip that brings the rail back."), .double(1...40), .double(8)),
            entry(.rail, t, "edge_magnetism_width", tr("Attraction du bord (points)", "Edge attraction (points)"),
                  tr("Distance à laquelle le pointeur est attiré par le bord pour faire apparaître le rail.", "Distance at which the pointer is pulled to the edge to show the rail."), .double(0...160), .double(24)),
            entry(.rail, t, "animation_ms", tr("Durée de l'animation (ms)", "Animation duration (ms)"),
                  tr("Durée de l'apparition et de la disparition du rail.", "Duration of the rail appearing and disappearing."), .double(0...1000), .double(160)),
            entry(.rail, t, "hide_delay_ms", tr("Délai avant masquage (ms)", "Delay before hiding (ms)"),
                  tr("Attente entre la sortie du pointeur et la disparition du rail.", "Wait between the pointer leaving and the rail disappearing."), .double(0...5000), .double(350)),
            entry(.rail, t, "layout_mode", tr("Place prise par le rail", "Space taken by the rail"),
                  tr("« overlay » : le rail recouvre les fenêtres ; « resize » : les fenêtres se réduisent pour lui laisser la place.", "“overlay”: the rail covers the windows; “resize”: windows shrink to make room for it."),
                  .choice(["overlay", "resize"]), .string("overlay")),
            entry(.rail, t, "dynamic_left_gap", tr("Marge gauche dynamique", "Dynamic left gap"),
                  tr("Ajuste la marge gauche des fenêtres selon la présence du rail.", "Adjusts the windows' left gap depending on whether the rail is shown."), .bool, .bool(false)),
            entry(.rail, t, "empty_click_hide_active", tr("Clic dans le vide : masquer", "Click on empty space: hide"),
                  tr("Un clic dans une zone vide du rail masque le stage actif.", "A click on an empty area of the rail hides the active stage."), .bool, .bool(false)),
            entry(.rail, t, "empty_click_safety_margin", tr("Marge de sécurité du clic dans le vide (points)", "Empty-click safety margin (points)"),
                  tr("Distance autour des cartes où un clic n'est pas compté comme un clic dans le vide.", "Distance around the cards where a click does not count as a click on empty space."), .double(0...80), .double(12)),
            entry(.rail, t, "hide_on_maximized", tr("Masquer devant une fenêtre agrandie", "Hide in front of a maximized window"),
                  tr("Cache aussi le rail devant une fenêtre agrandie, pas seulement en plein écran natif.", "Also hides the rail in front of a maximized window, not only in native full screen."), .bool, .bool(false)),
        ]
    }()

    private static let railLayout: [SettingDescriptor] = {
        let t = "fx.rail.layout"
        return [
            entry(.rail, t, "header_position", tr("Position de l'en-tête", "Header position"),
                  tr("Place des noms d'écran et de bureau : en haut, en bas ou masqués.", "Where display and desktop names go: top, bottom or hidden."),
                  .choice(["top", "bottom", "hidden"]), .string("top")),
            entry(.rail, t, "stages_position", tr("Position des stages", "Stage position"),
                  tr("Place de la liste des stages dans le rail.", "Where the stage list sits in the rail."), .choice(positions), .string("center")),
            entry(.rail, t, "spacing", tr("Espacement (points)", "Spacing (points)"),
                  tr("Espace entre les éléments du rail.", "Space between rail items."), .double(0...80), .double(13)),
            entry(.rail, t, "top_padding", tr("Marge haute (points)", "Top margin (points)"),
                  tr("Espace laissé en haut du rail.", "Space left at the top of the rail."), .double(0...240), .double(50)),
            entry(.rail, t, "bottom_padding", tr("Marge basse (points)", "Bottom margin (points)"),
                  tr("Espace laissé en bas du rail.", "Space left at the bottom of the rail."), .double(0...240), .double(16)),
        ]
    }()

    private static let railStages: [SettingDescriptor] = {
        let t = "fx.rail.stages"
        return [
            entry(.rail, t, "position", tr("Position de la liste", "List position"),
                  tr("Place de la liste des stages dans la hauteur du rail.", "Where the stage list sits in the rail's height."), .choice(positions), .string("center")),
            entry(.rail, t, "alignment", tr("Alignement des cartes", "Card alignment"),
                  tr("Alignement horizontal des cartes de stage.", "Horizontal alignment of stage cards."), .choice(alignments), .string("center")),
            entry(.rail, t, "reorder_magnetism", tr("Aimantation du réordonnancement (%)", "Reorder snapping (%)"),
                  tr("Stabilise la destination de l’aperçu pendant le glissement. 0 désactive l’aimantation ; 100 tolère davantage de petits mouvements. Le curseur ne bouge pas tout seul.", "Steadies the preview destination while dragging. 0 turns snapping off; 100 tolerates more small movements. The pointer never moves on its own."), .double(0...100), .double(50)),
            entry(.rail, t, "slot_height", tr("Hauteur d’un emplacement (points)", "Slot height (points)"),
                  tr("Hauteur commune des stages vides et occupés. Minimum 80 points ; 0 conserve la hauteur automatique.", "Shared height of empty and occupied stages. Minimum 80 points; 0 keeps the automatic height."), .double(0...320), .double(0)),
            entry(.rail, t, "gap", tr("Espace entre les emplacements (points)", "Space between slots (points)"),
                  tr("Espace ajouté entre deux emplacements. La hauteur des emplacements règle aussi la distance entre les vignettes.", "Space added between two slots. The slot height also sets the distance between thumbnails."), .double(0...80), .double(13)),
        ]
    }()

    private static let railPreview: [SettingDescriptor] = {
        let t = "fx.rail.preview"
        return [
            entry(.rail, t, "width", tr("Largeur des aperçus (points)", "Preview width (points)"),
                  tr("Largeur de l'aperçu d'un stage.", "Width of a stage preview."), .double(60...240), .double(160)),
            entry(.rail, t, "height", tr("Hauteur des aperçus (points)", "Preview height (points)"),
                  tr("Hauteur de l'aperçu d'un stage.", "Height of a stage preview."), .double(40...180), .double(104)),
            entry(.rail, t, "leading_padding", tr("Marge avant des aperçus (points)", "Preview leading margin (points)"),
                  tr("Espace à gauche de l'aperçu.", "Space to the left of the preview."), .double(0...80), .double(8)),
            entry(.rail, t, "trailing_padding", tr("Marge arrière des aperçus (points)", "Preview trailing margin (points)"),
                  tr("Espace à droite de l'aperçu.", "Space to the right of the preview."), .double(0...80), .double(16)),
            entry(.rail, t, "vertical_padding", tr("Marge verticale des aperçus (points)", "Preview vertical margin (points)"),
                  tr("Espace au-dessus et au-dessous de l'aperçu.", "Space above and below the preview."), .double(0...80), .double(20)),
            readOnlyEntry(.rail, t, "stage_overrides", tr("Couleur d'accent par stage", "Accent color per stage"),
                          tr("Tableau de couleurs d'accent propres à certains stages.", "Table of accent colors specific to some stages.")),
        ]
    }()

    private static let railStacked: [SettingDescriptor] = {
        let t = "fx.rail.stacked"
        return [
            entry(.rail, t, "offset_x", tr("Décalage horizontal des couches (points)", "Horizontal layer offset (points)"),
                  tr("Décalage de chaque couche de l'empilement vers la droite.", "Offset of each stacked layer to the right."), .double(0...120), .double(60)),
            entry(.rail, t, "offset_y", tr("Décalage vertical des couches (points)", "Vertical layer offset (points)"),
                  tr("Décalage de chaque couche de l'empilement vers le bas.", "Offset of each stacked layer downward."), .double(0...120), .double(80)),
            entry(.rail, t, "scale_per_layer", tr("Réduction par couche", "Shrink per layer"),
                  tr("Part de taille retirée à chaque couche (0,05 = 5 %).", "Share of size removed at each layer (0.05 = 5%)."), .double(0...0.30), .double(0.05)),
            entry(.rail, t, "opacity_per_layer", tr("Transparence par couche", "Transparency per layer"),
                  tr("Opacité retirée à chaque couche.", "Opacity removed at each layer."), .double(0...0.50), .double(0.08)),
        ]
    }()

    private static let railParallax: [SettingDescriptor] = {
        let t = "fx.rail.parallax"
        return [
            entry(.rail, t, "rotation", tr("Rotation (degrés)", "Rotation (degrees)"),
                  tr("Angle de rotation des aperçus en perspective.", "Rotation angle of the perspective previews."), .double(0...75), .double(35)),
            entry(.rail, t, "offset_x", tr("Décalage horizontal des couches (points)", "Horizontal layer offset (points)"),
                  tr("Décalage de chaque couche vers la droite.", "Offset of each layer to the right."), .double(0...80), .double(25)),
            entry(.rail, t, "offset_y", tr("Décalage vertical des couches (points)", "Vertical layer offset (points)"),
                  tr("Décalage de chaque couche vers le bas.", "Offset of each layer downward."), .double(0...80), .double(18)),
            entry(.rail, t, "scale_per_layer", tr("Réduction par couche", "Shrink per layer"),
                  tr("Part de taille retirée à chaque couche (0,08 = 8 %).", "Share of size removed at each layer (0.08 = 8%)."), .double(0...0.30), .double(0.08)),
            entry(.rail, t, "opacity_per_layer", tr("Transparence par couche", "Transparency per layer"),
                  tr("Opacité retirée à chaque couche.", "Opacity removed at each layer."), .double(0...0.50), .double(0.20)),
            entry(.rail, t, "darken_per_layer", tr("Assombrissement par couche", "Darkening per layer"),
                  tr("Part de noir ajoutée à chaque couche.", "Share of black added at each layer."), .double(0...1), .double(0.15)),
            entry(.rail, t, "width", tr("Largeur des aperçus (points)", "Preview width (points)"),
                  tr("Largeur de l'aperçu en perspective.", "Width of the perspective preview."), .double(60...240), .double(160)),
            entry(.rail, t, "height", tr("Hauteur des aperçus (points)", "Preview height (points)"),
                  tr("Hauteur de l'aperçu en perspective.", "Height of the perspective preview."), .double(40...180), .double(104)),
            entry(.rail, t, "leading_padding", tr("Marge avant des aperçus (points)", "Preview leading margin (points)"),
                  tr("Espace à gauche de l'aperçu en perspective.", "Space to the left of the perspective preview."), .double(0...80), .double(8)),
            entry(.rail, t, "trailing_padding", tr("Marge arrière des aperçus (points)", "Preview trailing margin (points)"),
                  tr("Espace à droite de l'aperçu en perspective.", "Space to the right of the perspective preview."), .double(0...80), .double(16)),
            entry(.rail, t, "vertical_padding", tr("Marge verticale des aperçus (points)", "Preview vertical margin (points)"),
                  tr("Espace au-dessus et au-dessous de l'aperçu en perspective.", "Space above and below the perspective preview."), .double(0...80), .double(20)),
        ]
    }()

    /// Noms d'écran et de bureau (même forme), puis noms de stage.
    private static let railLabels: [SettingDescriptor] =
        headerLabel("fx.rail.header.display", tr("du nom d'écran", "for the display name"), template: "{display}", color: "#FFFFFFDB",
                    size: 13, maxSize: 40, weight: "bold")
        + headerLabel("fx.rail.header.desktop", tr("du nom de bureau", "for the desktop name"), template: tr("Bureau {desktop}", "Desktop {desktop}"), color: "#FFFFFF6B",
                      size: 10, maxSize: 32, weight: "medium")
        + stageLabels

    /// 10 réglages d'un libellé d'en-tête. `of` complète les libellés (« du nom d'écran »).
    private static func headerLabel(
        _ table: String, _ of: String, template: String, color: String, size: Double, maxSize: Double, weight: String
    ) -> [SettingDescriptor] {
        [
            entry(.rail, table, "enabled", tr("Afficher le texte \(of)", "Show text \(of)"),
                  tr("Montre ou cache ce texte dans l'en-tête du rail.", "Shows or hides this text in the rail header."), .bool, .bool(true)),
            entry(.rail, table, "template", tr("Modèle \(of)", "Template \(of)"),
                  tr("Texte affiché. Les mots entre accolades, comme {display} ou {desktop}, sont remplacés.", "Text shown. Words in braces, like {display} or {desktop}, are replaced."), .text, .string(template)),
            entry(.rail, table, "color", tr("Couleur \(of)", "Color \(of)"),
                  tr("Couleur du texte.", "Text color."), .color, .string(color)),
            entry(.rail, table, "font_size", tr("Taille \(of) (points)", "Size \(of) (points)"),
                  tr("Taille du texte.", "Text size."), .double(6...maxSize), .double(size)),
            entry(.rail, table, "font_family", tr("Police \(of)", "Font \(of)"),
                  tr("Nom de la police, ou « system » pour la police du système.", "Font name, or “system” for the system font."), .text, .string("system")),
            entry(.rail, table, "weight", tr("Graisse \(of)", "Weight \(of)"),
                  tr("Épaisseur des caractères.", "Thickness of the characters."), .choice(weights), .string(weight)),
            entry(.rail, table, "alignment", tr("Alignement \(of)", "Alignment \(of)"),
                  tr("Alignement horizontal du texte.", "Horizontal alignment of the text."), .choice(alignments), .string("center")),
            entry(.rail, table, "opacity", tr("Opacité \(of)", "Opacity \(of)"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(1)),
            entry(.rail, table, "offset_x", tr("Décalage horizontal \(of) (points)", "Horizontal offset \(of) (points)"),
                  tr("Déplace le texte vers la droite (valeur positive) ou la gauche.", "Moves the text right (positive value) or left."), .double(-120...120), .double(0)),
            entry(.rail, table, "offset_y", tr("Décalage vertical \(of) (points)", "Vertical offset \(of) (points)"),
                  tr("Déplace le texte vers le haut (valeur positive) ou le bas.", "Moves the text up (positive value) or down."), .double(-120...120), .double(0)),
        ]
    }

    private static let stageLabels: [SettingDescriptor] = {
        let t = "fx.rail.stage_labels"
        return [
            entry(.rail, t, "enabled", tr("Afficher les noms de stage", "Show stage names"),
                  tr("Montre le nom de chaque stage sous sa carte.", "Shows each stage's name under its card."), .bool, .bool(true)),
            entry(.rail, t, "color", tr("Couleur des noms de stage", "Stage name color"),
                  tr("Couleur hexadécimale du texte, ou « stage » pour reprendre la couleur d'accent du stage.", "Hex color of the text, or “stage” to use the stage's accent color."), .text, .string("stage")),
            entry(.rail, t, "font_size", tr("Taille des détails du rail (points)", "Rail detail size (points)"),
                  tr("Taille des lettres, compteurs, indicateur d’enregistrement et menus. Sert aussi aux légendes dont la taille indépendante vaut 0.", "Size of letters, counters, recording indicator and menus. Also used for captions whose own size is 0."), .double(6...28), .double(11)),
            entry(.rail, t, "caption_font_size", tr("Taille de la légende (points)", "Caption size (points)"),
                  tr("Taille indépendante du numéro et du nom. 0 reprend la taille des détails du rail.", "Own size of the number and name. 0 uses the rail detail size."), .double(0...28), .double(0)),
            entry(.rail, t, "gap", tr("Écart entre vignette et légende (points)", "Gap between thumbnail and caption (points)"),
                  tr("Distance entre le contour de la vignette et sa légende.", "Distance between the thumbnail outline and its caption."), .double(0...24), .double(4)),
            entry(.rail, t, "follows_perspective", tr("La légende suit la perspective", "Caption follows perspective"),
                  tr("Incline et comprime le texte comme l'aperçu parallax. Désactivé : texte droit.", "Tilts and compresses the text like the parallax preview. Off: straight text."), .bool, .bool(false)),
            entry(.rail, t, "font_family", tr("Police des noms de stage", "Stage name font"),
                  tr("Nom de la police, ou « system » pour la police du système.", "Font name, or “system” for the system font."), .text, .string("system")),
            entry(.rail, t, "weight", tr("Graisse des noms de stage", "Stage name weight"),
                  tr("Épaisseur des caractères.", "Thickness of the characters."), .choice(weights), .string("semibold")),
            entry(.rail, t, "alignment", tr("Alignement des noms de stage", "Stage name alignment"),
                  tr("Alignement horizontal du texte.", "Horizontal alignment of the text."), .choice(alignments), .string("center")),
            entry(.rail, t, "opacity", tr("Opacité des noms de stage", "Stage name opacity"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(0.72)),
            entry(.rail, t, "offset_x", tr("Décalage horizontal des noms de stage (points)", "Stage name horizontal offset (points)"),
                  tr("Déplace le texte vers la droite (valeur positive) ou la gauche.", "Moves the text right (positive value) or left."), .double(-120...120), .double(0)),
            entry(.rail, t, "offset_y", tr("Décalage vertical des noms de stage (points)", "Stage name vertical offset (points)"),
                  tr("Déplace le texte vers le haut (valeur positive) ou le bas.", "Moves the text up (positive value) or down."), .double(-120...120), .double(0)),
            entry(.rail, t, "placement", tr("Place des noms de stage", "Stage name placement"),
                  tr("Le nom se place au-dessus (above) ou au-dessous (below) de la carte.", "The name goes above (above) or below (below) the card."),
                  .choice(["above", "below"]), .string("below")),
            entry(.rail, t, "z_order", tr("Superposition des noms de stage", "Stage name layering"),
                  tr("Le nom passe sous (below) ou sur (above) la carte quand ils se recouvrent.", "The name goes under (below) or over (above) the card when they overlap."),
                  .choice(["below", "above"]), .string("below")),
            entry(.rail, t, "visibility_seconds", tr("Durée d'affichage des noms de stage (secondes)", "Stage name display time (seconds)"),
                  tr("0 : toujours visibles. Sinon, les noms disparaissent après ce délai.", "0: always visible. Otherwise, names disappear after this delay."), .double(0...3600), .double(0)),
            entry(.rail, t, "fade_seconds", tr("Durée du fondu des noms de stage (secondes)", "Stage name fade duration (seconds)"),
                  tr("Temps mis par les noms pour disparaître.", "Time the names take to fade out."), .double(0...10), .double(0.35)),
        ]
    }()
}
