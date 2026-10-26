import Foundation

/// Effets d'un workflow sur le Mac, injectés : réels dans le démon, factices dans les tests (SPEC-088).
protocol AlfredEffects: Sendable {
    func openURL(_ url: String, browser: String?) async
    func open(path: String, with app: String?) async
    func reveal(_ paths: [String]) async
    func launch(_ paths: [String]) async
    func copy(_ text: String, paste: Bool) async
    func notify(title: String, text: String) async
    func playSound(_ name: String, system: Bool) async
    func speak(_ text: String) async
    func webSearch(_ text: String) async
    /// Rouvre la barre avec ce texte (Show Alfred, Script Filter atteint en cours de schéma).
    func showBar(_ text: String) async
    /// Journal sans saisie ni argument (FR-011).
    func log(_ type: String, _ details: [String: String])
    // Étape 2 (SPEC-089 FR-008).
    /// Touches simulées : code de touche (-1 : `character`), modificateurs d'Alfred, répétitions.
    func keyCombo(keyCode: Int, character: String, modifiers: Int, count: Int) async
    func largeType(_ text: String) async
    /// Commande lancée dans le Terminal ; dossier ouvert dans le Terminal.
    func terminal(command: String) async
    func terminal(folder: String) async
    /// Raccourci Apple ; sortie rendue (vide si aucune).
    func shortcut(_ name: String, input: String?) async -> String
    /// Boutons non vides ; rend le numéro du bouton choisi (1 à 3), nil si fermé.
    func dialog(title: String, text: String, buttons: [String]) async -> Int?
}

/// Bilan d'une exécution : étapes, briques manquantes, erreurs (sans contenu de l'utilisateur).
struct AlfredRunOutcome: Equatable, Sendable {
    var steps = 0
    var missing: [String] = []
    var errors: [String] = []
}

/// Moteur du schéma d'un workflow (SPEC-088 FR-007, FR-008) : suit les flèches depuis un objet avec
/// l'argument, les variables et les modificateurs tenus ; chaque brique produit l'argument suivant.
/// 200 étapes au plus : un schéma en boucle s'arrête. O(o + c) par exécution.
final class AlfredWorkflowEngine: @unchecked Sendable {
    static let maxSteps = 200
    /// Briques exécutées par cette version (la fiche de compatibilité s'en sert).
    static var supportedTypes: Set<String> { Set(handlers) }
    private static let handlers: [String] = [
        "action.script", "action.applescript", "action.openurl", "action.openfile", "action.revealfile",
        "action.launchfiles", "action.systemwebsearch", "output.clipboard", "output.notification", "output.playsound",
        "output.speak", "output.writefile", "utility.argument", "utility.junction", "utility.conditional",
        "utility.filter", "utility.split", "utility.joinargs", "utility.transform", "utility.replace", "utility.delay",
        "utility.random", "utility.json", "utility.hidealfred", "utility.showalfred", "utility.debug", "utility.expression",
        "input.scriptfilter", "input.keyword",
        // Étape 2 (SPEC-089).
        "trigger.hotkey", "trigger.external", "trigger.action", "trigger.universalaction", "trigger.fallback",
        "input.listfilter", "input.filefilter", "output.callexternaltrigger", "output.dispatchkeycombo", "output.largetype",
        "action.browseinterminal", "action.terminalcommand", "automation.runshortcut", "automation.task", "utility.dialog",
        "utility.file", "action.browseinalfred", "action.actioninalfred",
    ]

    let effects: AlfredEffects
    /// Workflows connus : cibles d'un appel externe vers un autre workflow (`Call External Trigger`).
    var workflows: [AlfredWorkflow] = []
    /// Dossier des tâches d'automatisation (tests : dossier d'essai).
    var tasksRoot = AlfredAutomationTasks.root

    init(effects: AlfredEffects, workflows: [AlfredWorkflow] = []) {
        self.effects = effects
        self.workflows = workflows
    }

