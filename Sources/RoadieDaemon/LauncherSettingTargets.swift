import Foundation

/// Réglages trouvés par la barre (session 115), comme les « Essentiels : Réglages Système » d'Alfred : pages et
/// réglages des Paramètres de Roadie, panneaux des Réglages Système. Ce sont des commandes de la section
/// « Réglages », exécutées par `LauncherSystemCommand.run()` selon le préfixe de leur identifiant.
enum LauncherSettingTargets {
    static let roadieCategoryPrefix = "roadie-category:"
    static let roadieSettingPrefix = "roadie-setting:"
    static let panePrefix = "pane:"

    /// Catégories (« Rail ») puis réglages (« Thème de la barre ») des Paramètres de Roadie. O(c + r).
    static func roadie(_ descriptors: [SettingDescriptor] = SettingsCatalog.all) -> [LauncherSystemCommand] {
        let categories = SettingCategory.allCases.map { category in
            LauncherSystemCommand(id: roadieCategoryPrefix + category.rawValue, title: category.label,
                                  keywords: ["paramètres", "settings", "roadie"], symbol: category.symbolName, confirms: false,
                                  detail: "Paramètres de Roadie")
        }
        let settings = descriptors.map { descriptor in
            LauncherSystemCommand(id: roadieSettingPrefix + descriptor.id, title: descriptor.label, keywords: [descriptor.key],
                                  symbol: descriptor.category.symbolName, confirms: false,
                                  detail: "Paramètres de Roadie › \(descriptor.category.label)")
        }
        return categories + settings
    }

    /// Panneaux des Réglages Système : extensions `com.apple.Settings.extension.ui` de macOS, nommées dans la
    /// langue de l'utilisateur par leur `InfoPlist.loctable` ; le nom anglais devient un mot-clé. O(e).
    static func systemPanes(root: URL = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions"),
                            languages: [String] = Locale.preferredLanguages) -> [LauncherSystemCommand] {
        let files = FileManager.default
        var panes: [LauncherSystemCommand] = []
        for url in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "appex" {
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  (info["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  let id = info["CFBundleIdentifier"] as? String else { continue }
            let table = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")) as? [String: Any] ?? [:]
            guard let name = localizedName(table, languages: languages) ?? fallbackNames[id]?.local(languages) else { continue }
            let english = localizedName(table, languages: ["en"]) ?? fallbackNames[id]?.en
            panes.append(LauncherSystemCommand(id: panePrefix + id, title: name, keywords: [english].compactMap { $0 },
                                               symbol: "gearshape", confirms: false, detail: "Réglages Système"))
        }
        return panes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Nom affiché dans la première langue disponible (`fr-FR` → `fr_FR`, puis `fr`). O(l).
    static func localizedName(_ table: [String: Any], languages: [String]) -> String? {
        for language in languages {
            let code = language.replacingOccurrences(of: "-", with: "_")
            for candidate in [code, String(code.prefix { $0 != "_" })] {
                if let name = (table[candidate] as? [String: Any])?["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
            }
        }
        return nil
    }

    /// Panneaux sans nom traduit dans leur table (relevé macOS 26 : Batterie).
    private struct Names { let fr: String; let en: String
        func local(_ languages: [String]) -> String { languages.first?.hasPrefix("fr") == true ? fr : en }
    }
    private static let fallbackNames = ["com.apple.Battery-Settings.extension": Names(fr: "Batterie", en: "Battery")]

    /// Lien qui ouvre un panneau des Réglages Système.
    static func paneURL(_ id: String) -> URL? { URL(string: "x-apple.systempreferences:\(id)") }
}

/// Panneaux lus une fois par lancement de Roadie : 51 panneaux parmi 228 extensions, 20 ms sur ce poste.
final class LauncherSettingTargetsCache: @unchecked Sendable {
    static let shared = LauncherSettingTargetsCache()
    private let lock = NSLock()
    private var panes: [LauncherSystemCommand]?

    func systemPanes() -> [LauncherSystemCommand] {
        lock.lock()
        defer { lock.unlock() }
        if let panes { return panes }
        let found = LauncherSettingTargets.systemPanes()
        panes = found
        return found
    }
}
