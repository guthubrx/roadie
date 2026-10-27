import Foundation

/// Icône d'une ligne de Script Filter : image, icône d'un fichier, ou icône d'un type (UTI).
enum AlfredIcon: Equatable, Sendable {
    case image(String), fileIcon(String), fileType(String)
}

/// Ce que fait une ligne quand un modificateur est tenu (`mods` d'Alfred).
struct AlfredMod: Equatable, Sendable {
    var arg: [String]?
    var subtitle: String?
    var valid: Bool?
    var variables: [String: String] = [:]
}

/// Ligne rendue par un Script Filter (SPEC-088 FR-005).
struct AlfredItem: Equatable, Sendable {
    var uid: String?
    var title: String
    var subtitle = ""
    var arg: [String] = []
    var icon: AlfredIcon?
    var valid = true
    var match: String?
    var autocomplete: String?
    var isFile = false
    var mods: [Int: AlfredMod] = [:]
    var copyText: String?
    var largeText: String?
    var quickLookURL: String?
    var variables: [String: String] = [:]
}

/// Réponse d'un Script Filter : lignes, variables, relance périodique, apprentissage désactivé.
struct AlfredScriptFilterResponse: Equatable, Sendable {
    var items: [AlfredItem] = []
    var variables: [String: String] = [:]
    var rerun: Double?
    var skipKnowledge = false
    /// Grille (SPEC-092 FR-007) : `uid` de la tuile choisie à l'ouverture.
    var preselect: String?

