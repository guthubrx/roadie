import AppKit
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 124 : captures de la documentation, dessinées par le vrai rendu de Roadie avec des données
/// d'exemple. Aucune fenêtre, aucun fichier, aucun fond d'écran de l'utilisateur n'est lu : les icônes
/// viennent des applications d'Apple, les vignettes et les fichiers sont inventés.
/// Chaque image existe en anglais (dossier racine, documentation par défaut) et en français (`fr/`), session 126.
/// Ne fait rien sans `ROADIE_DOC_SHOTS_DIR` :
/// `ROADIE_DOC_SHOTS_DIR=docs/assets/screenshots scripts/test --no-parallel --filter Spec124`.
@MainActor
@Suite(.serialized)
struct Spec124DocScreenshots {
    private let output = ProcessInfo.processInfo.environment["ROADIE_DOC_SHOTS_DIR"].map { URL(fileURLWithPath: $0) }

    // MARK: Données d'exemple

    private enum App {
        static let notes = "/System/Applications/Notes.app"
        static let safari = "/Applications/Safari.app"
        static let calendar = "/System/Applications/Calendar.app"
        static let mail = "/System/Applications/Mail.app"
        static let preview = "/System/Applications/Preview.app"
        static let terminal = "/System/Applications/Utilities/Terminal.app"
        static let finder = "/System/Library/CoreServices/Finder.app"
        static let music = "/System/Applications/Music.app"
        static let reminders = "/System/Applications/Reminders.app"
        static let freeform = "/System/Applications/Freeform.app"
        static let maps = "/System/Applications/Maps.app"
    }