    /// Déclencheur externe d'un workflow par son `triggerid`. O(o).
    static func externalTrigger(_ id: String, in workflow: AlfredWorkflow) -> AlfredObject? {
        workflow.objects.values.first { $0.type == "trigger.external" && $0.string("triggerid") == id }
    }

    private final class Run: @unchecked Sendable {
        var outcome = AlfredRunOutcome()
    }

    /// Ce qu'une brique rend : continuer avec un argument et des variables (et la branche d'une
    /// condition), ou s'arrêter.
    private enum Step { case next([String], [String: String], branch: String?), stop }

    func run(_ workflow: AlfredWorkflow, from uid: String, arg: [String], variables: [String: String] = [:],
             modifiers: Int = 0) async -> AlfredRunOutcome {
        let run = Run()
        let base = workflow.configuredVariables.merging(variables) { $1 }
        await follow(workflow, from: uid, input: arg, variables: base, modifiers: modifiers, branch: nil, run: run)
        effects.log("workflow.run", ["workflow": workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID,
                                      "steps": String(run.outcome.steps), "missing": run.outcome.missing.joined(separator: ","),
                                      "errors": String(run.outcome.errors.count)])
        return run.outcome
    }

    /// Exécute l'objet lui-même puis la suite (`roadie workflow run`, SPEC-089 FR-002). O(o + c).
    func start(_ workflow: AlfredWorkflow, at uid: String, arg: [String], variables: [String: String] = [:]) async -> AlfredRunOutcome {
        let run = Run()
        await execute(workflow, uid: uid, input: arg, variables: workflow.configuredVariables.merging(variables) { $1 }, run: run)
        effects.log("workflow.run", ["workflow": workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID,
                                      "steps": String(run.outcome.steps), "missing": run.outcome.missing.joined(separator: ","),
                                      "errors": String(run.outcome.errors.count)])
        return run.outcome
    }

    /// Flèches à suivre : celles du modificateur tenu s'il y en a, sinon celles sans modificateur
    /// (research R6) ; après une condition, celles de sa branche (`nil` = sinon). O(c).
    static func next(_ workflow: AlfredWorkflow, from uid: String, modifiers: Int, branch: String?, isConditional: Bool) -> [AlfredConnection] {
        var links = workflow.connections[uid] ?? []
        if isConditional { links = links.filter { $0.branch == branch } }
        let exact = links.filter { $0.modifiers == modifiers }
        return exact.isEmpty && modifiers != 0 ? links.filter { $0.modifiers == 0 } : exact
    }

    private func follow(_ workflow: AlfredWorkflow, from uid: String, input: [String], variables: [String: String],
                        modifiers: Int, branch: String?, run: Run) async {
        let isConditional = ["utility.conditional", "utility.dialog"].contains(workflow.objects[uid]?.type ?? "")
        for link in Self.next(workflow, from: uid, modifiers: modifiers, branch: branch, isConditional: isConditional) {
            await execute(workflow, uid: link.destination, input: input, variables: variables, run: run)
        }
    }

    private func execute(_ workflow: AlfredWorkflow, uid: String, input: [String], variables: [String: String], run: Run) async {
        guard run.outcome.steps < Self.maxSteps, let object = workflow.objects[uid] else { return }
        run.outcome.steps += 1
        switch await process(object, workflow: workflow, input: input, variables: variables, run: run) {
        case .stop: return
        case .next(let arg, let vars, let branch):
            await follow(workflow, from: uid, input: arg, variables: vars, modifiers: 0, branch: branch, run: run)
        }
    }

    // MARK: - Briques