    /// JSON d'Alfred, sinon ancien format XML `<items>` ; nil si ni l'un ni l'autre. O(n).
    static func parse(_ data: Data) -> AlfredScriptFilterResponse? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return parse(json: json) }
        return AlfredXMLItems.parse(data)
    }

    static func parse(json: [String: Any]) -> AlfredScriptFilterResponse {
        var response = AlfredScriptFilterResponse()
        response.variables = strings(json["variables"])
        response.rerun = (json["rerun"] as? NSNumber)?.doubleValue.clamped(to: 0.1...5)
        response.skipKnowledge = (json["skipknowledge"] as? Bool) ?? false
        response.preselect = (json["preselect"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        response.items = (json["items"] as? [[String: Any]] ?? []).compactMap(item)
        return response
    }

    private static func item(_ json: [String: Any]) -> AlfredItem? {
        guard let title = json["title"].map(text) else { return nil }
        var item = AlfredItem(title: title)
        item.uid = json["uid"].map(text)
        item.subtitle = json["subtitle"].map(text) ?? ""
        item.arg = args(json["arg"])
        item.valid = (json["valid"] as? Bool) ?? ((json["valid"] as? String).map { $0 != "no" && $0 != "false" } ?? true)
        item.match = json["match"] as? String
        item.autocomplete = json["autocomplete"].map(text)
        item.isFile = (json["type"] as? String)?.hasPrefix("file") ?? false
        item.quickLookURL = json["quicklookurl"] as? String
        item.variables = strings(json["variables"])
        if let icon = json["icon"] as? [String: Any], let path = icon["path"] as? String {
            switch icon["type"] as? String {
            case "fileicon": item.icon = .fileIcon(path)
            case "filetype": item.icon = .fileType(path)
            default: item.icon = .image(path)
            }
        }
        if let text = json["text"] as? [String: Any] {
            item.copyText = text["copy"] as? String
            item.largeText = text["largetype"] as? String
        }
        for (key, value) in json["mods"] as? [String: [String: Any]] ?? [:] {
            let bits = key.split(separator: "+").map { AlfredWorkflow.modifierBits[String($0)] ?? 0 }
            guard !bits.contains(0) else { continue }
            var mod = AlfredMod()
            if value["arg"] != nil { mod.arg = args(value["arg"]) }
            mod.subtitle = value["subtitle"] as? String
            mod.valid = value["valid"] as? Bool
            mod.variables = strings(value["variables"])
            item.mods[bits.reduce(0, +)] = mod
        }
        return item
    }

    private static func text(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    /// `arg` : texte, nombre, ou liste (plusieurs arguments, comme Alfred).
    static func args(_ value: Any?) -> [String] {
        switch value {
        case let list as [Any]: list.map(text)
        case nil: []
        case let single?: [text(single)]
        }
    }

    static func strings(_ value: Any?) -> [String: String] {
        (value as? [String: Any] ?? [:]).mapValues(text)
    }

    /// « Alfred filtre les résultats » (research R1 de la 088) : `match` sinon le titre. Modes : 0 début
    /// d'un mot (défaut), 1 début de la phrase, 2 mots dans n'importe quel ordre, 3 mots dans l'ordre. O(i × m).
    static func filter(_ items: [AlfredItem], query: String, mode: Int) -> [AlfredItem] {
        let words = LauncherMatch.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let text = LauncherMatch.fold(item.match ?? item.title)
            let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            switch mode {
            case 1: return text.hasPrefix(words.joined(separator: " "))
            case 2: return words.allSatisfy { word in tokens.contains { $0.hasPrefix(word) } }
            case 3:
                var rest = tokens[...]
                for word in words {
                    guard let index = rest.firstIndex(where: { $0.hasPrefix(word) }) else { return false }
                    rest = rest[rest.index(after: index)...]
                }
                return true
            default:
                let phrase = words.joined(separator: " ")
                return text.hasPrefix(phrase) || text.contains(" " + phrase) || tokens.contains { $0.hasPrefix(phrase) }
            }
        }
    }
}

/// Sortie d'un Run Script : JSON `{"alfredworkflow": {arg, variables, config}}`, sinon le texte, un
/// seul saut de ligne final retiré. O(n).
enum AlfredRunScriptOutput {
    static func parse(_ text: String) -> (arg: [String], variables: [String: String], config: [String: Any]) {
        if text.contains("alfredworkflow"), let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let payload = json["alfredworkflow"] as? [String: Any] {
            return (AlfredScriptFilterResponse.args(payload["arg"]), AlfredScriptFilterResponse.strings(payload["variables"]),
                    payload["config"] as? [String: Any] ?? [:])
        }
        var value = text
        if value.hasSuffix("\n") { value.removeLast() }
        return ([value], [:], [:])
    }
}

/// Ancien format XML d'Alfred : `<items><item uid arg valid autocomplete type><title/><subtitle mod/>
/// <icon type/><arg/><text type/></item></items>`. O(n).
private final class AlfredXMLItems: NSObject, XMLParserDelegate {
    private var items: [AlfredItem] = []
    private var current: AlfredItem?
    private var element = ""
    private var attributes: [String: String] = [:]
    private var buffer = ""
    private var sawItems = false

    static func parse(_ data: Data) -> AlfredScriptFilterResponse? {
        let delegate = AlfredXMLItems()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawItems else { return nil }
        return AlfredScriptFilterResponse(items: delegate.items)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        element = name
        self.attributes = attributes
        buffer = ""
        switch name {
        case "items": sawItems = true
        case "item":
            var item = AlfredItem(title: "")
            item.uid = attributes["uid"]
            if let arg = attributes["arg"] { item.arg = [arg] }
            item.valid = !["no", "false"].contains(attributes["valid"]?.lowercased() ?? "yes")
            item.autocomplete = attributes["autocomplete"]
            item.isFile = attributes["type"]?.hasPrefix("file") ?? false
            current = item
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": current?.title = value
        case "subtitle":
            if let key = attributes["mod"], let bits = AlfredWorkflow.modifierBits[key] {
                current?.mods[bits, default: AlfredMod()].subtitle = value
            } else { current?.subtitle = value }
        case "arg": current?.arg = [value]
        case "icon":
            switch attributes["type"] {
            case "fileicon": current?.icon = .fileIcon(value)
            case "filetype": current?.icon = .fileType(value)
            default: current?.icon = .image(value)
            }
        case "text":
            if attributes["type"] == "copy" { current?.copyText = value } else if attributes["type"] == "largetype" { current?.largeText = value }
        case "item":
            if let current { items.append(current) }
            current = nil
        default: break
        }
        buffer = ""
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
