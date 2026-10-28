import Foundation

/// Vue Texte d'un workflow (session 117), brique `userinterface.text` d'Alfred 5.5 : texte à lire, à modifier ou
/// Markdown rendu, rempli par l'argument reçu, un fichier ou un script relancé. Logique pure ; la fenêtre est
/// `WorkflowTextPanel`. Retour envoie le texte entier à la suite du schéma, depuis cette brique.
struct AlfredTextView: Equatable, Sendable {
    /// « Behaviour » d'Alfred, dans l'ordre de son menu (`AlfredWorkflowUserInterfaceText.nib`).
    enum Behaviour: Int, Sendable { case selectable = 0, editable = 1, markdown = 2 }
    /// « Script Input » : champ de saisie au-dessus ou au-dessous du texte, qui relance le script.
    enum InputPlacement: Int, Sendable { case none = 0, above = 1, below = 2 }

    var workflowID: String
    var objectUID: String
    var title: String
    /// Dossier où chercher une image Markdown donnée par un chemin relatif.
    var folder: String
    var behaviour = Behaviour.selectable
    var inputPlacement = InputPlacement.none
    /// « Font » : 0 système, 1 thème, 2 chasse fixe.
    var monospaced = false
    var footer = ""
    var loadingText: String?
    /// Script de la brique (« Script Source »), chemin dans le dossier du workflow ; nil pour l'argument ou un fichier.
    var scriptFile: String?
    /// Saisie du premier passage du script : l'argument reçu par la brique.
    var initialInput: String?
    var variables: [String: String] = [:]
    /// Morceaux de texte, un par réponse : `append`, `prepend` et `replacelast` en ont besoin.
    var chunks: [String] = []
    var scroll = AlfredTextResponse.Scroll.auto
    /// Relance du script dans ce délai (0,1 à 5 s), avec la même saisie.
    var rerun: Double?
    var clearsInput = true
    /// `actionoutput` : la vue se ferme et envoie la réponse à la suite.
    var actionOutput = false

    /// Texte montré : les réponses séparées par une ligne vide. O(n).
    var text: String { chunks.joined(separator: "\n\n") }

    /// Vue d'une brique : réglages de l'objet. O(1).
    static func make(object: AlfredObject, workflow: AlfredWorkflow, variables: [String: String]) -> AlfredTextView {
        var view = AlfredTextView(workflowID: workflow.id, objectUID: object.uid, title: workflow.name, folder: workflow.folder.path)
        view.behaviour = Behaviour(rawValue: object.int("behaviour") ?? 0) ?? .selectable
        view.inputPlacement = InputPlacement(rawValue: object.int("scriptinput") ?? 0) ?? .none
        view.monospaced = object.int("fontmode") == 2
        view.footer = object.string("footertext") ?? ""
        let loading = (object.string("loadingtext") ?? "").trimmingCharacters(in: .whitespaces)
        view.loadingText = loading.isEmpty ? "Loading…" : loading
        view.variables = variables
        return view
    }

    /// Applique une réponse du script : contenu, pied, variables, relance. O(n).
    mutating func apply(_ response: AlfredTextResponse) {
        switch response.mode {
        case .replace: chunks = [response.response]
        case .append: chunks.append(response.response)
        case .prepend: chunks.insert(response.response, at: 0)
        case .replacelast:
            if chunks.isEmpty { chunks = [response.response] } else { chunks[chunks.count - 1] = response.response }
        }
        if let footer = response.footer { self.footer = footer }
        variables.merge(response.variables) { $1 }
        scroll = response.scroll
        rerun = response.rerun
        clearsInput = response.clearsInput
        actionOutput = response.actionOutput
        loadingText = nil
    }
}

/// Vue Image ou PDF d'un workflow (session 118), briques `userinterface.image` et `userinterface.pdf` : le fichier
/// reçu en argument, montré dans une fenêtre ; Retour envoie son chemin à la suite du schéma.
struct AlfredMediaView: Equatable, Sendable {
    enum Kind: String, Sendable { case image, pdf }
    /// « Image Size » d'Alfred : 0 automatique (réduite à la fenêtre), 1 ajustée au cadre, 2 sans tenir compte de la
    /// résolution (pixels réels).
    enum ImageSize: Int, Sendable { case automatic = 0, fit = 1, ignoreDPI = 2 }
    /// « Display Mode » d'Alfred : 0 automatique, 1 une page, 2 une page continue, 3 deux pages, 4 deux pages continues.
    enum PDFMode: Int, Sendable { case automatic = 0, singlePage, singlePageContinuous, twoPages, twoPagesContinuous }

