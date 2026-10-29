import Foundation
import RoadieCore

/// Grille Apps de la barre (session 131), comme le Launchpad d'Alfred UI annoncé pour Alfred 6 (« chercher, ranger
/// et lancer ses applications ») et l'application Apps de macOS 26 : toutes les applications, par catégorie,
/// épinglées en tête, filtrées par la saisie après `apps`. Logique pure.
enum LauncherAppsGrid {
    static let keywords = ["apps", "launchpad"]

    /// Filtre tapé après `apps ` ; nil si la saisie n'ouvre pas la grille. O(t).
    static func query(_ text: String) -> String? {
        let lower = text.lowercased()
        for keyword in keywords where lower == keyword || lower.hasPrefix(keyword + " ") {
            return String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Nom d'une catégorie d'App Store (`public.app-category.*`), en français et en anglais ; « Autres » sinon. O(1).
    static func categoryName(_ identifier: String) -> String {
        let names: [String: (String, String)] = [
            "business": ("Économie et entreprise", "Business"), "developer-tools": ("Outils de développement", "Developer tools"),
            "education": ("Éducation", "Education"), "entertainment": ("Divertissement", "Entertainment"),
            "finance": ("Finance", "Finance"), "games": ("Jeux", "Games"), "graphics-design": ("Graphisme et design", "Graphics & design"),
            "healthcare-fitness": ("Santé et forme", "Health & fitness"), "lifestyle": ("Style de vie", "Lifestyle"),
            "medical": ("Médecine", "Medical"), "music": ("Musique", "Music"), "news": ("Actualités", "News"),
            "photography": ("Photo", "Photography"), "productivity": ("Productivité", "Productivity"),
            "reference": ("Références", "Reference"), "social-networking": ("Réseaux sociaux", "Social networking"),
            "sports": ("Sports", "Sports"), "travel": ("Voyages", "Travel"), "utilities": ("Utilitaires", "Utilities"),
            "video": ("Vidéo", "Video"), "weather": ("Météo", "Weather"),
        ]
        let key = identifier.replacingOccurrences(of: "public.app-category.", with: "")
        if key.hasSuffix("-games") { return tr("Jeux", "Games") }
        guard let pair = names[key] else { return tr("Autres", "Other") }
        return tr(pair.0, pair.1)
    }

    /// Sections : « Épinglées » dans l'ordre d'épinglage, puis chaque catégorie par nom, « Autres » en dernier ;
    /// applications par nom ; une application épinglée n'apparaît qu'une fois. O(a log a + a × t).
    static func sections(apps: [LauncherApp], query: String, pins: [String]) -> [(title: String, apps: [LauncherApp])] {
        let shown = apps.filter { app in
            query.isEmpty || LauncherMatch.score(query, in: app.name) != nil || app.alternateNames.contains { LauncherMatch.score(query, in: $0) != nil }
        }
        let byID = Dictionary(shown.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = pins.compactMap { byID[$0] }
        let pinnedIDs = Set(pinned.map(\.bundleID))
        let other = tr("Autres", "Other")
        let groups = Dictionary(grouping: shown.filter { !pinnedIDs.contains($0.bundleID) }) { categoryName($0.category) }
        let titles = groups.keys.sorted { ($0 == other ? 1 : 0, $0.localizedLowercase) < ($1 == other ? 1 : 0, $1.localizedLowercase) }
        var result: [(title: String, apps: [LauncherApp])] = pinned.isEmpty ? [] : [(tr("Épinglées", "Pinned"), pinned)]
        for title in titles {
            result.append((title, groups[title, default: []].sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }))
        }
        return result
    }
}

/// Applications épinglées en tête de la grille Apps (session 131), dans `~/.roadies/apps-pins.json`.
struct LauncherAppsPins: Sendable {
    let path: String

    init(path: String = NSString(string: TestEnvironment.launcherFile("apps-pins.json")).expandingTildeInPath) {
        self.path = path
    }

    func load() -> [String] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Épingle à la fin, ou retire si déjà épinglée ; écriture atomique. O(p).
    @discardableResult
    func toggle(_ bundleID: String) -> Bool {
        var pins = load()
        let pinned: Bool
        if let index = pins.firstIndex(of: bundleID) { pins.remove(at: index); pinned = false } else { pins.append(bundleID); pinned = true }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? JSONEncoder().encode(pins).write(to: URL(fileURLWithPath: path), options: .atomic)
        return pinned
    }
}
