import AppKit
import RoadieCore

/// Thème de la barre (session 101), sur le modèle des thèmes d'Alfred : couleurs `#RRGGBBAA`, polices,
/// arrondis, flou et largeur. Les thèmes fournis reprennent les valeurs des thèmes livrés avec Alfred 5 ;
/// un fichier `.alfredappearance` exporté d'Alfred se lit tel quel.
struct LauncherTheme: Equatable, Sendable {
    struct Text: Equatable, Sendable {
        var size: Double
        var color: String
        var colorSelected: String
        var font: String
    }

    /// Mode de flou d'Alfred : aucun, matière claire, matière sombre.
    enum Effect: Int, Equatable, Sendable {
        case none = 0, light, dark
    }

    var id: String
    var name: String
    var windowColor: String
    var borderColor: String
    /// Épaisseur du contour ; 0 : un filet de 0,5 point.
    var borderWidth: Double
    var roundness: Double
    /// Rayon du flou derrière la barre ; 0 sans flou, sauf `effect`.
    var blur: Double
    var effect: Effect
    var width: Double
    var searchBackground: String
    var searchRoundness: Double
    var searchText: Text
    /// `accent` : couleur d'accent de macOS.
    var selectedBackground: String
    var rowRoundness: Double
    var title: Text
    var subtitle: Text
    var shortcut: Text
    /// Faux pour `roadie` : les tailles et polices viennent des réglages `search_text_font_size`,
    /// `command_text_font_size` et des familles ; vrai : celles du thème.
    var ownsSizes = true

    /// Titres de section et compteur : la couleur du sous-titre.
    var headerColor: String { subtitle.color }

    /// Matière du flou derrière la barre ; nil sans flou.
    var blurAppearance: NSAppearance.Name? {
        switch effect {
        case .light: return .aqua
        case .dark: return .darkAqua
        case .none:
            guard blur > 0 else { return nil }
            return Self.isLight(windowColor) ? .aqua : .darkAqua
        }
    }

    /// O(1). Couleur claire si sa luminance dépasse 0,5.
    static func isLight(_ hex: String) -> Bool {
        guard let color = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return false }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent > 0.5
    }

    static func color(_ hex: String) -> NSColor {
        hex == "accent" ? NSColor.controlAccentColor.withAlphaComponent(0.9) : NSColor(hex: hex) ?? .white
    }

    /// Hauteur de la barre de saisie : formule historique pour `roadie`, celle d'Alfred (texte et marges)
    /// pour les autres thèmes. O(1).
    func barHeight(fontSize: CGFloat) -> CGFloat {
        let size = min(48, max(8, fontSize))
        return ownsSizes ? max(40, (size * 1.35 + 18).rounded()) : 40 * size / 15
    }
}

extension LauncherTheme {
    /// Aspect historique de Roadie : surface sombre presque opaque, sélection en couleur d'accent.
    static let roadie = LauncherTheme(
        id: "roadie", name: "Roadie", windowColor: "#1A1A1AF5", borderColor: "#FFFFFF2E", borderWidth: 0,
        roundness: 12, blur: 0, effect: .none, width: 640, searchBackground: "#00000000", searchRoundness: 8,
        searchText: Text(size: 15, color: "#F0F0F0FF", colorSelected: "#FFFFFFFF", font: "system"),
        selectedBackground: "accent", rowRoundness: 9,
        title: Text(size: 13, color: "#F7F7F7FF", colorSelected: "#FFFFFFFF", font: "system"),
        subtitle: Text(size: 8, color: "#949494FF", colorSelected: "#FFFFFFC7", font: "system"),
        shortcut: Text(size: 8, color: "#808080FF", colorSelected: "#FFFFFFBF", font: "system"),
        ownsSizes: false)

    private static func alfred(_ id: String, _ name: String, window: String, blur: Double, effect: Effect = .none,
                               roundness: Double = 3, width: Double = 559, borderWidth: Double = 0, border: String = "#0000007F",
                               search: String, searchRoundness: Double = 0, searchText: Text, selected: String,
                               rowRoundness: Double = 0, title: Text, subtitle: Text, shortcut: Text) -> LauncherTheme {
        LauncherTheme(id: id, name: name, windowColor: window, borderColor: border, borderWidth: borderWidth, roundness: roundness,
                      blur: blur, effect: effect, width: width, searchBackground: search, searchRoundness: searchRoundness,
                      searchText: searchText, selectedBackground: selected, rowRoundness: rowRoundness,
                      title: title, subtitle: subtitle, shortcut: shortcut)
    }

    private static func text(_ size: Double, _ color: String, _ selected: String, _ font: String = "System") -> Text {
        Text(size: size, color: color, colorSelected: selected, font: font)
    }