    private func process(_ object: AlfredObject, workflow: AlfredWorkflow, input: [String], variables: [String: String],
                         run: Run) async -> Step {
        let query = input.joined(separator: "\t")
        let constants = AlfredScriptRunner.constants(workflow: workflow)
        func expand(_ text: String, encode: ((String) -> String)? = nil, encodeVariables: Bool = true) -> String {
            AlfredPlaceholders.expand(text, query: query, variables: variables, constants: constants, encode: encode, encodeVariables: encodeVariables)
        }
        func text(_ key: String, default fallback: String = "{query}") -> String {
            let raw = object.string(key) ?? ""
            return expand(raw.isEmpty ? fallback : raw)
        }
        let pass = Step.next(input, variables, branch: nil)
        switch object.type {
        case "action.script":
            guard let script = AlfredScript(object: object) else { return pass }
            let result = await AlfredScriptRunner.run(script, query: query, arguments: input, workflow: workflow, variables: variables)
            guard result.failure == nil, !result.timedOut else {
                run.outcome.errors.append(result.failure ?? "timeout")
                await effects.notify(title: workflow.name, text: "Script : \(result.failure ?? "délai dépassé")")
                return .stop
            }
            let output = AlfredRunScriptOutput.parse(result.text)
            return .next(output.arg, variables.merging(output.variables) { $1 }, branch: nil)
        case "action.applescript":
            var source = object.string("applescript") ?? ""
            if source.contains("alfred_script") { source += "\non run argv\nreturn alfred_script(item 1 of argv)\nend run" }
            let result = await AlfredScriptRunner.run(AlfredScript(language: 6, source: source), query: query, arguments: [query],
                                                      workflow: workflow, variables: variables)
            return .next([AlfredRunScriptOutput.parse(result.text).arg.first ?? ""], variables, branch: nil)
        case "action.openurl":
            let url = text("url").trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = AlfredPlaceholders.expand(object.string("url") ?? "{query}", query: query, variables: variables, constants: constants,
                                                    encode: object.bool("skipqueryencode") ? nil : { Self.urlEncode($0, spaces: object.string("spaces"), plus: object.bool("plusspaces")) },
                                                    encodeVariables: !object.bool("skipvarencode"))
            await effects.openURL(encoded.isEmpty ? url : encoded, browser: object.string("browser").flatMap { $0.isEmpty ? nil : $0 })
            return pass
        case "action.openfile":
            let path = Self.path(text("sourcefile"), in: workflow)
            await effects.open(path: path, with: object.string("openwith").flatMap { $0.isEmpty ? nil : $0 })
            return pass
        case "action.revealfile":
            let raw = object.string("path") ?? ""
            await effects.reveal(raw.isEmpty ? input.map { Self.path($0, in: workflow) } : [Self.path(expand(raw), in: workflow)])
            return pass
        case "action.launchfiles":
            await effects.launch((object.config["paths"]?.array ?? []).compactMap(\.string).map { Self.path(expand($0), in: workflow) })
            return pass
        case "action.systemwebsearch":
            await effects.webSearch(query)
            return pass
        case "output.clipboard":
            await effects.copy(text("clipboardtext"), paste: object.bool("autopaste"))
            return pass
        case "output.notification":
            if object.bool("onlyshowifquerypopulated"), query.isEmpty { return pass }
            var body = text("text")
            if object.bool("lastpathcomponent") { body = (body as NSString).lastPathComponent }
            if object.bool("removeextension") { body = (body as NSString).deletingPathExtension }
            await effects.notify(title: text("title", default: workflow.name), text: body)
            return pass
        case "output.playsound":
            await effects.playSound(object.string("soundname") ?? "", system: object.bool("systemsound"))
            return pass
        case "output.speak":
            await effects.speak(text("text"))
            return pass
        case "output.writefile":
            return writeFile(object, workflow: workflow, expand: { expand($0) }, input: input, variables: variables, run: run)
        case "utility.argument":
            let arg = object.bool("passthroughargument") ? input : [text("argument")]
            let assigned = (object.config["variables"]?.dict ?? [:]).compactMapValues(\.string).mapValues { expand($0) }
            return .next(arg, variables.merging(assigned) { $1 }, branch: nil)
        case "utility.junction", "utility.hidealfred":
            return pass
        case "utility.debug":
            effects.log("workflow.debug", ["workflow": workflow.id, "variables": String(variables.count)])
            return pass
        case "utility.conditional":
            for condition in object.config["conditions"]?.array ?? [] {
                let raw = condition["inputstring"]?.string ?? ""
                let subject = raw.isEmpty ? query : expand(raw)
                if Self.test(subject, mode: condition["matchmode"]?.int ?? 0, against: expand(condition["matchstring"]?.string ?? ""),
                             caseSensitive: condition["matchcasesensitive"]?.bool ?? false) {
                    return .next(input, variables, branch: condition["uid"]?.string)
                }
            }
            return .next(input, variables, branch: nil)
        case "utility.filter":
            let raw = object.string("inputstring") ?? ""
            let subject = raw.isEmpty ? query : expand(raw)
            let mode = object.int("matchmode") ?? 0
            let matched = Self.test(subject, mode: mode == 2 ? 4 : mode == 1 ? 7 : 0, against: expand(object.string("matchstring") ?? ""),
                                    caseSensitive: object.bool("matchcasesensitive"))
            return matched ? pass : .stop
        case "utility.split":
            let delimiter = Self.unescape(object.string("delimiter") ?? "\t")
            var parts = query.components(separatedBy: delimiter.isEmpty ? "\t" : delimiter)
            if object.bool("trimarguments") { parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            if object.bool("discardemptyarguments") { parts = parts.filter { !$0.isEmpty } }
            var vars = variables
            let prefix = object.string("variableprefix") ?? "split"
            for (index, part) in parts.enumerated() { vars["\(prefix)\(index + 1)"] = part }
            return .next(parts, vars, branch: nil)
        case "utility.joinargs":
            return .next([input.joined(separator: Self.unescape(object.string("delimiter") ?? ""))], variables, branch: nil)
        case "utility.transform":
            guard (object.int("type") ?? 0) == 0 else { return missing("utility.transform:\(object.int("type") ?? -1)", workflow, run) }
            return .next(input.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, variables, branch: nil)
        case "utility.replace":
            let pattern = expand(object.string("matchstring") ?? ""), replacement = expand(object.string("replacestring") ?? "")
            guard !pattern.isEmpty else { return pass }
            let replaced = input.map { value -> String in
                guard (object.int("matchmode") ?? 0) == 1 else { return value.replacingOccurrences(of: pattern, with: replacement) }
                var options: NSRegularExpression.Options = []
                if object.bool("regexcaseinsensitive") { options.insert(.caseInsensitive) }
                if object.bool("regexmultiline") { options.insert(.anchorsMatchLines) }
                guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return value }
                return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement)
            }
            return .next(replaced, variables, branch: nil)
        case "utility.delay":
            let seconds = min(30, max(0, Double(text("seconds", default: "0").replacingOccurrences(of: ",", with: ".")) ?? 0))
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            return pass
        case "utility.random":
            guard (object.int("type") ?? 2) == 2 else { return missing("utility.random:\(object.int("type") ?? -1)", workflow, run) }
            let words = expand(object.string("words") ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
            return .next([words.randomElement() ?? ""], variables, branch: nil)
        case "utility.json":
            // Les remplacements entrent dans des chaînes JSON : échappés comme tels.
            let json = AlfredPlaceholders.expand(object.string("json") ?? "", query: query, variables: variables, constants: constants,
                                                 encode: Self.jsonEscape, encodeVariables: true)
            let output = AlfredRunScriptOutput.parse(json)
            return .next(json.contains("\"arg\"") ? output.arg : input, variables.merging(output.variables) { $1 }, branch: nil)
        case "utility.expression":
            let expression = expand(object.string("expression") ?? "")
            guard let value = LauncherCalculator.evaluate("=" + expression, locale: Locale(identifier: "en_US_POSIX")) else {
                run.outcome.errors.append("expression")
                return .stop
            }
            return .next([value.text], variables, branch: nil)
        case "utility.showalfred":
            await effects.showBar(text("argument"))
            return .stop
        case "input.scriptfilter", "input.keyword":
            // Entrée atteinte en cours de schéma : la barre se rouvre sur son mot-clé.
            let keyword = expand(object.string("keyword") ?? "")
            await effects.showBar(keyword.isEmpty ? query : "\(keyword) \(query)")
            return .stop
        // MARK: Étape 2 (SPEC-089)
        case "trigger.hotkey", "trigger.external", "trigger.action", "trigger.universalaction", "trigger.fallback":
            // Déclencheur atteint par une flèche : il passe la main tel quel.
            return pass
        case "input.listfilter", "input.filefilter":
            let keyword = expand(object.string("keyword") ?? "")
            await effects.showBar(keyword.isEmpty ? query : "\(keyword) \(query)")
            return .stop
        case "output.callexternaltrigger":
            let target = object.string("workflowbundleid") ?? "self"
            let destination = target == "self" || target.isEmpty ? workflow
                : workflows.first { $0.bundleID == target || $0.id == target }
            guard let destination, let trigger = Self.externalTrigger(object.string("externaltriggerid") ?? "", in: destination) else {
                run.outcome.errors.append("externaltrigger")
                return .stop
            }
            let arg = (object.config["passinputasargument"]?.bool ?? true) ? input : []
            let vars = (object.config["passvariables"]?.bool ?? false) ? variables : destination.configuredVariables
            await follow(destination, from: trigger.uid, input: arg, variables: vars, modifiers: 0, branch: nil, run: run)
            return .stop
        case "output.dispatchkeycombo":
            await effects.keyCombo(keyCode: object.int("keycode") ?? -1, character: object.string("keychar") ?? "",
                                   modifiers: object.int("keymod") ?? 0, count: max(1, min(50, object.int("count") ?? 1)))
            return pass
        case "output.largetype":
            await effects.largeType(text("largetypetext"))
            return pass
        case "action.browseinterminal":
            let raw = object.string("path") ?? ""
            await effects.terminal(folder: Self.path(raw.isEmpty ? query : expand(raw), in: workflow))
            return pass
        case "action.terminalcommand":
            let command = AlfredPlaceholders.expand(object.string("script") ?? "", query: AlfredScriptRunner.escape(query, bits: object.int("escaping") ?? 0),
                                                    variables: variables, constants: constants)
            await effects.terminal(command: command)
            return pass
        case "automation.runshortcut":
            let output = await effects.shortcut(expand(object.string("shortcut") ?? ""), input: (object.int("inputmode") ?? 1) == 0 ? nil : query)
            return .next((object.int("outputmode") ?? 0) == 0 ? [output] : input, variables, branch: nil)
        case "automation.task":
            let uid = object.string("taskuid") ?? ""
            guard let task = AlfredAutomationTasks.task(uid, root: tasksRoot) else {
                return missing("tâche absente : \(uid) (roadie workflow tasks update)", workflow, run)
            }
            let settings = (object.config["tasksettings"]?.dict ?? [:]).mapValues { value -> String in
                if case .bool(let flag) = value { return flag ? "1" : "0" }
                return expand(value.string ?? "")
            }
            let result = await AlfredAutomationTasks.run(task, settings: settings, input: input, workflow: workflow, variables: variables)
            guard result.failure == nil, !result.timedOut else {
                run.outcome.errors.append(result.failure ?? "timeout")
                return .stop
            }
            let output = AlfredRunScriptOutput.parse(result.text)
            return .next(output.arg, variables.merging(output.variables) { $1 }, branch: nil)
        case "utility.dialog":
            let buttons = ["button1", "button2", "button3"].map { expand(object.string($0) ?? "") }
            guard let chosen = await effects.dialog(title: text("title", default: workflow.name), text: text("description", default: ""),
                                                    buttons: buttons) else { return .stop }
            return .next(input, variables, branch: "_button\(chosen)")
        case "utility.file":
            // Type (UTI) du fichier reçu : en argument et, si un nom est donné, en variable.
            let uti = (try? URL(fileURLWithPath: query).resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? ""
            var vars = variables
            if let name = object.string("fileutivariablename"), !name.isEmpty { vars[name] = uti }
            return .next(object.bool("outputfileuti") ? [uti] : input, vars, branch: nil)
        case "action.browseinalfred", "action.actioninalfred":
            // Barre rouverte sur le chemin : mode chemin (SPEC-087), → y ouvre ses verbes.
            let raw = object.string("path") ?? ""
            let path = raw.isEmpty ? query : expand(raw)
            await effects.showBar((path as NSString).abbreviatingWithTildeInPath)
            return .stop
        default:
            return missing(object.type, workflow, run)
        }
    }

    private func missing(_ type: String, _ workflow: AlfredWorkflow, _ run: Run) -> Step {
        run.outcome.missing.append(type)
        let effects = effects
        Task { await effects.notify(title: workflow.name, text: "Roadie ne prend pas encore en charge : \(type)") }
        return .stop
    }

    private func writeFile(_ object: AlfredObject, workflow: AlfredWorkflow, expand: (String) -> String,
                           input: [String], variables: [String: String], run: Run) -> Step {
        var path = Self.path(expand(object.string("filename") ?? ""), in: workflow)
        guard !path.isEmpty else { return .stop }
        if object.bool("adduuid") {
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
            path = url.deletingLastPathComponent().appendingPathComponent(url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)").path
        }
        let content = expand(object.string("filetext") ?? "{query}")
        guard !content.isEmpty || object.config["allowemptyfiles"]?.bool != false else { return .stop }
        let folder = (path as NSString).deletingLastPathComponent
        if object.config["createintermediatefolders"]?.bool ?? true {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        // Type 2 : ajout à la fin ; 1 (et 0, non observé) : remplacement (relevé du corpus).
        if object.int("type") == 2, let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(content.utf8))
            try? handle.close()
        } else if (try? Data(content.utf8).write(to: URL(fileURLWithPath: path))) == nil {
            run.outcome.errors.append("writefile")
            return .stop
        }
        return .next([path], variables, branch: nil)
    }