    var kind: Kind
    var workflowID: String
    var objectUID: String
    var title: String
    var path: String
    var imageSize = ImageSize.automatic
    var pdfMode = PDFMode.automatic
    var variables: [String: String] = [:]

    /// O(1).
    static func make(_ kind: Kind, object: AlfredObject, workflow: AlfredWorkflow, path: String, variables: [String: String]) -> AlfredMediaView {
        var view = AlfredMediaView(kind: kind, workflowID: workflow.id, objectUID: object.uid, title: workflow.name, path: path)
        view.imageSize = ImageSize(rawValue: object.int("imageresizemode") ?? 0) ?? .automatic
        view.pdfMode = PDFMode(rawValue: object.int("displaymode") ?? 0) ?? .automatic
        view.variables = variables
        return view
    }
}

/// Réponse JSON d'un script de vue Texte (aide d'Alfred, « Text View JSON Format »). Une sortie qui n'est pas
/// ce JSON devient le texte lui-même.
struct AlfredTextResponse: Equatable, Sendable {
    enum Mode: String, Sendable { case replace, append, prepend, replacelast }
    enum Scroll: String, Sendable { case auto, start, end }

    var response: String
    var footer: String?
    var mode = Mode.replace
    var scroll = Scroll.auto
    var clearsInput = true
    var actionOutput = false
    var variables: [String: String] = [:]
    var rerun: Double?

    /// O(n).
    static func parse(_ output: String) -> AlfredTextResponse {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String else { return AlfredTextResponse(response: output) }
        var response = AlfredTextResponse(response: text)
        response.footer = json["footer"] as? String
        response.actionOutput = json["actionoutput"] as? Bool ?? false
        let behaviour = json["behaviour"] as? [String: Any] ?? [:]
        response.mode = (behaviour["response"] as? String).flatMap(Mode.init(rawValue:)) ?? .replace
        response.scroll = (behaviour["scroll"] as? String).flatMap(Scroll.init(rawValue:)) ?? .auto
        response.clearsInput = (behaviour["inputfield"] as? String) != "select"
        response.variables = (json["variables"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String ?? ($0 as? NSNumber)?.stringValue }
        // Comme le `rerun` d'un Script Filter : 0,1 à 5 secondes.
        response.rerun = (json["rerun"] as? NSNumber).map { min(5, max(0.1, $0.doubleValue)) }
        return response
    }
}

/// Markdown d'une vue Texte, découpé en blocs simples pour l'affichage : titres, citations, listes, code,
/// images, paragraphes ; la mise en forme dans une ligne (gras, italique, code, liens) reste à `AttributedString`.
/// Pur et testable. O(n) lignes.
enum AlfredMarkdown {
    enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case quote(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
        case image(alt: String, path: String)
        case rule
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code { blocks.append(.code(open.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let heading = heading(line) { flush(); blocks.append(heading); continue }
            if ["---", "***", "___"].contains(line) { flush(); blocks.append(.rule); continue }
            if let image = image(line) { flush(); blocks.append(image); continue }
            if line.hasPrefix(">") { flush(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { flush(); blocks.append(.bullet(String(line.dropFirst(2)))); continue }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...])))
                continue
            }
            paragraph.append(line)
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
    }

    /// Ligne faite d'une seule image `![alt](chemin)`.
    private static func image(_ line: String) -> Block? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "]("),
              line.index(line.startIndex, offsetBy: 2) <= close.lowerBound else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let path = String(line[close.upperBound..<line.index(before: line.endIndex)])
        return path.isEmpty ? nil : .image(alt: alt, path: path)
    }

    /// Chemin d'une image : absolu, `~`, `file://`, ou relatif au dossier donné. O(1).
    static func imagePath(_ raw: String, folder: String) -> String {
        if let url = URL(string: raw), url.isFileURL { return url.path }
        let expanded = NSString(string: raw).expandingTildeInPath
        return expanded.hasPrefix("/") ? expanded : (folder as NSString).appendingPathComponent(expanded)
    }
}
