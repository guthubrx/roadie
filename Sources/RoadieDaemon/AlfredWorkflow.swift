import AppKit
import Foundation

/// Valeur d'une liste de propriétés (plist) gardée telle quelle (SPEC-088) : chaque brique d'un
/// workflow lit les clés qu'elle connaît, le reste est ignoré sans perte.
enum PlistValue: Equatable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool), array([PlistValue]), dict([String: PlistValue]), data(Data), date(Date)

    init?(_ any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) }
            else if CFNumberIsFloatType(value) { self = .double(value.doubleValue) }
            else { self = .int(value.intValue) }
        case let value as [Any]: self = .array(value.compactMap(PlistValue.init))
        case let value as [String: Any]: self = .dict(value.compactMapValues(PlistValue.init))
        case let value as Data: self = .data(value)
        case let value as Date: self = .date(value)
        default: return nil
        }
    }

    var string: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "1" : "0"
        default: nil
        }
    }

    var int: Int? {
        switch self {
        case .int(let value): value
        // Une valeur plist hors de la plage de Int ne doit pas arrêter le démon.
        case .double(let value): Int(exactly: value.rounded(.towardZero))
        case .bool(let value): value ? 1 : 0
        case .string(let value): Int(value.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .string(let value): ["1", "true", "yes"].contains(value.lowercased())
        default: nil
        }
    }

    var array: [PlistValue]? { if case .array(let value) = self { value } else { nil } }
    var dict: [String: PlistValue]? { if case .dict(let value) = self { value } else { nil } }
    subscript(key: String) -> PlistValue? { dict?[key] }

    /// Valeur JSON équivalente (sortie `alfredworkflow`, configuration JSON). O(n).
    var any: Any {
        switch self {
        case .string(let v): v
        case .int(let v): v
        case .double(let v): v
        case .bool(let v): v
        case .array(let v): v.map(\.any)
        case .dict(let v): v.mapValues(\.any)
        case .data(let v): v.base64EncodedString()
        case .date(let v): ISO8601DateFormatter().string(from: v)
        }
    }
}

/// Objet d'un workflow : `type` sans le préfixe « alfred.workflow. » (« input.scriptfilter »).
struct AlfredObject: Equatable, Sendable {
    let uid: String
    let type: String
    let config: [String: PlistValue]

    func string(_ key: String) -> String? { config[key]?.string }
    func int(_ key: String) -> Int? { config[key]?.int }
    func bool(_ key: String) -> Bool { config[key]?.bool ?? false }
}

/// Flèche du schéma ; `modifiers` : 0, ⌘ 1048576, ⌥ 524288, ⌃ 262144, ⇧ 131072, fn 8388608 (sommes).
/// `branch` : condition d'une brique Conditional dont part la flèche (`sourceoutputuid`).
struct AlfredConnection: Equatable, Sendable {
    let destination: String
    let modifiers: Int
    let branch: String?
}

/// Réglage déclaré par le workflow (`userconfigurationconfig`), avec sa valeur par défaut.
struct AlfredUserSetting: Equatable, Sendable {
    let variable: String
    let type: String
    let defaultValue: String
}

/// Workflow d'Alfred lu sur le disque (SPEC-088, research R2).
struct AlfredWorkflow: Equatable, Sendable {
    enum Source: String, Sendable { case alfred, roadie }

    /// Nom du dossier : identifiant stable, même sans `bundleid`.
    let id: String
    let bundleID: String
    let name: String
    let description: String
    let version: String
    let folder: URL
    let source: Source
    let disabled: Bool
    let objects: [String: AlfredObject]
    let connections: [String: [AlfredConnection]]
    let variables: [String: String]
    let userSettings: [AlfredUserSetting]
    /// Valeurs saisies par l'utilisateur dans Alfred (`prefs.plist`).
    let prefs: [String: String]

    /// Modificateurs d'Alfred, par nom de la clé `mods` d'un Script Filter.
    static let modifierBits: [String: Int] = ["cmd": 1_048_576, "alt": 524_288, "ctrl": 262_144, "shift": 131_072, "fn": 8_388_608]

    /// Variables du workflow, puis défauts des réglages, puis valeurs de l'utilisateur. O(v).
    var configuredVariables: [String: String] {
        var result = variables
        for setting in userSettings where !setting.variable.isEmpty { result[setting.variable] = setting.defaultValue }
        for (key, value) in prefs { result[key] = value }
        return result
    }

