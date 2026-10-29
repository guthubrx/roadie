import Foundation
import RoadieAX
import RoadieCore

/// Liste « Fenêtres toujours flottantes » (`exclusions.floating_windows`, session 125), partagée par le
/// menu Fenêtre et Paramètres > Règles : l'utilisateur ajoute, modifie ou retire ses propres lignes.
struct FloatingWindowSettings {
    static let id = "exclusions.floating_windows"
    var settings = SettingsService()

    /// Lignes de la liste, dans l'ordre du fichier. O(n).
    func rows() -> [CollectionRow] {
        guard let descriptor = SettingsCatalog.find(id: Self.id),
              case .success(.rows(let rows)) = settings.collection(of: descriptor) else { return [] }
        return rows
    }

    /// Ligne de la liste lue comme réglage, nil si incomplète. O(1).
    static func entry(_ row: CollectionRow) -> FloatingWindowConfig? {
        guard case .string(let app)? = row.fields["app"], case .string(let title)? = row.fields["title"] else { return nil }
        return FloatingWindowConfig(app: app, title: title)
    }

    /// Vrai si cette ligne vise la fenêtre, avec la même règle que le tuilage. O(t).
    static func matches(_ row: CollectionRow, window: WindowSnapshot) -> Bool {
        guard let entry = entry(row), let rule = FloatingWindowTitles.rules([entry]).first else { return false }
        return WindowRuleMatcher.matches(rule: rule, window: window, context: WindowRuleMatchContext(role: window.role, subrole: window.subrole))
    }

    /// Titre de la liste qui vise cette fenêtre, ou nil. O(n).
    func listedTitle(for window: WindowSnapshot) -> String? {
        rows().first { Self.matches($0, window: window) }.flatMap(Self.entry)?.title
    }

    /// Ajoute la fenêtre à la liste (titre généralisé : « 1 Reminder » devient « # Reminder »), ou retire
    /// toutes les lignes qui la visent. O(n).
    func setFloating(_ floating: Bool, window: WindowSnapshot) -> WindowRuleAffinityResult {
        var rows = rows()
        if floating {
            guard let title = FloatingWindowTitles.text(fromTitle: window.title) else {
                return WindowRuleAffinityResult(message: tr("titre vide : aucune ligne ajoutee", "empty title: no row added"), changed: false, path: settings.configPath)
            }
            guard !rows.contains(where: { Self.matches($0, window: window) }) else {
                return WindowRuleAffinityResult(message: tr("deja dans la liste", "already in the list"), changed: false, path: settings.configPath)
            }
            rows.append(CollectionRow(fields: ["app": .string(window.appName), "title": .string(title)]))
        } else {
            let kept = rows.filter { !Self.matches($0, window: window) }
            guard kept.count != rows.count else {
                return WindowRuleAffinityResult(message: tr("aucune ligne pour cette fenetre", "no row for this window"), changed: false, path: settings.configPath)
            }
            rows = kept
        }
        switch settings.setCollection(Self.id, .rows(rows)) {
        case .applied:
            return WindowRuleAffinityResult(message: floating ? tr("fenetres flottantes: \(window.appName)", "floating windows: \(window.appName)") : tr("ligne retiree: \(window.appName)", "row removed: \(window.appName)"),
                                            changed: true, path: settings.configPath)
        case .rejected(let reason):
            return WindowRuleAffinityResult(message: reason, changed: false, path: settings.configPath)
        }
    }
}
