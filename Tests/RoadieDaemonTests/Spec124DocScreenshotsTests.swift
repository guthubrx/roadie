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

    private func clipboardScene() -> TargetSearchBar {
        bar("cb", [
            header(tr("Presse-papiers local · 0o600 · mots de passe exclus", "Local clipboard · 0o600 · passwords excluded")),
            row("📌 git switch -c feat/layouts-advanced", tr("Terminal · épinglé · Retour copie", "Terminal · pinned · Return copies"), .file(App.terminal)),
            row("https://example.org/docs/roadmap", tr("Safari · il y a 2 min · 34 car.", "Safari · 2m ago · 34 chars"), .file(App.safari)),
            row(tr("Réunion produit jeudi à 10 h 00 — salle Lisbonne", "Product meeting Thursday 10:00 AM — Lisbon room"),
                tr("Notes · il y a 8 min · 48 car.", "Notes · 8m ago · 48 chars"), .file(App.notes)),
            row("{\"mode\": \"scrolling\", \"column_width\": 0.65}", tr("Terminal · il y a 19 min · JSON", "Terminal · 19m ago · JSON"), .file(App.terminal)),
            row(tr("Budget prévisionnel T2 : +12 %", "Q2 forecast budget: +12%"), tr("Mail · il y a 42 min · 30 car.", "Mail · 42m ago · 30 chars"), .file(App.mail)),
        ], selected: 1, view: .list)
    }

    private func snippetsScene() -> TargetSearchBar {
        bar("snip", [
            header(tr("Snippets locaux · variables {date} {clipboard} {cursor}", "Local snippets · {date} {clipboard} {cursor} variables")),
            row("!date · " + tr("Date du jour", "Today's date"), tr("2026-11-25 · Retour copie l'expansion", "2026-11-25 · Return copies expansion"), .symbol("calendar.badge.clock")),
            row("!sig · " + tr("Signature courte", "Short signature"), tr("Cordialement,\nAlex — Équipe produit", "Best regards,\nAlex — Product team"), .symbol("signature")),
            row("!cr · " + tr("Compte-rendu de réunion", "Meeting notes template"), tr("# Réunion {date} — {clipboard}", "# Meeting {date} — {clipboard}"), .symbol("doc.text")),
            row("!mail · " + tr("Adresse exemple", "Example address"), "alex@example.org", .symbol("envelope")),
        ], selected: 1, view: .list)
    }

    private func converterMiniScene() -> TargetSearchBar {
        bar("100 km in mi", [
            header(tr("Convertisseur intégré · unités, bases, fuseaux", "Built-in converter · units, bases, time zones")),
            row(tr("62,14 mi", "62.14 mi"), tr("100 km → miles · Retour copie", "100 km → miles · Return copies"), .symbol("arrow.left.arrow.right.square")),
            row("0xff → 255", tr("Hexadécimal · binaire · octal · fuseaux", "Hex · binary · octal · time zones"), .symbol("number.square")),
        ], selected: 1)
    }

    private func timerMiniScene() -> TargetSearchBar {
        bar("timer 25m focus", [
            header(tr("Minuteur & Pomodoro", "Timer & Pomodoro")),
            row(tr("Démarrer le minuteur : 25 min — focus", "Start timer: 25 min — focus"), tr("Notification locale macOS à la fin", "Local macOS notification when done"), .symbol("timer")),
            row(tr("Pomodoro · 25 min de concentration", "Pomodoro · 25 min focus session"), "pomodoro · timer status · timer stop", .symbol("flame")),
        ], selected: 1)
    }

    private func colorPickerMiniScene() -> TargetSearchBar {
        bar(tr("pipette", "color picker"), [
            header(tr("Pipette de couleur native", "Native color picker")),
            row(tr("Ouvrir la pipette de couleur", "Open color picker"), "#3B82F6 · rgb(59, 130, 246) · hsl(217, 91%, 60%)", .symbol("eyedropper.halffull")),
            row(tr("Copie #RRGGBB dans le presse-papiers", "Copies #RRGGBB to clipboard"), tr("Sans plugin externe · NSColorSampler", "Built-in · NSColorSampler"), .symbol("swatchpalette")),
        ], selected: 1)
    }

    private func nativeEmojiMiniScene() -> TargetSearchBar {
        let emojis: [(String, String, String)] = [
            ("🚀", "Fusée", "Rocket"), ("✨", "Étincelles", "Sparkles"), ("🔥", "Feu", "Fire"),
            ("⚡", "Éclair", "Lightning"), ("🎯", "Cible", "Target"), ("💡", "Idée", "Idea"),
            ("🧩", "Puzzle", "Puzzle"),
        ]
        let copies = tr("Retour copie", "Return copies")
        var state = bar(tr(":fusée", ":rocket"), emojis.map { row(tr($0.1, $0.2), "\(copies) \($0.0)", .image(emojiImage($0.0))) },
                        selected: 0, view: .grid)
        state.grid = SearchGrid(columns: 7, showTitles: false,
                                footer: "\(tr("Fusée", "Rocket")) · \(copies) 🚀 · " + tr("Catalogue natif FR/EN", "Built-in FR/EN catalog"))
        return state
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
                                  ("launcher-files-grid", filesGridScene()), ("launcher-emoji-grid", emojiGridScene()),
                                  ("launcher-clipboard", clipboardScene()), ("launcher-snippets", snippetsScene())] {
                try save(try await renderBar(state, theme: main), name)
            }
        }
    }

    @Test func launcherToolsShowcase() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await launcherToolsImage() }
    }

    private func launcherToolsImage() async throws {
        let main = theme("alfred-modern-dark")
        let scenes = [converterMiniScene(), timerMiniScene(), colorPickerMiniScene(), nativeEmojiMiniScene()]
        var renders: [NSBitmapImageRep] = []
        for scene in scenes {
            renders.append(try await renderBar(scene, theme: main, backdrop: false))
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
        try save(rep, "launcher-tools")
    }

    @Test func advancedLayoutsShowcase() async throws {
        guard output != nil else { return }
        try await eachLanguage { try await advancedLayoutsImage() }
    }

    private func advancedLayoutsImage() async throws {
        let size = CGSize(width: 1560, height: 640)
        let termIcon = NSWorkspace.shared.icon(forFile: App.terminal)
        let safariIcon = NSWorkspace.shared.icon(forFile: App.safari)
        let notesIcon = NSWorkspace.shared.icon(forFile: App.notes)
        let termMock = Self.mock(.code)
        let safariMock = Self.mock(.browser)
        let notesMock = Self.mock(.notes)
        let leftTitle = tr("Mode Onglets (tabbed)", "Tabbed mode (tabbed)")
        let leftSub = tr("Barre d'onglets cliquable · 1 fenêtre active plein cadre · focus left/right",
                         "Clickable tab bar · 1 active window full-frame · focus left/right")
        let rightTitle = tr("Mode Ruban défilant (scrolling) + Dim Inactive", "Scrolling ribbon mode (scrolling) + Dim Inactive")
        let rightSub = tr("Colonne active centrée (65 %) · bords voisins cliquables · atténuation douce",
                          "Centered active column (65%) · clickable neighbor edges · subtle dimming")
        let tabs: [(String, NSImage, Bool)] = [
            (tr("Terminal — atelier", "Terminal — workshop"), termIcon, true),
            (tr("Safari — Documentation", "Safari — Docs"), safariIcon, false),
            (tr("Notes — Plan", "Notes — Plan"), notesIcon, false),
        ]
        let rep = try await bitmap(size: size) { bounds in
            Self.drawBackdrop(bounds)
            let pad: CGFloat = 36
            let gap: CGFloat = 28
            let cardW = (bounds.width - 2 * pad - gap) / 2
            let cardH = bounds.height - 2 * pad

            func drawText(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) {
                (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }

            func drawCardFrame(_ rect: CGRect, title: String, subtitle: String) -> CGRect {
                NSColor(calibratedWhite: 0.08, alpha: 0.72).setFill()
                let bg = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
                bg.fill()
                NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
                bg.lineWidth = 1.2
                bg.stroke()
                drawText(title, at: CGPoint(x: rect.minX + 22, y: rect.maxY - 40), size: 19, weight: .bold)
                drawText(subtitle, at: CGPoint(x: rect.minX + 22, y: rect.maxY - 62), size: 12.5, color: NSColor(calibratedWhite: 0.82, alpha: 1))
                return CGRect(x: rect.minX + 20, y: rect.minY + 20, width: rect.width - 40, height: rect.height - 96)
            }

            // Panneau gauche : Mode Onglets (tabbed)
            let leftCard = CGRect(x: pad, y: pad, width: cardW, height: cardH)
            let leftCanvas = drawCardFrame(leftCard, title: leftTitle, subtitle: leftSub)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: leftCanvas, xRadius: 12, yRadius: 12).addClip()
            NSColor(calibratedWhite: 0.14, alpha: 0.85).setFill()
            leftCanvas.fill()
            let barH: CGFloat = 34
            let barRect = CGRect(x: leftCanvas.minX + 8, y: leftCanvas.maxY - barH - 8, width: leftCanvas.width - 16, height: barH)
            NSColor(calibratedWhite: 0.10, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 9, yRadius: 9).fill()
            let tabGap: CGFloat = 6
            let tabW = (barRect.width - CGFloat(tabs.count + 1) * tabGap) / CGFloat(tabs.count)
            for (idx, tab) in tabs.enumerated() {
                let r = CGRect(x: barRect.minX + tabGap + CGFloat(idx) * (tabW + tabGap),
                               y: barRect.minY + 4, width: tabW, height: barH - 8)
                (tab.2 ? NSColor.systemTeal.withAlphaComponent(0.85) : NSColor(calibratedWhite: 0.22, alpha: 0.85)).setFill()
                NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
                tab.1.draw(in: CGRect(x: r.minX + 8, y: r.minY + 4, width: 18, height: 18))
                drawText(tab.0, at: CGPoint(x: r.minX + 32, y: r.minY + 5), size: 12, weight: tab.2 ? .semibold : .regular,
                         color: tab.2 ? .white : NSColor(calibratedWhite: 0.85, alpha: 1))
            }
            let winRect = CGRect(x: leftCanvas.minX + 8, y: leftCanvas.minY + 8,
                                 width: leftCanvas.width - 16, height: leftCanvas.height - barH - 22)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: winRect, xRadius: 10, yRadius: 10).addClip()
            termMock.draw(in: winRect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(roundedRect: winRect, xRadius: 10, yRadius: 10)
            border.lineWidth = 2
            border.stroke()
            NSGraphicsContext.restoreGraphicsState()

            // Panneau droit : Mode Ruban défilant (scrolling) + Dim Inactive
            let rightCard = CGRect(x: pad + cardW + gap, y: pad, width: cardW, height: cardH)
            let rightCanvas = drawCardFrame(rightCard, title: rightTitle, subtitle: rightSub)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rightCanvas, xRadius: 12, yRadius: 12).addClip()
            NSColor(calibratedWhite: 0.14, alpha: 0.85).setFill()
            rightCanvas.fill()
            let colW = floor(rightCanvas.width * 0.65)
            let colGap: CGFloat = 10
            let colY = rightCanvas.minY + 10
            let colH = rightCanvas.height - 20
            let centerX = floor(rightCanvas.midX - colW / 2)
            let columns: [(CGRect, NSImage, Bool)] = [
                (CGRect(x: centerX - colGap - colW, y: colY, width: colW, height: colH), termMock, false),
                (CGRect(x: centerX, y: colY, width: colW, height: colH), safariMock, true),
                (CGRect(x: centerX + colW + colGap, y: colY, width: colW, height: colH), notesMock, false),
            ]
            for (colRect, img, focused) in columns {
                NSGraphicsContext.saveGraphicsState()
                let path = NSBezierPath(roundedRect: colRect, xRadius: 10, yRadius: 10)
                path.addClip()
                img.draw(in: colRect)
                if !focused {
                    // Voile Dim Inactive (opacity ~0.30) sur les colonnes voisines
                    NSColor(calibratedWhite: 0.02, alpha: 0.34).setFill()
                    colRect.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                if focused {
                    NSColor.systemTeal.withAlphaComponent(0.95).setStroke()
                    let focusRing = NSBezierPath(roundedRect: colRect, xRadius: 10, yRadius: 10)
                    focusRing.lineWidth = 2.5
                    focusRing.stroke()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        try save(rep, "layouts-advanced")
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

    /// Photo d'une zone : petite scène inventée, avec du texte lisible (session 139 : les blocs gris ne se comprenaient
    /// pas), à l'échelle d'une vraie photo de zone (300 × 180 points). Aucun contenu réel.
    private enum ZoneScene { case booking, inbox, agenda, code, board, note }

    private static func zonePhoto(_ scene: ZoneScene) -> NSImage {
        NSImage(size: CGSize(width: 300, height: 180), flipped: true) { rect in
            func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = .black, mono: Bool = false) {
                let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
                (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
            }
            func box(_ frame: CGRect, _ color: NSColor, radius: CGFloat = 6) {
                color.setFill()
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            }
            let grey = NSColor(calibratedWhite: 0.45, alpha: 1)
            switch scene {
            case .booking:
                box(rect, NSColor(calibratedWhite: 0.97, alpha: 1), radius: 0)
                box(CGRect(x: 10, y: 8, width: 280, height: 22), .white, radius: 8)
                text("voyages-exemple.fr/lisbonne", 22, 11, size: 11, color: grey)
                box(CGRect(x: 10, y: 40, width: 280, height: 132), .white, radius: 10)
                text(tr("Lisbonne · 3 nuits", "Lisbon · 3 nights"), 22, 50, size: 15, weight: .semibold)
                text(tr("Hôtel Alfama · 12 au 15 nov.", "Alfama Hotel · Nov 12–15"), 22, 72, size: 11, color: grey)
                text("412 €", 22, 96, size: 20, weight: .bold, color: NSColor.systemGreen.blended(withFraction: 0.3, of: .black) ?? .systemGreen)
                box(CGRect(x: 168, y: 126, width: 110, height: 34), .systemBlue, radius: 9)
                text(tr("Réserver", "Book"), 194, 134, size: 14, weight: .semibold, color: .white)
            case .inbox:
                box(rect, .white, radius: 0)
                let rows = [(tr("Banque Exemple", "Example Bank"), tr("Relevé d'octobre", "October statement"), false),
                            ("Léa Martin", tr("Photos du week-end", "Weekend photos"), true),
                            (tr("Équipe projet", "Project team"), tr("Ordre du jour de jeudi", "Thursday's agenda"), false)]
                for (index, row) in rows.enumerated() {
                    let y = 8 + CGFloat(index) * 56
                    if row.2 { box(CGRect(x: 6, y: y, width: 288, height: 52), .systemBlue, radius: 8) }
                    let main: NSColor = row.2 ? .white : .black, soft: NSColor = row.2 ? NSColor(calibratedWhite: 0.92, alpha: 1) : grey
                    text(row.0, 16, y + 7, size: 13, weight: .semibold, color: main)
                    text(row.1, 16, y + 27, size: 12, color: soft)
                    text(tr("9 h 4\(index)", "9:4\(index)"), 244, y + 8, size: 10, color: soft)
                }
            case .agenda:
                box(rect, .white, radius: 0)
                text(tr("Jeudi 30", "Thursday 30"), 12, 8, size: 14, weight: .bold)
                for (index, hour) in ["9:00", "10:00", "11:00", "12:00"].enumerated() {
                    let y = 40 + CGFloat(index) * 36
                    text(hour, 10, y - 6, size: 10, color: grey)
                    NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
                    CGRect(x: 52, y: y, width: 240, height: 1).fill()
                }
                box(CGRect(x: 56, y: 76, width: 230, height: 34), NSColor.systemBlue.withAlphaComponent(0.85))
                text(tr("Réunion produit", "Product meeting"), 64, 80, size: 12, weight: .semibold, color: .white)
                text(tr("10:00 – 11:00 · Salle Lisbonne", "10:00 – 11:00 · Lisbon room"), 64, 95, size: 10, color: .white)
                box(CGRect(x: 56, y: 148, width: 230, height: 26), NSColor.systemGreen.withAlphaComponent(0.8))
                text(tr("Déjeuner avec Léa", "Lunch with Léa"), 64, 153, size: 11, weight: .semibold, color: .white)
            case .code:
                box(rect, NSColor(calibratedWhite: 0.12, alpha: 1), radius: 0)
                let lines = ["func total(_ items: [Item]) -> Int {", "    let prices = items.map(\\.price)", "    return itens.reduce(0, +)", "}"]
                for (index, line) in lines.enumerated() {
                    let y = 14 + CGFloat(index) * 22
                    text("\(40 + index)", 8, y, size: 11, color: NSColor(calibratedWhite: 0.45, alpha: 1), mono: true)
                    text(line, 34, y, size: 11, color: index == 2 ? NSColor.systemPink : NSColor(calibratedWhite: 0.88, alpha: 1), mono: true)
                }
                NSColor.systemRed.setFill()
                CGRect(x: 108, y: 72, width: 40, height: 2).fill()
                box(CGRect(x: 30, y: 112, width: 262, height: 52), NSColor.systemRed.withAlphaComponent(0.25))
                text(tr("Erreur ligne 42", "Error on line 42"), 40, 118, size: 12, weight: .semibold, color: .systemRed)
                text(tr("« itens » est inconnu ; vouliez-vous dire « items » ?", "“itens” is unknown; did you mean “items”?"), 40, 138,
                     size: 10, color: NSColor(calibratedWhite: 0.9, alpha: 1))
            case .board:
                box(rect, NSColor(calibratedWhite: 0.95, alpha: 1), radius: 0)
                for (index, note) in [(tr("Budget 2027", "2027 budget"), NSColor.systemYellow), (tr("Planning", "Schedule"), NSColor.systemPink),
                                      (tr("Idées", "Ideas"), NSColor.systemTeal)].enumerated() {
                    let x = 12 + CGFloat(index) * 96
                    box(CGRect(x: x, y: 24 + CGFloat(index % 2) * 18, width: 86, height: 110), note.1.withAlphaComponent(0.75), radius: 4)
                    text(note.0, x + 8, 34 + CGFloat(index % 2) * 18, size: 12, weight: .semibold)
                    for line in 0..<3 {
                        text(["• T1 : 40 k€", "• T2 : 55 k€", "• Marge 12 %"][line], x + 8, 56 + CGFloat(index % 2) * 18 + CGFloat(line) * 16, size: 9,
                             color: NSColor(calibratedWhite: 0.25, alpha: 1))
                    }
                }
            case .note:
                box(rect, .white, radius: 0)
                box(CGRect(x: 0, y: 0, width: 96, height: 180), NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.80, alpha: 1), radius: 0)
                for (index, title) in [tr("Lisbonne", "Lisbon"), tr("Courses", "Groceries"), tr("Livres", "Books")].enumerated() {
                    if index == 0 { box(CGRect(x: 4, y: 10, width: 88, height: 26), NSColor.systemYellow.withAlphaComponent(0.6)) }
                    text(title, 12, 15 + CGFloat(index) * 32, size: 12, weight: index == 0 ? .semibold : .regular)
                }
                text(tr("Lisbonne", "Lisbon"), 108, 12, size: 16, weight: .bold)
                for (index, line) in [tr("• Pastéis de Belém", "• Pastéis de Belém"), tr("• Tram 28 jusqu'à Alfama", "• Tram 28 to Alfama"),
                                      tr("• Coucher de soleil au miradouro", "• Sunset at the miradouro"), tr("• Fado le samedi", "• Fado on Saturday")].enumerated() {
                    text(line, 108, 44 + CGFloat(index) * 24, size: 11, color: NSColor(calibratedWhite: 0.2, alpha: 1))
                }
            }
            return true
        }
    }

    private func zoneSwitcherImage() async throws {
        let windowsEntries = entries()
        func zone(_ look: Look, _ scene: ZoneScene, _ title: String) -> (ZoneRecord, NSImage)? {
            guard let index = windows.firstIndex(where: { $0.look == look }) else { return nil }
            let record = ZoneRecord(appName: windows[index].app, bundleID: "doc.\(index)", pid: Int32(9000 + index), windowID: UInt32(index + 1),
                                    windowTitle: windows[index].title, title: title, relative: Rect(x: 100, y: 100, width: 80, height: 24),
                                    windowWidth: 640, windowHeight: 400, date: Date())
            return (record, Self.zonePhoto(scene))
        }
        let zones = [zone(.browser, .booking, tr("Bouton « Réserver »", "“Book” button")),
                     zone(.mail, .inbox, tr("Message de Léa", "Message from Léa")),
                     zone(.calendar, .agenda, tr("Réunion produit", "Product meeting")),
                     zone(.code, .code, tr("Erreur ligne 42", "Error on line 42")),
                     zone(.board, .board, tr("Note « Budget 2027 »", "“2027 budget” note")),
                     zone(.notes, .note, tr("Note « Lisbonne »", "“Lisbon” note"))].compactMap { $0 }
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