    // MARK: - Outils purs

    /// Conditions d'Alfred (relevé du corpus) : 0 égal, 1 différent, 2 plus grand, 3 plus petit,
    /// 4 expression régulière, 5 vide, 6 non vide, 7 contient. O(n).
    static func test(_ value: String, mode: Int, against expected: String, caseSensitive: Bool) -> Bool {
        let a = caseSensitive ? value : value.lowercased(), b = caseSensitive ? expected : expected.lowercased()
        switch mode {
        case 0: return a == b
        case 1: return a != b
        case 2, 3:
            if let x = Double(value.trimmingCharacters(in: .whitespaces)), let y = Double(expected.trimmingCharacters(in: .whitespaces)) {
                return mode == 2 ? x > y : x < y
            }
            return mode == 2 ? a > b : a < b
        case 4:
            guard let regex = try? NSRegularExpression(pattern: expected, options: caseSensitive ? [] : [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        case 5: return value.isEmpty
        case 6: return !value.isEmpty
        case 7: return a.contains(b)
        default: return false
        }
    }

    /// Chemin relatif : dans le dossier du workflow ; `~` développé.
    static func path(_ raw: String, in workflow: AlfredWorkflow) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        return expanded.hasPrefix("/") ? expanded : workflow.folder.appendingPathComponent(expanded).path
    }

    static func urlEncode(_ text: String, spaces: String?, plus: Bool) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        if plus { return encoded.replacingOccurrences(of: "%20", with: "+") }
        if let spaces, !spaces.isEmpty { return encoded.replacingOccurrences(of: "%20", with: spaces) }
        return encoded
    }

    static func jsonEscape(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return text }
        return String(json.dropFirst(2).dropLast(2))
    }

    /// `\t`, `\n` tapés dans un champ de délimiteur.
    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\n", with: "\n")
    }
}
