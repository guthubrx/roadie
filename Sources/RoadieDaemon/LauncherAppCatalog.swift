import Foundation

/// Une application installée, telle que le lanceur la propose (SPEC-073 F1).
struct LauncherApp: Equatable, Sendable {
    let bundleID: String
    let path: String
    /// Nom affiché par le Finder, dans la langue de l'utilisateur (`Calculatrice`).
    let name: String
    /// Autres noms cherchés : nom de fichier, noms déclarés dans `Info.plist` (`Calculator`).
    let alternateNames: [String]

    var rankingKey: String { "app:\(bundleID)" }
}

/// Index des applications des dossiers usuels, construit hors du fil principal et gardé en mémoire.
/// Un niveau de sous-dossier est parcouru (`/Applications/Adobe Photoshop 2026/…`), sans aller plus loin.
/// Une seule copie par identifiant : la première trouvée dans l'ordre des dossiers.
final class LauncherAppCatalog: @unchecked Sendable {
    static let shared = LauncherAppCatalog()

    static let defaultRoots: [String] = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        // Safari et les applications livrées par cryptex ne vivent qu'ici.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        "~/Applications",
        "/System/Library/CoreServices/Finder.app",
        // Utilitaires système (Échange de fichiers Bluetooth…) et outils de Xcode (SPEC-077).
        "/System/Library/CoreServices/Applications",
        "/Applications/Xcode.app/Contents/Applications",
    ]

    private let lock = NSLock()
    private var apps: [LauncherApp] = []
    private var refreshing = false
    /// Dossiers ajoutés par `app_search_paths` (session 105), parcourus après ceux par défaut.
    private var extraRoots: [String] = []

    /// Change les dossiers ajoutés ; vrai s'ils ont changé (l'index sera refait au prochain parcours).
    @discardableResult
    func setExtraRoots(_ roots: [String]) -> Bool {
        lock.withLock {
            guard extraRoots != roots else { return false }
            extraRoots = roots
            return true
        }
    }

    /// Dernier index connu ; vide avant le premier parcours.
    var current: [LauncherApp] { lock.withLock { apps } }

    /// Reconstruit l'index en arrière-plan, puis appelle `done` sur le fil principal. Un parcours déjà
    /// en cours n'est pas doublé : `done` reçoit alors l'index courant.
    func refresh(done: (@MainActor @Sendable ([LauncherApp]) -> Void)? = nil) {
        let start = lock.withLock { () -> Bool in
            guard !refreshing else { return false }
            refreshing = true
            return true
        }
        guard start else {
            let snapshot = current
            if let done { DispatchQueue.main.async { MainActor.assumeIsolated { done(snapshot) } } }
            return
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            let scanned = Self.scan(roots: Self.defaultRoots + lock.withLock { extraRoots })
            lock.withLock { apps = scanned; refreshing = false }
            if let done { DispatchQueue.main.async { MainActor.assumeIsolated { done(scanned) } } }
        }
    }

    /// Parcours des dossiers. O(f), f = entrées des dossiers et de leurs sous-dossiers directs.
    static func scan(roots: [String], fileManager: FileManager = .default) -> [LauncherApp] {
        var seen = Set<String>()
        var result: [LauncherApp] = []
        func add(_ path: String) {
            guard let app = app(at: path, fileManager: fileManager), seen.insert(app.bundleID).inserted else { return }
            result.append(app)
        }
        for root in roots.map({ NSString(string: $0).expandingTildeInPath }) {
            if root.hasSuffix(".app") { add(root); continue }
            guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(name)
                if name.hasSuffix(".app") { add(path); continue }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                      let inner = try? fileManager.contentsOfDirectory(atPath: path) else { continue }
                for child in inner.sorted() where child.hasSuffix(".app") {
                    add((path as NSString).appendingPathComponent(child))
                }
            }
        }
        return result
    }

    /// Lecture d'un paquet : identifiant obligatoire ; applications d'arrière-plan exclues. O(1).
    static func app(at path: String, fileManager: FileManager = .default) -> LauncherApp? {
        guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        if (info["LSBackgroundOnly"] as? Bool) == true { return nil }
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let display = fileManager.displayName(atPath: path)
        let name = (display as NSString).pathExtension == "app" ? (display as NSString).deletingPathExtension : display
        var alternates: [String] = []
        for candidate in [fileName, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String].compactMap({ $0 })
        where candidate != name && !alternates.contains(candidate) {
            alternates.append(candidate)
        }
        return LauncherApp(bundleID: bundleID, path: path, name: name, alternateNames: alternates)
    }
}
