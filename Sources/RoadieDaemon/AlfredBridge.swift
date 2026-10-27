import Foundation

/// Ordres qu'un script de workflow donne à Alfred, traduits en commandes `roadie workflow alfred`
/// (SPEC-093, research R2) : AppleScript `tell application [id] "<Alfred>" to …` (ligne ou bloc),
/// JavaScript `Application("<Alfred>")`. Texte pur : rien n'est envoyé à Alfred.
enum AlfredBridge {
    enum Language { case appleScript, javaScript }

    /// Noms qui désignent Alfred (identifiant, nom de l'application, anciennes versions).
    private static let name = #"(?:com\.runningwithcrayons\.Alfred|Alfred(?: [2-5])?)"#
    private static let oneLiner = try! NSRegularExpression(pattern: #"tell application (?:id )?""# + name + #""\s+to\s+(.+)$"#, options: [.anchorsMatchLines])
    private static let blockStart = try! NSRegularExpression(pattern: #"^\s*tell application (?:id )?""# + name + #""\s*$"#)
    private static let blockEnd = try! NSRegularExpression(pattern: #"^\s*end tell\s*$"#)
    private static let application = try! NSRegularExpression(pattern: #"Application\(\s*(["'])"# + name + #"\1\s*\)"#)
    private static let assigned = try! NSRegularExpression(pattern: #"(?:const|let|var)\s+(\w+)\s*=\s*Application\(\s*(["'])"# + name + #"\2\s*\)"#)
    private static let chained = try! NSRegularExpression(pattern: #"Application\(\s*(["'])"# + name + #"\1\s*\)\s*\.\s*(\w+)"#)

    /// Ordres AppleScript reconnus : motif, nom d'Alfred, arguments de la commande dans l'ordre de
    /// `roadie workflow alfred` (indices de groupes). `nil` : sans commande (version, sans effet).
    private struct Pattern { let regex: NSRegularExpression; let order: String; let verb: String?; let groups: [Int] }
    private static let patterns: [Pattern] = [
        (#"^return version$"#, "version", nil, []),
        (#"^version$"#, "version", nil, []),
        (#"^(?:activate|quit)$"#, "activate", nil, []),
        (#"^search(?:\s+(.+))?$"#, "search", "search", [1]),
        (#"^run trigger (.+?) in workflow (.+?)(?: with argument (.+))?$"#, "run trigger", "trigger", [2, 1, 3]),
        (#"^reload workflow (.+)$"#, "reload workflow", "reload", [1]),
        (#"^reveal workflow (.+)$"#, "reveal workflow", "reveal", [1]),
        (#"^set configuration (.+?) to value (.+?) in workflow (.+?)(?: as exportable .+)?$"#, "set configuration", "set", [3, 1, 2]),
        (#"^remove configuration (.+?) in workflow (.+)$"#, "remove configuration", "remove", [2, 1]),
    ].map { Pattern(regex: try! NSRegularExpression(pattern: $0.0), order: $0.1, verb: $0.2, groups: $0.3) }

    /// Méthodes JavaScript traduites par l'objet de Roadie, avec leur nom d'Alfred.
    private static let methods = ["search": "search", "runTrigger": "run trigger", "setConfiguration": "set configuration",
                                  "removeConfiguration": "remove configuration", "reloadWorkflow": "reload workflow",
                                  "revealWorkflow": "reveal workflow", "version": "version", "activate": "activate", "quit": "quit"]

    /// Texte traduit, ou nil s'il ne donne aucun ordre à Alfred (le texte reste alors tel quel). O(n).
    static func translate(_ source: String, language: Language, cli: String, version: String) -> String? {
        switch language {
        case .appleScript: appleScript(source, cli: cli, version: version)
        case .javaScript: javaScript(source, cli: cli, version: version)
        }
    }

    // MARK: AppleScript

    private static func appleScript(_ source: String, cli: String, version: String) -> String? {
        var changed = false
        var inBlock = false
        let lines = source.components(separatedBy: "\n").map { line -> String in
            let range = NSRange(line.startIndex..., in: line)
            if inBlock {
                if blockEnd.firstMatch(in: line, range: range) != nil { inBlock = false; return "-- fin" }
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                return command(line.trimmingCharacters(in: .whitespaces), cli: cli, version: version).map { indent + $0 } ?? line
            }
            if blockStart.firstMatch(in: line, range: range) != nil { inBlock = true; changed = true; return "-- Alfred (Roadie)" }
            guard let match = oneLiner.firstMatch(in: line, range: range), let order = Range(match.range(at: 1), in: line),
                  let translated = command(String(line[order]).trimmingCharacters(in: .whitespaces), cli: cli, version: version),
                  let whole = Range(match.range, in: line) else { return line }
            changed = true
            return line.replacingCharacters(in: whole, with: translated)
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    /// Un ordre AppleScript traduit ; nil s'il n'est pas reconnu. Les expressions restent évaluées
    /// par AppleScript (`quoted form of (…)`). O(n).
    private static func command(_ text: String, cli: String, version: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: text, range: range) else { continue }
            guard let verb = pattern.verb else {
                return pattern.order == "version" ? (text.hasPrefix("return") ? "return \"\(version)\"" : "\"\(version)\"") : "set __roadieAlfred to 0"
            }
            var parts = [#"do shell script ""# + appleScriptEscaped(BTTShortcutBindingService.shellQuote(cli)) + " workflow alfred \(verb) \""]
            for (index, group) in pattern.groups.enumerated() {
                let value = Range(match.range(at: group), in: text).map { String(text[$0]) }
                guard value != nil || verb == "search" else { continue }
                parts.append((index == 0 ? "" : #" & " " & "#) + "quoted form of (\(value ?? "\"\""))")
            }
            return parts[0] + " & " + parts.dropFirst().joined().trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: JavaScript

    private static func javaScript(_ source: String, cli: String, version: String) -> String? {
        let range = NSRange(source.startIndex..., in: source)
        guard application.firstMatch(in: source, range: range) != nil else { return nil }
        let body = application.stringByReplacingMatches(in: source, range: range, withTemplate: "__roadieAlfred")
        let quotedCLI = BTTShortcutBindingService.shellQuote(cli).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let object = #"var __roadieAlfred = (function () { var app = Application.currentApplication(); app.includeStandardAdditions = true; "#
            + #"function q(v) { return "'" + String(v === undefined || v === null ? "" : v).replace(/'/g, "'\\''") + "'"; } "#
            + #"function call(args) { return app.doShellScript(""# + quotedCLI + #" workflow alfred " + args.map(q).join(" ")); } "#
            + #"return { search: function (t) { call(["search", t]); }, "#
            + #"runTrigger: function (n, o) { o = o || {}; var a = ["trigger", o.inWorkflow, n]; if (o.withArgument !== undefined) { a.push(o.withArgument); } return call(a); }, "#
            + #"setConfiguration: function (k, o) { o = o || {}; call(["set", o.inWorkflow, k, o.toValue]); }, "#
            + #"removeConfiguration: function (k, o) { o = o || {}; call(["remove", o.inWorkflow, k]); }, "#
            + #"reloadWorkflow: function (w) { call(["reload", w]); }, revealWorkflow: function (w) { call(["reveal", w]); }, "#
            + #"version: function () { return ""# + version + #""; }, activate: function () {}, quit: function () {} }; })();"#
        // Une ligne `#!` reste la première.
        if body.hasPrefix("#!"), let end = body.firstIndex(of: "\n") {
            return String(body[...end]) + object + "\n" + body[body.index(after: end)...]
        }
        return object + "\n" + body
    }

    // MARK: Fiche (FR-006)

    /// Ordres trouvés dans un texte (scripts d'un workflow) : traduits et non traduits, noms d'Alfred,
    /// triés et sans doublon. Une simple citation (dossier de cache) n'est pas un ordre. O(n).
    static func orders(in raw: String) -> (translated: [String], untranslated: [String]) {
        // Ordre écrit dans un `-e "…"` de shell : `\"` y vaut un guillemet.
        let text = raw.replacingOccurrences(of: #"\""#, with: "\"")
        var translated = Set<String>(), untranslated = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        func note(_ order: String?, raw: String) {
            if let order { translated.insert(order) } else { untranslated.insert(raw) }
        }
        func appleOrder(_ command: String) -> String? {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"\\")))
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return patterns.first { $0.regex.firstMatch(in: trimmed, range: range) != nil }?.order
        }
        for match in oneLiner.matches(in: text, range: range) {
            guard let order = Range(match.range(at: 1), in: text) else { continue }
            let command = String(text[order]).replacingOccurrences(of: #"\""#, with: "\"")
                .components(separatedBy: "'").first ?? ""
            note(appleOrder(command), raw: command.split(separator: " ").prefix(2).joined(separator: " "))
        }
        for match in chained.matches(in: text, range: range) {
            guard let method = Range(match.range(at: 2), in: text).map({ String(text[$0]) }) else { continue }
            note(methods[method], raw: method)
        }
        for match in assigned.matches(in: text, range: range) {
            guard let variable = Range(match.range(at: 1), in: text).map({ String(text[$0]) }),
                  let calls = try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: variable) + #"\s*\.\s*(\w+)\s*\("#) else { continue }
            for call in calls.matches(in: text, range: range) {
                guard let method = Range(call.range(at: 1), in: text).map({ String(text[$0]) }) else { continue }
                note(methods[method], raw: method)
            }
        }
        return (translated.sorted(), untranslated.subtracting(translated).sorted())
    }

    // MARK: Shell (FR-003)

    private static let absoluteOsascript = try! NSRegularExpression(pattern: #"/usr/bin/osascript(?=\s)"#)

    /// Texte qui cite Alfred par une forme d'ordre : son `/usr/bin/osascript` suivi d'une espace devient
    /// celui de Roadie ; un chemin écrit dans un fichier (`</string>`) ne change pas. O(n).
    static func redirectOsascript(_ source: String, shim: String) -> String {
        let range = NSRange(source.startIndex..., in: source)
        let found = orders(in: source)
        guard !found.translated.isEmpty || !found.untranslated.isEmpty else { return source }
        return absoluteOsascript.stringByReplacingMatches(in: source, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: shim))
    }

    /// `osascript` de Roadie, en tête du `PATH` des scripts : il appelle `roadie workflow osascript`.
    /// Écrit une fois par processus ; nil si la commande `roadie` est absente. O(1).
    static let shim: String? = {
        let cli = BTTShortcutBindingService().executable
        guard FileManager.default.isExecutableFile(atPath: cli) else { return nil }
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/roadie/alfred-bridge")
        let file = folder.appendingPathComponent("osascript")
        let script = "#!/bin/sh\nexec \(BTTShortcutBindingService.shellQuote(cli)) workflow osascript \"$@\"\n"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? String(contentsOf: file, encoding: .utf8)) != script { try script.write(to: file, atomically: true, encoding: .utf8) }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch { return nil }
        return file.path
    }()

    /// Remplace le processus par `/usr/bin/osascript` : texte traduit s'il donne un ordre à Alfred,
    /// sinon les mêmes arguments. Un script compilé (`FasdUAS`) passe tel quel. Ne revient pas.
    static func execOsascript(_ args: [String], cli: String) -> Never {
        let call = OsascriptCall(args)
        var source: String?
        if !call.statements.isEmpty {
            source = call.statements.joined(separator: "\n")
        } else if let file = call.file, let data = FileManager.default.contents(atPath: file), !data.starts(with: Data("FasdUAS".utf8)) {
            source = String(data: data, encoding: .utf8)
        }
        let language: Language = call.isJavaScript ? .javaScript : .appleScript
        let final = source.flatMap { translate($0, language: language, cli: cli, version: AlfredScriptRunner.alfredVersion) }
            .map { call.rebuilt(source: $0) } ?? args
        let argv = (["/usr/bin/osascript"] + final).map { strdup($0) } + [nil]
        execv("/usr/bin/osascript", argv)
        perror("osascript")
        exit(127)
    }

    /// Options d'un appel à `osascript` : langue, instructions `-e`, autres options (`-s h`), fichier et
    /// arguments. O(a).
    struct OsascriptCall: Equatable {
        var language: String?
        var statements: [String] = []
        var options: [String] = []
        var file: String?
        var arguments: [String] = []

        init(_ args: [String]) {
            var index = 0
            while index < args.count {
                let arg = args[index]
                if arg == "-l" || arg == "-e" || arg == "-s", index + 1 < args.count {
                    switch arg {
                    case "-l": language = args[index + 1]
                    case "-e": statements.append(args[index + 1])
                    default: options += [arg, args[index + 1]]
                    }
                    index += 2
                } else if arg.hasPrefix("-"), arg != "-" {
                    options.append(arg)
                    index += 1
                } else {
                    if statements.isEmpty { file = arg; index += 1 }
                    arguments = Array(args[index...])
                    break
                }
            }
        }

        /// Arguments de `/usr/bin/osascript` avec le texte traduit à la place des `-e` ou du fichier.
        func rebuilt(source: String) -> [String] {
            (language.map { ["-l", $0] } ?? []) + options + ["-e", source] + arguments
        }

        var isJavaScript: Bool { language?.lowercased() == "javascript" || (file.map { $0.hasSuffix(".js") || $0.hasSuffix(".jxa") } ?? false) }
    }
}

/// Réglages qu'un workflow enregistre par `set configuration` (SPEC-093 FR-005) : un fichier JSON par
/// workflow, jamais dans le dossier d'Alfred ; lus après `prefs.plist`.
struct AlfredKeptSettings: Sendable {
    static let shared = AlfredKeptSettings(folder: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".roadies/workflows-settings"))
    let folder: URL

    private func file(_ workflow: String) -> URL {
        folder.appendingPathComponent(workflow.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    func values(for workflow: String) -> [String: String] {
        guard !workflow.isEmpty, let data = try? Data(contentsOf: file(workflow)) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }

    func set(_ key: String, to value: String, workflow: String) throws { try write(values(for: workflow).merging([key: value]) { $1 }, workflow) }

    func remove(_ key: String, workflow: String) throws {
        var values = values(for: workflow)
        values[key] = nil
        try write(values, workflow)
    }

    private func write(_ values: [String: String], _ workflow: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted]).write(to: file(workflow), options: .atomic)
    }

    /// Date du dossier : un fichier réécrit (écriture atomique) la change ; l'index s'en sert.
    var stamp: Date? { (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.modificationDate] as? Date }
}
