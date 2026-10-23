import Foundation
import RoadieCore

extension SettingsCatalog {
    static let switcherDescriptors: [SettingDescriptor] = [
        entry(.selecteur, "switcher", "enabled", "Activer le sélecteur",
              "Active le sélecteur, accessible par les commandes CLI depuis BetterTouchTool ou Karabiner. Les raccourcis internes sont facultatifs.",
              .bool, .bool(true)),
        entry(.selecteur, "switcher", "style", "Affichage des fenêtres",
              "Affichage des fenêtres dans le sélecteur : vignettes, icônes ou liste compacte.",
              .choice(["thumbnails", "icons", "list"]), .string("thumbnails")),
        entry(.selecteur, "switcher", "presentation", "Organisation",
              "Choisit la disposition et le regroupement par bureau et stage Roadie. La grille classique conserve l'affichage précédent. Chaque profil peut utiliser sa propre organisation, sans changer les raccourcis ni l'action au relâchement.",
              .choice(WindowSwitcherPresentation.allCases.map(\.rawValue)), .string("classic")),
        entry(.selecteur, "switcher", "auto_size", "Taille automatique",
              "Calcule la taille des vignettes. Désactivez ce réglage pour utiliser la largeur ci-dessous.",
              .bool, .bool(true)),
        entry(.selecteur, "switcher", "thumbnail_width", "Largeur des vignettes (points)",
              "Largeur de chaque vignette quand la taille automatique est désactivée.",
              .double(120...400), .double(220)),
        entry(.selecteur, "switcher", "font_size", "Taille du texte (points)",
              "Taille du texte affiché dans le sélecteur.",
              .double(10...32), .double(16)),
        entry(.selecteur, "switcher", "font_family", "Police du texte",
              "Nom de la police, ou « system » pour la police du système.",
              .text, .string("system")),
        entry(.selecteur, "switcher", "preview", "Aperçu agrandi",
              "Affiche un aperçu agrandi de la fenêtre sélectionnée, sans l'activer.",
              .bool, .bool(true)),
        readOnlyEntry(.selecteur, "switcher", "excluded_bundles", "Applications exclues",
                      "Identifiants d'applications (bundle ID) que le sélecteur n'affiche jamais. Exemple : com.apple.finder."),
        readOnlyEntry(.selecteur, "switcher", "shortcuts", "Profils de raccourcis",
                      "Jusqu'à neuf profils. Chaque profil a sa touche, ses fenêtres, son tri et son action au relâchement. Une touche déjà prise par AltTab ou par un autre outil peut ne pas réagir."),
    ]
}