    /// Icône du workflow, ou d'un de ses objets (`<uid>.png`), si le fichier existe.
    func icon(for uid: String? = nil) -> String? {
        if let uid {
            let path = folder.appendingPathComponent("\(uid).png").path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let path = folder.appendingPathComponent("icon.png").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Lit `info.plist` (et `prefs.plist`) d'un dossier de workflow ; nil s'il n'en est pas un. O(o + c).
    static func load(folder: URL, source: Source) -> AlfredWorkflow? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("info.plist")),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              case .dict(let plist)? = PlistValue(raw) else { return nil }
        var objects: [String: AlfredObject] = [:]
        for case .dict(let object) in plist["objects"]?.array ?? [] {
            guard let uid = object["uid"]?.string, let type = object["type"]?.string else { continue }
            let short = type.hasPrefix("alfred.workflow.") ? String(type.dropFirst("alfred.workflow.".count)) : type
            objects[uid] = AlfredObject(uid: uid, type: short, config: object["config"]?.dict ?? [:])
        }
        var connections: [String: [AlfredConnection]] = [:]
        for (source, links) in plist["connections"]?.dict ?? [:] {
            connections[source] = (links.array ?? []).compactMap { link in
                guard let destination = link["destinationuid"]?.string else { return nil }
                return AlfredConnection(destination: destination, modifiers: link["modifiers"]?.int ?? 0,
                                        branch: link["sourceoutputuid"]?.string)
            }
        }
        let settings: [AlfredUserSetting] = (plist["userconfigurationconfig"]?.array ?? []).compactMap { setting in
            guard let variable = setting["variable"]?.string else { return nil }
            return AlfredUserSetting(variable: variable, type: setting["type"]?.string ?? "",
                                     defaultValue: setting["config"]?["default"]?.string ?? "")
        }
        var prefs: [String: String] = [:]
        if let data = try? Data(contentsOf: folder.appendingPathComponent("prefs.plist")),
           let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
           case .dict(let values)? = PlistValue(raw) {
            for (key, value) in values { if let text = value.string { prefs[key] = text } }
        }
        return AlfredWorkflow(
            id: folder.lastPathComponent, bundleID: plist["bundleid"]?.string ?? "", name: plist["name"]?.string ?? folder.lastPathComponent,
            description: plist["description"]?.string ?? "", version: plist["version"]?.string ?? "", folder: folder, source: source,
            disabled: plist["disabled"]?.bool ?? false, objects: objects, connections: connections,
            variables: (plist["variables"]?.dict ?? [:]).compactMapValues(\.string), userSettings: settings, prefs: prefs)
    }
}

/// Remplacements d'Alfred dans un texte de configuration : `{query}`, `{var:nom}`, `{const:nom}`,
/// `{allvars}`, `{date}`, `{time}`, `{datetime}`, `{clipboard}`. Un nom inconnu devient vide. O(n).
enum AlfredPlaceholders {
    static func expand(_ text: String, query: String, variables: [String: String], constants: [String: String] = [:],
                       encode: ((String) -> String)? = nil, encodeVariables: Bool = true, now: Date = Date()) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { result += rest[open...]; return result }
            let token = String(rest[rest.index(after: open)..<close])
            // Un texte JSON a ses propres accolades : seul un nom sans accolade ni espace est un remplacement.
            if !token.contains("{"), !token.contains(" "),
               let value = value(token, query: query, variables: variables, constants: constants, now: now) {
                let isVariable = token.hasPrefix("var:")
                result += (token == "query" || (isVariable && encodeVariables)) ? (encode?(value) ?? value) : value
                rest = rest[rest.index(after: close)...]
            } else {
                result += "{"
                rest = rest[rest.index(after: open)...]
            }
        }
        return result + rest
    }

    private static func value(_ token: String, query: String, variables: [String: String], constants: [String: String], now: Date) -> String? {
        if token == "query" { return query }
        if token.hasPrefix("var:") { return variables[String(token.dropFirst(4))] ?? "" }
        if token.hasPrefix("const:") { return constants[String(token.dropFirst(6))] ?? "" }
        // Historique du presse-papiers d'Alfred : seul le contenu actuel (0) existe hors d'Alfred.
        if token.hasPrefix("clipboard:") { return token == "clipboard:0" ? NSPasteboard.general.string(forType: .string) ?? "" : "" }
        let formatter = DateFormatter()
        switch token {
        case "allvars":
            let data = (try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        case "date": formatter.dateStyle = .medium; formatter.timeStyle = .none; return formatter.string(from: now)
        case "time": formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter.string(from: now)
        case "datetime": formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter.string(from: now)
        case "clipboard": return NSPasteboard.general.string(forType: .string) ?? ""
        default: return nil
        }
    }
}