    /// Thèmes fournis, dans l'ordre de la liste d'Alfred. Valeurs relevées dans les fichiers
    /// `.alfredappearance` d'Alfred 5.
    static let builtIn: [LauncherTheme] = [
        roadie,
        alfred("alfred", "Alfred", window: "#FFFFFFDB", blur: 15, search: "#0000001A",
               searchText: text(34, "#000000FF", "#FFFFFFFF", "System Light"), selected: "#480069E4",
               title: text(18, "#000000E5", "#FFFFFFFF"), subtitle: text(12, "#00000065", "#FFFFFFC4"),
               shortcut: text(16, "#480069FF", "#FFFFFFFF")),
        alfred("alfred-dark", "Alfred Dark", window: "#000000C6", blur: 15, search: "#0000003E",
               searchText: text(34, "#FFFFFFFF", "#FFFFFFFF", "System Light"), selected: "#358188FF",
               title: text(18, "#FFFFFFCB", "#FFFFFFFF"), subtitle: text(12, "#FFFFFF7E", "#FFFFFFCB"),
               shortcut: text(16, "#FFFFFF7E", "#FFFFFFFF")),
        alfred("alfred-modern", "Alfred Modern", window: "#F8F8F86B", blur: 0, effect: .light, roundness: 15, width: 700,
               search: "#00000019", searchRoundness: 8, searchText: text(36, "#000000FF", "#FFFFFFFF", "System Light"),
               selected: "#480069E4", rowRoundness: 8, title: text(18, "#000000E4", "#FFFFFFFF"),
               subtitle: text(12, "#00000098", "#FFFFFFCB"), shortcut: text(16, "#480069E4", "#FFFFFFFF")),
        alfred("alfred-modern-dark", "Alfred Modern Dark", window: "#00000066", blur: 0, effect: .dark, roundness: 15, width: 700,
               search: "#0000003E", searchRoundness: 8, searchText: text(36, "#FFFFFFFF", "#FFFFFFFF", "System Light"),
               selected: "#358188FF", rowRoundness: 8, title: text(18, "#FFFFFFCB", "#FFFFFFFF"),
               subtitle: text(12, "#FFFFFF7E", "#FFFFFFCB"), shortcut: text(16, "#FFFFFF7E", "#FFFFFFFF")),
        alfred("alfred-macos", "Alfred macOS", window: "#FFFFFFE5", blur: 10, search: "#FFFFFF00",
               searchText: text(34, "#000000FF", "#FFFFFFFF", "System Light"), selected: "#016BDEFF",
               title: text(18, "#000000E5", "#FFFFFFFF"), subtitle: text(12, "#00000065", "#FFFFFFC4"),
               shortcut: text(16, "#480069FF", "#FFFFFFFF")),
        alfred("alfred-macos-dark", "Alfred macOS Dark", window: "#000000D8", blur: 15, search: "#FFFFFF00",
               searchText: text(34, "#FFFFFFFF", "#FFFFFFFF", "System Light"), selected: "#016BDEFF",
               title: text(18, "#FFFFFFD8", "#FFFFFFFF"), subtitle: text(12, "#FFFFFF66", "#FFFFFFCC"),
               shortcut: text(16, "#FEFFFF66", "#FFFFFFFF")),
        alfred("frosty-teal", "Frosty Teal", window: "#106480B4", blur: 20, width: 573, border: "#000000FF", search: "#FFFFFF00",
               searchText: text(40, "#FFFFFFFF", "#FFFFFFFF", "System Light"), selected: "#0000001F",
               title: text(21, "#FFFFFFAD", "#FFFFFFFF"), subtitle: text(12, "#FFFFFF6F", "#FFFFFFA7"),
               shortcut: text(15, "#FFFFFF7E", "#FFFFFF9E")),
        alfred("high-contrast", "High Contrast Light", window: "#FFFFFFFF", blur: 0, roundness: 0, borderWidth: 8, search: "#CBCBCBF3",
               searchText: text(38, "#000000FF", "#000000FF", "Avenir"), selected: "#000000DA",
               title: text(24, "#000000E5", "#FFFFFFFF", "Avenir"), subtitle: text(14, "#000000B6", "#FFFFFFD9", "Avenir"),
               shortcut: text(17, "#000000FF", "#FFFFFFFF", "Avenir")),
        alfred("large-avenir", "Large Avenir", window: "#272727F1", blur: 15, roundness: 5, width: 683, border: "#0000003F",
               search: "#00000000", searchText: text(46, "#FFFFFFFF", "#FFFFFFFF", "Avenir"), selected: "#1D6488FF",
               title: text(26, "#FFFFFFDB", "#FFFFFFE8", "Avenir"), subtitle: text(14, "#FFFFFF7F", "#FFFFFFCB", "Avenir"),
               shortcut: text(20, "#FFFFFF59", "#FFFFFFFF", "Avenir")),
    ]
}

