import Foundation
import RoadieCore

extension SettingsCatalog {
    static let overviewDescriptors: [SettingDescriptor] = [
        entry(.overview, "overview", "enabled", "Activer la vue d’ensemble", "Carte globale des écrans, bureaux et stages Roadie, accessible par la CLI, BetterTouchTool ou un raccourci facultatif.", .bool, .bool(true)),
        entry(.overview, "overview", "presentation", "Disposition", "Archipel : écrans en colonnes et bureaux en îlots. Baies : écrans en bandes et bureaux côte à côte. Les traits obliques séparent les écrans.", .choice(["archipelago", "bays"]), .string("archipelago")),
        entry(.overview, "overview", "loupe", "Loupe au survol", "Agrandit les cartes du bureau sous la souris après une courte stabilisation. Consulter ne change pas le bureau actif. Désactivez pour garder la même taille partout.", .bool, .bool(true)),
        entry(.overview, "overview", "magnification", "Grossissement de la loupe (%)", "Taille des cartes du bureau survolé, par rapport aux autres. Les autres bureaux se resserrent si la place manque et restent visibles. Aucune fenêtre n’est redimensionnée.", .double(100...250), .double(150)),
        entry(.overview, "overview", "background_blur", "Flou du fond d’écran (%)", "0 % : fond d’écran net. 100 % : très flou. L’aperçu montre votre fond d’écran avec ce réglage. Le flou masque les icônes du bureau sans gêner la lecture des cartes.", .double(0...100), .double(20)),
        entry(.overview, "overview", "hotkey", "Raccourci interne (facultatif)", "Enregistrez directement une combinaison. Laissez vide pour BetterTouchTool, Karabiner ou un autre outil : roadie overview toggle. Ce réglage ne modifie pas Cmd+Tab.", .text, .string("")),
    ]
}
