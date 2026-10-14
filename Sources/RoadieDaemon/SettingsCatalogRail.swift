import Foundation

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
            entry(.rail, t, "renderer", "Style du rail",
                  "Façon d'afficher les stages : aperçus empilés (stacked-previews), mosaïque (mosaic), perspective (parallax-45) ou icônes seules (icons-only).",
                  .choice(["stacked-previews", "mosaic", "parallax-45", "icons-only"]), .string("stacked-previews")),
            entry(.rail, t, "width", "Largeur du rail (points)",
                  "Largeur de la bande du rail.", .double(90...320), .double(150)),
            entry(.rail, t, "background_color", "Couleur de fond",
                  "Couleur de fond du rail.", .color, .string("#000000")),
            entry(.rail, t, "background_opacity", "Opacité du fond",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(0)),
            entry(.rail, t, "auto_hide", "Masquer automatiquement",
                  "Cache le rail et le fait réapparaître au bord de l'écran.", .bool, .bool(false)),
            entry(.rail, t, "edge_hit_width", "Zone de réveil au bord (points)",
                  "Largeur de la bande du bord de l'écran qui fait réapparaître le rail.", .double(1...40), .double(8)),
            entry(.rail, t, "edge_magnetism_width", "Attraction du bord (points)",
                  "Distance à laquelle le pointeur est attiré par le bord pour faire apparaître le rail.", .double(0...160), .double(24)),
            entry(.rail, t, "animation_ms", "Durée de l'animation (ms)",
                  "Durée de l'apparition et de la disparition du rail.", .double(0...1000), .double(160)),
            entry(.rail, t, "hide_delay_ms", "Délai avant masquage (ms)",
                  "Attente entre la sortie du pointeur et la disparition du rail.", .double(0...5000), .double(350)),
            entry(.rail, t, "layout_mode", "Place prise par le rail",
                  "« overlay » : le rail recouvre les fenêtres ; « resize » : les fenêtres se réduisent pour lui laisser la place.",
                  .choice(["overlay", "resize"]), .string("overlay")),
            entry(.rail, t, "dynamic_left_gap", "Marge gauche dynamique",
                  "Ajuste la marge gauche des fenêtres selon la présence du rail.", .bool, .bool(false)),
            entry(.rail, t, "empty_click_hide_active", "Clic dans le vide : masquer",
                  "Un clic dans une zone vide du rail masque le stage actif.", .bool, .bool(false)),
            entry(.rail, t, "empty_click_safety_margin", "Marge de sécurité du clic dans le vide (points)",
                  "Distance autour des cartes où un clic n'est pas compté comme un clic dans le vide.", .double(0...80), .double(12)),
            entry(.rail, t, "hide_on_maximized", "Masquer devant une fenêtre agrandie",
                  "Cache aussi le rail devant une fenêtre agrandie, pas seulement en plein écran natif.", .bool, .bool(false)),
        ]
    }()

    private static let railLayout: [SettingDescriptor] = {
        let t = "fx.rail.layout"
        return [
            entry(.rail, t, "header_position", "Position de l'en-tête",
                  "Place des noms d'écran et de bureau : en haut, en bas ou masqués.",
                  .choice(["top", "bottom", "hidden"]), .string("top")),
            entry(.rail, t, "stages_position", "Position des stages",
                  "Place de la liste des stages dans le rail.", .choice(positions), .string("center")),
            entry(.rail, t, "spacing", "Espacement (points)",
                  "Espace entre les éléments du rail.", .double(0...80), .double(13)),
            entry(.rail, t, "top_padding", "Marge haute (points)",
                  "Espace laissé en haut du rail.", .double(0...240), .double(50)),
            entry(.rail, t, "bottom_padding", "Marge basse (points)",
                  "Espace laissé en bas du rail.", .double(0...240), .double(16)),
        ]
    }()

    private static let railStages: [SettingDescriptor] = {
        let t = "fx.rail.stages"
        return [
            entry(.rail, t, "position", "Position de la liste",
                  "Place de la liste des stages dans la hauteur du rail.", .choice(positions), .string("center")),
            entry(.rail, t, "alignment", "Alignement des cartes",
                  "Alignement horizontal des cartes de stage.", .choice(alignments), .string("center")),
            entry(.rail, t, "gap", "Espace entre les cartes (points)",
                  "Espace entre deux cartes de stage.", .double(0...80), .double(13)),
        ]
    }()

    private static let railPreview: [SettingDescriptor] = {
        let t = "fx.rail.preview"
        return [
            entry(.rail, t, "width", "Largeur des aperçus (points)",
                  "Largeur de l'aperçu d'un stage.", .double(60...240), .double(160)),
            entry(.rail, t, "height", "Hauteur des aperçus (points)",
                  "Hauteur de l'aperçu d'un stage.", .double(40...180), .double(104)),
            entry(.rail, t, "leading_padding", "Marge avant des aperçus (points)",
                  "Espace à gauche de l'aperçu.", .double(0...80), .double(8)),
            entry(.rail, t, "trailing_padding", "Marge arrière des aperçus (points)",
                  "Espace à droite de l'aperçu.", .double(0...80), .double(16)),
            entry(.rail, t, "vertical_padding", "Marge verticale des aperçus (points)",
                  "Espace au-dessus et au-dessous de l'aperçu.", .double(0...80), .double(20)),
            readOnlyEntry(.avance, t, "stage_overrides", "Couleur d'accent par stage",
                          "Tableau de couleurs d'accent propres à certains stages."),
        ]
    }()

    private static let railStacked: [SettingDescriptor] = {
        let t = "fx.rail.stacked"
        return [
            entry(.rail, t, "offset_x", "Décalage horizontal des couches (points)",
                  "Décalage de chaque couche de l'empilement vers la droite.", .double(0...120), .double(60)),
            entry(.rail, t, "offset_y", "Décalage vertical des couches (points)",
                  "Décalage de chaque couche de l'empilement vers le bas.", .double(0...120), .double(80)),
            entry(.rail, t, "scale_per_layer", "Réduction par couche",
                  "Part de taille retirée à chaque couche (0,05 = 5 %).", .double(0...0.30), .double(0.05)),
            entry(.rail, t, "opacity_per_layer", "Transparence par couche",
                  "Opacité retirée à chaque couche.", .double(0...0.50), .double(0.08)),
        ]
    }()

    private static let railParallax: [SettingDescriptor] = {
        let t = "fx.rail.parallax"
        return [
            entry(.rail, t, "rotation", "Rotation (degrés)",
                  "Angle de rotation des aperçus en perspective.", .double(0...75), .double(35)),
            entry(.rail, t, "offset_x", "Décalage horizontal des couches (points)",
                  "Décalage de chaque couche vers la droite.", .double(0...80), .double(25)),
            entry(.rail, t, "offset_y", "Décalage vertical des couches (points)",
                  "Décalage de chaque couche vers le bas.", .double(0...80), .double(18)),
            entry(.rail, t, "scale_per_layer", "Réduction par couche",
                  "Part de taille retirée à chaque couche (0,08 = 8 %).", .double(0...0.30), .double(0.08)),
            entry(.rail, t, "opacity_per_layer", "Transparence par couche",
                  "Opacité retirée à chaque couche.", .double(0...0.50), .double(0.20)),
            entry(.rail, t, "darken_per_layer", "Assombrissement par couche",
                  "Part de noir ajoutée à chaque couche.", .double(0...1), .double(0.15)),
            entry(.rail, t, "width", "Largeur des aperçus (points)",
                  "Largeur de l'aperçu en perspective.", .double(60...240), .double(160)),
            entry(.rail, t, "height", "Hauteur des aperçus (points)",
                  "Hauteur de l'aperçu en perspective.", .double(40...180), .double(104)),
            entry(.rail, t, "leading_padding", "Marge avant des aperçus (points)",
                  "Espace à gauche de l'aperçu en perspective.", .double(0...80), .double(8)),
            entry(.rail, t, "trailing_padding", "Marge arrière des aperçus (points)",
                  "Espace à droite de l'aperçu en perspective.", .double(0...80), .double(16)),
            entry(.rail, t, "vertical_padding", "Marge verticale des aperçus (points)",
                  "Espace au-dessus et au-dessous de l'aperçu en perspective.", .double(0...80), .double(20)),
        ]
    }()

    /// Noms d'écran et de bureau (même forme), puis noms de stage.
    private static let railLabels: [SettingDescriptor] =
        headerLabel("fx.rail.header.display", "du nom d'écran", template: "{display}", color: "#FFFFFFDB",
                    size: 13, maxSize: 40, weight: "bold")
        + headerLabel("fx.rail.header.desktop", "du nom de bureau", template: "Desktop {desktop}", color: "#FFFFFF6B",
                      size: 10, maxSize: 32, weight: "medium")
        + stageLabels

    /// 10 réglages d'un libellé d'en-tête. `of` complète les libellés (« du nom d'écran »).
    private static func headerLabel(
        _ table: String, _ of: String, template: String, color: String, size: Double, maxSize: Double, weight: String
    ) -> [SettingDescriptor] {
        [
            entry(.rail, table, "enabled", "Afficher le texte \(of)",
                  "Montre ou cache ce texte dans l'en-tête du rail.", .bool, .bool(true)),
            entry(.rail, table, "template", "Modèle \(of)",
                  "Texte affiché. Les mots entre accolades, comme {display} ou {desktop}, sont remplacés.", .text, .string(template)),
            entry(.rail, table, "color", "Couleur \(of)",
                  "Couleur du texte.", .color, .string(color)),
            entry(.rail, table, "font_size", "Taille \(of) (points)",
                  "Taille du texte.", .double(6...maxSize), .double(size)),
            entry(.rail, table, "font_family", "Police \(of)",
                  "Nom de la police, ou « system » pour la police du système.", .text, .string("system")),
            entry(.rail, table, "weight", "Graisse \(of)",
                  "Épaisseur des caractères.", .choice(weights), .string(weight)),
            entry(.rail, table, "alignment", "Alignement \(of)",
                  "Alignement horizontal du texte.", .choice(alignments), .string("center")),
            entry(.rail, table, "opacity", "Opacité \(of)",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(1)),
            entry(.rail, table, "offset_x", "Décalage horizontal \(of) (points)",
                  "Déplace le texte vers la droite (valeur positive) ou la gauche.", .double(-120...120), .double(0)),
            entry(.rail, table, "offset_y", "Décalage vertical \(of) (points)",
                  "Déplace le texte vers le haut (valeur positive) ou le bas.", .double(-120...120), .double(0)),
        ]
    }

    private static let stageLabels: [SettingDescriptor] = {
        let t = "fx.rail.stage_labels"
        return [
            entry(.rail, t, "enabled", "Afficher les noms de stage",
                  "Montre le nom de chaque stage sous sa carte.", .bool, .bool(true)),
            entry(.rail, t, "color", "Couleur des noms de stage",
                  "Couleur hexadécimale du texte, ou « stage » pour reprendre la couleur d'accent du stage.", .text, .string("stage")),
            entry(.rail, t, "font_size", "Taille des textes de stage et des détails (points)",
                  "Taille des noms de stage, lettres des cartes, compteurs, indicateur d'enregistrement et menus du rail. Le changement s'applique immédiatement.", .double(6...28), .double(11)),
            entry(.rail, t, "font_family", "Police des noms de stage",
                  "Nom de la police, ou « system » pour la police du système.", .text, .string("system")),
            entry(.rail, t, "weight", "Graisse des noms de stage",
                  "Épaisseur des caractères.", .choice(weights), .string("semibold")),
            entry(.rail, t, "alignment", "Alignement des noms de stage",
                  "Alignement horizontal du texte.", .choice(alignments), .string("center")),
            entry(.rail, t, "opacity", "Opacité des noms de stage",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(0.72)),
            entry(.rail, t, "offset_x", "Décalage horizontal des noms de stage (points)",
                  "Déplace le texte vers la droite (valeur positive) ou la gauche.", .double(-120...120), .double(0)),
            entry(.rail, t, "offset_y", "Décalage vertical des noms de stage (points)",
                  "Déplace le texte vers le haut (valeur positive) ou le bas.", .double(-120...120), .double(0)),
            entry(.rail, t, "placement", "Place des noms de stage",
                  "Le nom se place au-dessus (above) ou au-dessous (below) de la carte.",
                  .choice(["above", "below"]), .string("below")),
            entry(.rail, t, "z_order", "Superposition des noms de stage",
                  "Le nom passe sous (below) ou sur (above) la carte quand ils se recouvrent.",
                  .choice(["below", "above"]), .string("below")),
            entry(.rail, t, "visibility_seconds", "Durée d'affichage des noms de stage (secondes)",
                  "0 : toujours visibles. Sinon, les noms disparaissent après ce délai.", .double(0...3600), .double(0)),
            entry(.rail, t, "fade_seconds", "Durée du fondu des noms de stage (secondes)",
                  "Temps mis par les noms pour disparaître.", .double(0...10), .double(0.35)),
        ]
    }()
}