/// Lecture d'un thème exporté d'Alfred (`.alfredappearance`, ou `theme.json` des préférences d'Alfred).
/// Les clés absentes prennent les valeurs du thème « Alfred ».
enum AlfredAppearanceReader {
    static func theme(from data: Data, id: String) -> LauncherTheme? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let theme = root["alfredtheme"] as? [String: Any] else { return nil }
        let base = LauncherTheme.builtIn[1]
        let window = theme["window"] as? [String: Any] ?? [:]
        let search = theme["search"] as? [String: Any] ?? [:]
        let result = theme["result"] as? [String: Any] ?? [:]
        func string(_ table: [String: Any], _ key: String, _ fallback: String) -> String {
            (table[key] as? String).flatMap { NSColor(hex: $0) == nil ? nil : $0 } ?? fallback
        }
        func number(_ table: [String: Any], _ key: String, _ fallback: Double) -> Double {
            (table[key] as? NSNumber)?.doubleValue ?? fallback
        }
        func text(_ table: [String: Any], _ key: String, _ fallback: LauncherTheme.Text) -> LauncherTheme.Text {
            let value = table[key] as? [String: Any] ?? [:]
            return LauncherTheme.Text(size: number(value, "size", fallback.size), color: string(value, "color", fallback.color),
                                      colorSelected: string(value, "colorSelected", fallback.colorSelected),
                                      font: value["font"] as? String ?? fallback.font)
        }
        return LauncherTheme(
            id: id, name: theme["name"] as? String ?? id,
            windowColor: string(window, "color", base.windowColor), borderColor: string(window, "borderColor", base.borderColor),
            borderWidth: number(window, "borderPadding", 0), roundness: max(0, number(window, "roundness", base.roundness)),
            blur: number(window, "blur", 0),
            effect: LauncherTheme.Effect(rawValue: (theme["visualEffectMode"] as? NSNumber)?.intValue ?? 0) ?? .none,
            width: min(1200, max(320, number(window, "width", base.width))),
            searchBackground: string(search, "background", base.searchBackground), searchRoundness: number(search, "roundness", 0),
            searchText: text(search, "text", base.searchText),
            selectedBackground: string(result, "backgroundSelected", base.selectedBackground),
            rowRoundness: number(result, "roundness", 0),
            title: text(result, "text", base.title), subtitle: text(result, "subtext", base.subtitle),
            shortcut: text(result, "shortcut", base.shortcut))
    }
}

/// Thèmes disponibles : fournis, puis fichiers importés de `~/.config/roadies/themes` et thèmes
/// personnels d'Alfred. Lecture à l'ouverture de la barre : quelques fichiers, O(f).
enum LauncherThemeCatalog {
    static var userDirectory: URL {
        URL(fileURLWithPath: NSString(string: "~/.config/roadies/themes").expandingTildeInPath, isDirectory: true)
    }

    static var alfredDirectory: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Alfred/Alfred.alfredpreferences/themes").expandingTildeInPath,
            isDirectory: true)
    }

    /// Identifiant d'un fichier importé : son nom sans extension, en minuscules, espaces en tirets.
    static func identifier(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { $0 == " " || $0 == "_" }).joined(separator: "-")
    }

    /// Thèmes importés, triés par nom. O(f).
    static func imported(user: URL = userDirectory, alfred: URL = alfredDirectory) -> [LauncherTheme] {
        let files = FileManager.default
        var found: [LauncherTheme] = []
        for url in (try? files.contentsOfDirectory(at: user, includingPropertiesForKeys: nil)) ?? []
        where ["alfredappearance", "json"].contains(url.pathExtension.lowercased()) {
            if let data = try? Data(contentsOf: url),
               let theme = AlfredAppearanceReader.theme(from: data, id: identifier(url.deletingPathExtension().lastPathComponent)) {
                found.append(theme)
            }
        }
        // Préférences d'Alfred : un dossier par thème personnel, `theme.json` dedans ; l'identifiant suit le nom.
        for folder in (try? files.contentsOfDirectory(at: alfred, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("theme.json")),
                  let probe = AlfredAppearanceReader.theme(from: data, id: folder.lastPathComponent) else { continue }
            let id = identifier(probe.name)
            guard !found.contains(where: { $0.id == id }) else { continue }
            found.append(AlfredAppearanceReader.theme(from: data, id: id) ?? probe)
        }
        let builtIDs = Set(LauncherTheme.builtIn.map(\.id))
        return found.filter { !builtIDs.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func all() -> [LauncherTheme] { LauncherTheme.builtIn + imported() }

    /// Thème de `theme`, ou de `theme_dark` en mode sombre ; un nom inconnu revient à `roadie`. O(f).
    static func resolve(_ config: TargetModeConfig, dark: Bool, available: () -> [LauncherTheme] = all) -> LauncherTheme {
        let id = dark && !config.themeDark.isEmpty ? config.themeDark : config.theme
        if let theme = LauncherTheme.builtIn.first(where: { $0.id == id }) { return theme }
        return available().first { $0.id == id } ?? .roadie
    }

    /// Mode sombre de macOS, lu sur l'apparence de l'application.
    @MainActor static var systemIsDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