    /// Fichiers vides créés pour avoir l'icône de leur type ; le chemin montré est inventé.
    private func sampleFile(_ name: String, folder: Bool = false) -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-doc-shots-files")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        if folder { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        else if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: Data()) }
        return url.path
    }

    private func header(_ title: String) -> SlashSuggestion { SlashSuggestion(text: title, kind: .header) }

    private func row(_ text: String, _ detail: String, _ icon: SlashSuggestion.Icon, letter: String = "") -> SlashSuggestion {
        var line = SlashSuggestion(text: text, detail: detail, kind: .result, icon: icon)
        line.letter = letter
        return line
    }

    /// ⌘1 à ⌘9 sur les lignes choisissables, comme `TargetOverlayPresenter.show`.
    private func numbered(_ rows: [SlashSuggestion]) -> [SlashSuggestion] {
        var rank = 0
        return rows.map { row in
            guard row.kind != .header, rank < 9 else { return row }
            rank += 1
            var row = row
            row.shortcut = "⌘\(rank)"
            return row
        }
    }

    /// `view` : chip de la présentation (« ☰ Liste »), là où la vraie barre l'affiche (session 099).
    private func bar(_ query: String, _ rows: [SlashSuggestion], selected: Int?, properties: String? = nil,
                     view: LauncherViewMode? = nil) -> TargetSearchBar {
        var state = TargetSearchBar(query: query, matchCount: rows.filter { $0.kind != .header }.count, properties: properties,
                                    isLoading: false, suggestions: numbered(rows), selectedSuggestion: selected, richRows: true)
        state.viewChip = view.map { "\($0.symbol) \($0.title)" }
        return state
    }

    /// Image d'exemple d'un émoji, dessinée par la police du système, comme les icônes d'un workflow d'émojis.
    private func emojiImage(_ emoji: String) -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-doc-shots-emoji")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")).png")
        let size = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return url.path }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 100)])
        let bounds = text.size()
        text.draw(at: CGPoint(x: (CGFloat(size) - bounds.width) / 2, y: (CGFloat(size) - bounds.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        return url.path
    }

    /// Images de chaque langue : anglais d'abord, la langue d'origine rétablie ensuite.
    private func eachLanguage(_ body: () async throws -> Void) async throws {
        let saved = UILanguage.current
        defer { UILanguage.current = saved }
        for language in [UILanguage.en, .fr] {
            UILanguage.current = language
            try await body()
        }
    }

    private var personal: String { tr("Perso", "Personal") }

    private func searchScene() -> TargetSearchBar {
        bar("note", [
            header(tr("Applications", "Applications")),
            row("Notes", tr("Ouverte", "Open") + " · \(personal)", .file(App.notes)),
            header(tr("Fenêtres", "Windows")),
            row("Notes", tr("Idées de voyage", "Travel ideas"), .file(App.notes), letter: "⇧K"),
            header(tr("Documents et onglets", "Documents and tabs")),
            row(tr("Notes de version 2.4.pdf", "Release notes 2.4.pdf"), tr("Aperçu · Documentation", "Preview · Documentation"), .file(App.preview)),
            header(tr("Fichiers", "Files")),
            row(tr("Notes de réunion.md", "Meeting notes.md"), tr("~/Documents/Projets", "~/Documents/Projects"),
                .file(sampleFile(tr("Notes de réunion.md", "Meeting notes.md")))),
            row(tr("Notes partagées", "Shared notes"), "~/Documents", .file(sampleFile(tr("Notes partagées", "Shared notes"), folder: true))),
            row(tr("notes-atelier.txt", "workshop-notes.txt"), tr("~/Bureau", "~/Desktop"), .file(sampleFile(tr("notes-atelier.txt", "workshop-notes.txt")))),
        ], selected: 1, view: .list)
    }

    /// Même recherche après ⌘G : les fichiers seuls, en grille, nom sous chaque tuile (session 099 FR-002).
    private func filesGridScene() -> TargetSearchBar {
        let files = UILanguage.current == .fr
            ? ["Notes de réunion.md", "Notes de version 2.4.pdf", "notes-atelier.txt", "Notes partagées",
               "Notes de cours.docx", "Notes de frais.xlsx", "Notes de lecture.rtf", "Notes de présentation.key",
               "Notes de projet.numbers", "Notes du jardin.pages", "Notes archivées.zip", "Notes du séminaire.mov", "Notes vocales.m4a",
               "Notes de voyage"]
            : ["Meeting notes.md", "Release notes 2.4.pdf", "workshop-notes.txt", "Shared notes",
               "Lecture notes.docx", "Expense notes.xlsx", "Reading notes.rtf", "Keynote notes.key",
               "Project notes.numbers", "Garden notes.pages", "Archived notes.zip", "Seminar notes.mov", "Voice notes.m4a",
               "Travel notes"]
        var state = bar("note", files.map { name in
            row(name, "", .file(sampleFile(name, folder: !name.contains("."))))
        }, selected: 0, view: .grid)
        state.grid = SearchGrid(columns: LauncherViewMode.grid.columns ?? 7, showTitles: true)
        return state
    }

    /// Workflow d'émojis en grille : le nom de l'émoji choisi en pied (session 099 FR-003).
    private func emojiGridScene() -> TargetSearchBar {
        let emojis: [(String, String, String)] = [
            ("❤️", "Cœur rouge", "Red heart"), ("🧡", "Cœur orange", "Orange heart"), ("💛", "Cœur jaune", "Yellow heart"),
            ("💚", "Cœur vert", "Green heart"), ("💙", "Cœur bleu", "Blue heart"), ("💜", "Cœur violet", "Purple heart"),
            ("🖤", "Cœur noir", "Black heart"), ("🤍", "Cœur blanc", "White heart"), ("💔", "Cœur brisé", "Broken heart"),
            ("💖", "Cœur étincelant", "Sparkling heart"), ("💕", "Deux cœurs", "Two hearts"), ("💘", "Cœur avec flèche", "Heart with arrow"),
            ("💓", "Cœur battant", "Beating heart"), ("💗", "Cœur qui grandit", "Growing heart"),
        ]
        let selected = 9
        let copies = tr("Retour copie", "Return copies")
        var state = bar(tr("emoji coeur", "emoji heart"), emojis.map { row(tr($0.1, $0.2), "\(copies) \($0.0)", .image(emojiImage($0.0))) },
                        selected: selected, view: .grid)
        let chosen = emojis[selected]
        state.grid = SearchGrid(columns: LauncherViewMode.grid.columns ?? 7, showTitles: false,
                                footer: "\(tr(chosen.1, chosen.2)) · \(copies) \(chosen.0)")
        return state
    }

    private func verbsScene() -> TargetSearchBar {
        let safari = LauncherApp(bundleID: "com.apple.Safari", path: App.safari, name: "Safari", alternateNames: [])
        let rows = LauncherVerb.verbs(for: .app(safari)).map { verb in
            row(verb.title(app: "Safari"), verb.needsDestination ? tr("Tab ou Retour : choisir", "Tab or Return: choose") : "",
                .symbol(verb.needsDestination ? "arrow.right.circle" : "play.circle"))
        }
        return bar("", rows, selected: 1, properties: "Safari  ›  " + tr("verbe ou destination…", "verb or destination…"))
    }

    private func phraseScene() -> TargetSearchBar {
        bar(tr("safari perso gauche", "safari personal left"), [
            header(tr("Phrase", "Phrase")),
            row(tr("Ouvrir Safari dans Perso, à gauche", "Open Safari in Personal, on the left"),
                tr("Retour fait l'action · ⌘S la garde", "Return runs it · ⌘S saves it"), .file(App.safari)),
            header(tr("Applications", "Applications")),
            row("Safari", tr("Ouverte · Recherche", "Open · Research"), .file(App.safari)),
            header(tr("Stages et bureaux", "Stages and desktops")),
            row(personal, tr("Bureau 1 · 2 fenêtre(s)", "Desktop 1 · 2 window(s)"), .symbol("square.stack.3d.up"), letter: "⇧P"),
        ], selected: 1)
    }

    private func workflowScene() -> TargetSearchBar {
        bar(tr("heure tokyo", "time tokyo"), [
            header(tr("Fuseaux horaires", "Time zones")),
            row(tr("Tokyo : 22 h 32", "Tokyo: 10:32 PM"), tr("jeudi 29 octobre · Retour copie", "Thursday, October 29 · Return copies"), .symbol("clock")),
            row(tr("Tokyo → Paris : 14 h 32", "Tokyo → Paris: 2:32 PM"), tr("8 heures de décalage", "8 hours behind"), .symbol("arrow.left.arrow.right")),
            row(tr("Ajouter Tokyo aux favoris", "Add Tokyo to favorites"), tr("Mots-clés : heure, time", "Keywords: time, heure"), .symbol("star")),
            header("Workflows"),
            row(tr("Fuseaux horaires", "Time zones"), tr("heure · workflow d'Alfred", "time · Alfred workflow"), .symbol("puzzlepiece.extension")),
        ], selected: 1)
    }

    private func calcScene() -> TargetSearchBar {
        let expression = "(1250*12)/7"
        let calc = LauncherCalculator.evaluate(expression, locale: Locale(identifier: tr("fr_FR", "en_US")))
        return bar(expression, [
            header(tr("Calcul", "Calculation")),
            row(calc?.text ?? "?", "\(calc?.expression ?? expression) · \(LauncherCalculator.returnHint(opensCalculator: false))",
                .symbol("equal.square")),
            header("Web"),
            row(tr("Rechercher « (1250*12)/7 » sur Google", "Search Google for “(1250*12)/7”"), "www.google.com", .symbol("magnifyingglass")),
        ], selected: 1)
    }

    // MARK: Rendu

    private func theme(_ id: String) -> LauncherTheme { LauncherTheme.builtIn.first { $0.id == id } ?? .roadie }

    private func style(_ theme: LauncherTheme) -> TargetOverlayStyle {
        var style = TargetOverlayStyle(searchTextFontSize: 21, commandTextFontSize: 17)
        style.theme = theme
        return style
    }

    /// Fond inventé : dégradé et deux halos, sans le fond d'écran de l'utilisateur.
    private static func drawBackdrop(_ rect: CGRect) {
        NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.36, alpha: 1),
                            NSColor(calibratedRed: 0.34, green: 0.16, blue: 0.42, alpha: 1),
                            NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.32, alpha: 1)])?.draw(in: rect, angle: 35)
        for (center, color) in [(CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.8), NSColor.systemTeal),
                                (CGPoint(x: rect.minX + rect.width * 0.85, y: rect.minY + rect.height * 0.25), NSColor.systemPink)] {
            NSGradient(colors: [color.withAlphaComponent(0.45), color.withAlphaComponent(0)])?
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: max(rect.width, rect.height) * 0.45, options: [])
        }
    }

    /// Vue dessinée par une fermeture, posée dans une vraie fenêtre hors écran : le rendu d'AppKit en a besoin.
    private final class Canvas: NSView {
        var body: (CGRect) -> Void = { _ in }
        override func draw(_ dirtyRect: NSRect) { body(bounds) }
    }

    private func bitmap(size: CGSize, body: @escaping (CGRect) -> Void) async throws -> NSBitmapImageRep {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        let canvas = Canvas(frame: CGRect(origin: .zero, size: size))
        canvas.body = body
        window.contentView = canvas
        func capture() throws -> NSBitmapImageRep {
            let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            return rep
        }
        _ = try capture()
        // Icônes réduites en fond (session 123) : rendre la main au fil principal pour qu'elles arrivent.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return try capture()
    }

    /// Barre et liste seules, avec une marge de fond autour.
    private func renderBar(_ state: TargetSearchBar, theme: LauncherTheme, backdrop: Bool = true) async throws -> NSBitmapImageRep {
        let style = style(theme)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 1100)
        var state = state
        state.placement = .top
        let layout = state.layout(in: screen, style: style)
        let content = [layout.bar, layout.panel].compactMap { $0 }.reduce(layout.bar) { $0.union($1) }
        let margin: CGFloat = 48
        let size = CGSize(width: content.width + 2 * margin, height: content.height + 2 * margin)
        let origin = CGPoint(x: margin - content.minX, y: margin - content.minY)
        return try await bitmap(size: size) { bounds in
            if backdrop { Self.drawBackdrop(bounds) }
            let shifted = screen.offsetBy(dx: origin.x, dy: origin.y)
            // Flou d'arrière-plan du thème (NSVisualEffectView à l'exécution) : teinte posée dessous.
            if theme.effect != .none {
                (theme.effect == .dark ? NSColor(calibratedWhite: 0.11, alpha: 0.74) : NSColor(calibratedWhite: 0.95, alpha: 0.72)).setFill()
                for rect in [layout.bar, layout.panel].compactMap({ $0 }) {
                    let local = rect.offsetBy(dx: origin.x, dy: origin.y)
                    NSBezierPath(roundedRect: local, xRadius: theme.roundness, yRadius: theme.roundness).fill()
                }
            }
            SearchBarRenderer.draw(state, in: shifted, style: style)
        }
    }

    /// Image posée par-dessus le fond : `draw(in:)` remplacerait les pixels, voile translucide compris.
    private static func over(_ rep: NSBitmapImageRep, in rect: CGRect) {
        rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        guard let output else { return }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let folder = UILanguage.current == .fr ? output.appendingPathComponent("fr") : output
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }

    @Test func launcherScenes() async throws {
        guard output != nil else { return }
        let main = theme("alfred-modern-dark")
        try await eachLanguage {
            for (name, state) in [("launcher-search", searchScene()), ("launcher-verbs", verbsScene()), ("launcher-phrase", phraseScene()),
                                  ("launcher-workflow", workflowScene()), ("launcher-calc", calcScene()),
                                  ("launcher-files-grid", filesGridScene()), ("launcher-emoji-grid", emojiGridScene())] {
                try save(try await renderBar(state, theme: main), name)
            }
        }
    }

    @Test func launcherThemes() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await launcherThemesImage() }
    }

    private func launcherThemesImage() async throws {
        var renders: [NSBitmapImageRep] = []
        for id in ["alfred-modern-dark", "alfred", "alfred-macos-dark", "frosty-teal"] {
            renders.append(try await renderBar(phraseScene(), theme: theme(id), backdrop: false))
        }
        let cell = renders.reduce(CGSize.zero) { CGSize(width: max($0.width, $1.size.width), height: max($0.height, $1.size.height)) }
        let rep = try await bitmap(size: CGSize(width: cell.width * 2, height: cell.height * 2)) { bounds in
            Self.drawBackdrop(bounds)
            for (index, render) in renders.enumerated() {
                let origin = CGPoint(x: CGFloat(index % 2) * cell.width + (cell.width - render.size.width) / 2,
                                     y: CGFloat(1 - index / 2) * cell.height + (cell.height - render.size.height) / 2)
                Self.over(render, in: CGRect(origin: origin, size: render.size))
            }
        }
        try save(rep, "launcher-themes")
    }

    // MARK: Sélecteur et vue d'ensemble

    private struct SampleWindow {
        let app: String
        let path: String
        let title: String
        let look: Look
        let desktop: Int
        let stage: String
    }

    private enum Look { case code, browser, notes, terminal, mail, calendar, board, music }

    private var windows: [SampleWindow] {
        let development = tr("Développement", "Development"), design = tr("Conception", "Design")
        return [
            SampleWindow(app: "Terminal", path: App.terminal, title: tr("~/projets/atelier — zsh", "~/projects/workshop — zsh"), look: .terminal,
                         desktop: 1, stage: development),
            SampleWindow(app: "Safari", path: App.safari, title: tr("Documentation de l'API", "API documentation"), look: .browser,
                         desktop: 1, stage: development),
            SampleWindow(app: "Notes", path: App.notes, title: tr("Idées de voyage", "Travel ideas"), look: .notes, desktop: 1, stage: personal),
            SampleWindow(app: tr("Musique", "Music"), path: App.music, title: tr("Écoute en cours", "Now playing"), look: .music,
                         desktop: 1, stage: personal),
            SampleWindow(app: "Mail", path: App.mail, title: tr("Boîte de réception", "Inbox"), look: .mail, desktop: 2, stage: "Communication"),
            SampleWindow(app: tr("Calendrier", "Calendar"), path: App.calendar, title: tr("Semaine 44", "Week 44"), look: .calendar,
                         desktop: 2, stage: "Communication"),
            SampleWindow(app: "Freeform", path: App.freeform, title: tr("Plan du projet", "Project plan"), look: .board, desktop: 2, stage: design),
            SampleWindow(app: "Terminal", path: App.terminal, title: tr("Journal du serveur", "Server log"), look: .code, desktop: 2, stage: design),
        ]
    }

    private var mainDisplay: String { tr("Écran principal", "Main display") }

    private func entries() -> [WindowSwitcherEntry] {
        windows.enumerated().map { index, sample in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(index + 1)), pid: Int32(9000 + index),
                appName: sample.app, bundleID: "doc.\(index)", title: sample.title,
                frame: Rect(x: 0, y: 0, width: 1280, height: 800), isOnScreen: true, isTileCandidate: true),
                scope: StageScope(displayID: DisplayID(rawValue: "principal"), desktopID: DesktopID(rawValue: sample.desktop),
                                  stageID: StageID(rawValue: sample.stage)),
                displayName: mainDisplay, desktopName: tr("Bureau", "Desktop") + " \(sample.desktop)", stageName: sample.stage)
        }
    }

    private func icons() -> [Int32: NSImage] {
        Dictionary(uniqueKeysWithValues: windows.enumerated().map { (Int32(9000 + $0.offset), NSWorkspace.shared.icon(forFile: $0.element.path)) })
    }

    private func thumbnails() -> [WindowID: NSImage] {
        Dictionary(uniqueKeysWithValues: windows.enumerated().map { (WindowID(rawValue: UInt32($0.offset + 1)), Self.mock($0.element.look)) })
    }

    /// Fenêtre inventée : barre de titre, puis des blocs qui évoquent son contenu, sans texte lisible.
    private static func mock(_ look: Look) -> NSImage {
        let size = CGSize(width: 1280, height: 800)
        return NSImage(size: size, flipped: true) { rect in
            let dark = [Look.code, .terminal, .music].contains(look)
            (dark ? NSColor(calibratedWhite: 0.11, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)).setFill()
            rect.fill()
            (dark ? NSColor(calibratedWhite: 0.18, alpha: 1) : NSColor(calibratedWhite: 0.90, alpha: 1)).setFill()
            CGRect(x: 0, y: 0, width: size.width, height: 56).fill()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: CGRect(x: 24 + CGFloat(index) * 30, y: 18, width: 20, height: 20)).fill()
            }
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 6) {
                color.setFill()
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
            }
            let soft = NSColor(calibratedWhite: dark ? 0.35 : 0.80, alpha: 1)
            switch look {
            case .terminal, .code:
                let palette: [NSColor] = look == .terminal ? [.systemGreen, soft, soft, .systemTeal] : [.systemPink, .systemTeal, soft, .systemYellow, .systemPurple]
                for line in 0..<20 {
                    let indent = CGFloat([0, 40, 80, 40, 0, 120][line % 6])
                    bar(40 + indent, 90 + CGFloat(line) * 34, CGFloat(160 + (line * 137) % 620), 16, palette[line % palette.count], radius: 4)
                }
            case .browser:
                bar(180, 12, 760, 32, NSColor(calibratedWhite: 1, alpha: 1), radius: 10)
                bar(60, 100, 1160, 220, NSColor.systemBlue.withAlphaComponent(0.75), radius: 18)
                for column in 0..<3 {
                    bar(60 + CGFloat(column) * 393, 350, 367, 180, NSColor(calibratedWhite: 0.88, alpha: 1), radius: 14)
                    bar(80 + CGFloat(column) * 393, 560, 300, 16, soft, radius: 4)
                    bar(80 + CGFloat(column) * 393, 590, 220, 16, soft, radius: 4)
                }
            case .notes:
                bar(0, 56, 300, size.height - 56, NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.80, alpha: 1), radius: 0)
                for item in 0..<7 { bar(24, 90 + CGFloat(item) * 70, 240, 22, soft, radius: 5) }
                bar(340, 90, 420, 34, NSColor(calibratedWhite: 0.25, alpha: 1))
                for line in 0..<12 { bar(340, 160 + CGFloat(line) * 42, CGFloat(380 + (line * 97) % 480), 16, soft, radius: 4) }
            case .mail:
                for item in 0..<9 {
                    bar(24, 80 + CGFloat(item) * 78, 360, 60, item == 1 ? NSColor.systemBlue.withAlphaComponent(0.8) : NSColor(calibratedWhite: 0.92, alpha: 1), radius: 10)
                }
                bar(420, 90, 520, 30, NSColor(calibratedWhite: 0.25, alpha: 1))
                for line in 0..<12 { bar(420, 150 + CGFloat(line) * 40, CGFloat(420 + (line * 89) % 400), 16, soft, radius: 4) }
            case .calendar:
                for day in 0..<7 {
                    for slot in 0..<6 where (day * 3 + slot * 5) % 4 == 0 {
                        let color: NSColor = [.systemRed, .systemBlue, .systemGreen, .systemOrange][(day + slot) % 4]
                        bar(40 + CGFloat(day) * 172, 90 + CGFloat(slot) * 112, 160, 96, color.withAlphaComponent(0.55), radius: 8)
                    }
                }
            case .board:
                for (index, color) in [NSColor.systemYellow, .systemPink, .systemTeal, .systemOrange, .systemGreen, .systemPurple].enumerated() {
                    bar(80 + CGFloat(index % 3) * 380, 110 + CGFloat(index / 3) * 300, 300, 230, color.withAlphaComponent(0.7), radius: 12)
                }
            case .music:
                bar(60, 100, 380, 380, NSColor.systemPink.withAlphaComponent(0.8), radius: 16)
                for track in 0..<10 { bar(500, 110 + CGFloat(track) * 56, CGFloat(420 + (track * 71) % 280), 20, soft, radius: 5) }
                bar(60, 640, 1160, 10, NSColor.systemPink, radius: 5)
            }
            return true
        }
    }

    @Test func windowSwitcher() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await windowSwitcherImage() }
    }

    private func windowSwitcherImage() async throws {
        let entries = entries()
        let images = thumbnails()
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig()))
        defer { panel.close() }
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.appIcons = icons()
        panel.configure(profile: WindowSwitcherShortcutConfig())
        panel.layout(in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        panel.render(entries: entries, selectedID: entries[1].id, query: "", images: images, previewImage: images[entries[1].id], emptyMessage: tr("Aucune fenêtre", "No windows"))
        let content = try #require(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let panelRep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: panelRep)
        let margin: CGFloat = 48
        let rep = try await bitmap(size: CGSize(width: content.bounds.width + 2 * margin, height: content.bounds.height + 2 * margin)) { bounds in
            Self.drawBackdrop(bounds)
            let panelRect = bounds.insetBy(dx: margin, dy: margin)
            NSBezierPath(roundedRect: panelRect, xRadius: 16, yRadius: 16).addClip()
            Self.over(panelRep, in: panelRect)
        }
        try save(rep, "window-switcher")
    }

    /// Session 136 : le sélecteur de zones (⌥Tab), avec des zones inventées découpées dans les mêmes fausses fenêtres.
    @Test func zoneSwitcher() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await zoneSwitcherImage() }
    }

    /// Photo d'une zone : 300 × 180 points découpés dans la fausse fenêtre, autour de `origin` (coin haut gauche).
    private static func zonePhoto(_ look: Look, at origin: CGPoint) -> NSImage {
        let window = mock(look)
        let crop = CGSize(width: 600, height: 360)
        return NSImage(size: CGSize(width: 300, height: 180), flipped: false) { rect in
            window.draw(in: rect, from: CGRect(x: origin.x, y: 800 - origin.y - crop.height, width: crop.width, height: crop.height),
                        operation: .copy, fraction: 1)
            return true
        }
    }

    private func zoneSwitcherImage() async throws {
        let windowsEntries = entries()
        func zone(_ look: Look, _ title: String, _ origin: CGPoint) -> (ZoneRecord, NSImage)? {
            guard let index = windows.firstIndex(where: { $0.look == look }) else { return nil }
            let record = ZoneRecord(appName: windows[index].app, bundleID: "doc.\(index)", pid: Int32(9000 + index), windowID: UInt32(index + 1),
                                    windowTitle: windows[index].title, title: title, relative: Rect(x: origin.x / 2, y: origin.y / 2, width: 80, height: 24),
                                    windowWidth: 640, windowHeight: 400, date: Date())
            return (record, Self.zonePhoto(look, at: origin))
        }
        let zones = [zone(.browser, tr("Bouton « Réserver »", "“Book” button"), CGPoint(x: 360, y: 300)),
                     zone(.mail, tr("Message de Léa", "Message from Léa"), CGPoint(x: 20, y: 60)),
                     zone(.calendar, tr("Réunion de jeudi", "Thursday meeting"), CGPoint(x: 520, y: 180)),
                     zone(.code, tr("Erreur ligne 42", "Error on line 42"), CGPoint(x: 30, y: 220)),
                     zone(.board, tr("Carte « Budget »", "“Budget” card"), CGPoint(x: 420, y: 90)),
                     zone(.notes, tr("Note « Lisbonne »", "“Lisbon” note"), CGPoint(x: 0, y: 60))].compactMap { $0 }
        let built = WindowSwitcherZones.build(records: zones.map(\.0), windows: windowsEntries)
        var images: [WindowID: NSImage] = [:]
        for (entry, photo) in zip(built.entries, zones.map(\.1)) { images[entry.id] = photo }
        // Cartes plus larges que le défaut : les textes des zones restent lisibles sur la capture.
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(thumbnailWidth: 300)))
        defer { panel.close() }
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.appIcons = icons()
        panel.configure(profile: WindowSwitcherShortcutConfig(id: "zones", name: tr("Zones récentes", "Recent zones"), source: "zones"))
        panel.layout(in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        panel.render(entries: built.entries, selectedID: built.entries[1].id, query: "", images: images,
                     previewImage: images[built.entries[1].id], emptyMessage: "")
        let content = try #require(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let panelRep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: panelRep)
        let margin: CGFloat = 48
        let rep = try await bitmap(size: CGSize(width: content.bounds.width + 2 * margin, height: content.bounds.height + 2 * margin)) { bounds in
            Self.drawBackdrop(bounds)
            let panelRect = bounds.insetBy(dx: margin, dy: margin)
            NSBezierPath(roundedRect: panelRect, xRadius: 16, yRadius: 16).addClip()
            Self.over(panelRep, in: panelRect)
        }
        try save(rep, "zone-switcher")
    }

    @Test func overview() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await overviewImage() }
    }

    private func overviewImage() async throws {
        let displays = [DisplaySnapshot(id: DisplayID(rawValue: "principal"), index: 0, name: mainDisplay,
                                        frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 0, width: 1440, height: 900), isMain: true)]
        let size = CGSize(width: 1440, height: 860)
        let canvas = OverviewCanvas(frame: CGRect(origin: .zero, size: size))
        canvas.model = OverviewModel(entries: entries(), displays: displays, state: PersistentStageState())
        canvas.viewport = size
        canvas.config = OverviewConfig(presentation: "archipelago")
        canvas.images = thumbnails()
        canvas.appIcons = icons()
        canvas.focusedDesktop = canvas.model.displays.first?.desktops.first?.id
        canvas.selectedID = canvas.model.entries.dropFirst().first?.id
        canvas.rebuild()
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        window.contentView = canvas
        let canvasRep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: canvasRep)
        let composed = try await bitmap(size: size) { bounds in
            Self.drawBackdrop(bounds)
            Self.over(canvasRep, in: bounds)
        }
        try save(composed, "overview")
    }
}
