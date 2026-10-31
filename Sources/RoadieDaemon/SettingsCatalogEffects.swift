import Foundation
import RoadieCore

extension SettingsCatalog {
    static let effectsDescriptors: [SettingDescriptor] = {
        let table = "fx.animations"
        var result: [SettingDescriptor] = [
            entry(.effets, "fx", "drop_preview", tr("Destination du glisser", "Drag destination"), tr("Contour : rectangle de destination. Aperçu réel : la vraie fenêtre rejoint la destination et refait sa mise en page. Le pointeur continue de viser. Échap restaure. Indépendant du suivi des voisines. Un titre non admissible, une capture indisponible ou une destination sur un autre écran garde le contour ; aucune nouvelle permission demandée.", "Outline: destination rectangle. Real preview: the actual window moves to the destination and lays out its content. The pointer keeps choosing targets. Escape restores. Independent of live neighbors. An unsupported title, unavailable capture, or destination on another display keeps the outline; no new permission is requested."), .choice(["contour", "real"]), .string("contour")),
            entry(.effets, table, "enabled", tr("Activer les animations", "Enable animations"), tr("Effets de mouvement et fondus. Désactiver garde les mêmes destinations et rend les changements immédiats. Ce choix est indépendant de macOS et ne change pas l’aperçu réel du glisser.", "Motion effects and fades. Turning this off keeps the same destinations and makes changes immediate. This choice is independent of macOS and does not change the real drag preview."), .bool, .bool(false)),
            entry(.effets, table, "profile", tr("Profil", "Profile"), tr("Base commune aux actions. Les valeurs saisies ci-dessous remplacent le profil ; effacez-les pour revenir à l’héritage.", "Shared defaults for all actions. Values entered below override the profile; clear them to inherit again."), .choice(["none", "subtle", "smooth", "expressive"]), .string("subtle")),
        ]
        result += motionDescriptors(table: table, action: false)
        for action in AnimationAction.allCases {
            result += motionDescriptors(table: "\(table).\(action.rawValue)", action: true)
        }
        return result
    }()

    /// Même contrat de saisie pour politique commune et surcharges, sans second catalogue.
    private static func motionDescriptors(table: String, action: Bool) -> [SettingDescriptor] {
        var items: [SettingDescriptor] = []
        if action {
            items.append(entry(.effets, table, "enabled", tr("Animer cette action", "Animate this action"), tr("S’applique seulement lorsque les animations communes sont actives.", "Applies only when shared animations are enabled."), .bool, .bool(true)))
        }
        items += [
            entry(.effets, table, "curve", tr("Courbe", "Curve"), tr("Ressort : mouvement physique, réglé par raideur et amortissement. Les autres courbes utilisent la durée.", "Spring: physical motion, controlled by stiffness and damping. Other curves use duration."), .choice(["inherit", "linear", "ease_out", "ease_in_out", "spring"]), .string("inherit")),
            entry(.effets, table, "duration_ms", tr("Durée (ms)", "Duration (ms)"), tr("0 à 1000 ms pour les courbes temporelles. Vide : hériter. Sans effet sur un ressort. Le rail hérite sinon de sa durée existante.", "0 to 1000 ms for timed curves. Empty: inherit. Does not set a spring's duration. The rail otherwise inherits its existing duration."), .double(0...1000), .unset),
            entry(.effets, table, "intensity", tr("Intensité (0–1)", "Intensity (0–1)"), tr("0 : immédiat. 1 : effet entier. Vide : hériter. La destination finale reste identique.", "0: immediate. 1: full effect. Empty: inherit. The final destination stays the same."), .double(0...1), .unset),
            entry(.effets, table, "stiffness", tr("Raideur du ressort", "Spring stiffness"), tr("50 à 1500. Plus haut : retour plus rapide. Vide : hériter.", "50 to 1500. Higher: faster return. Empty: inherit."), .double(50...1500), .unset),
            entry(.effets, table, "damping", tr("Amortissement du ressort", "Spring damping"), tr("0,3 à 2. Sous 1 : rebond. 1 : retour sans rebond. Au-dessus : retour plus lent. Vide : hériter.", "0.3 to 2. Below 1: bounce. 1: return without bounce. Above 1: slower return. Empty: inherit."), .double(0.3...2), .unset),
        ]
        return items
    }
}
