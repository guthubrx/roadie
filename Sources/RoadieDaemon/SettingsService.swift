import Foundation
import RoadieCore
import TOMLKit

extension Notification.Name {
    /// Écriture validée : les composants visibles peuvent se redessiner sans attendre le watcher.
    public static let roadieSettingsDidChange = Notification.Name("roadie.settings.didChange")
}

public enum SettingChangeResult: Equatable, Sendable {
    case applied(old: SettingValue, new: SettingValue)
    case rejected(reason: String)
}

public struct SettingsValidity: Equatable, Sendable {
    public var path: String
    public var isValid: Bool
    public var errorCount: Int
    public var warningCount: Int
    public var messages: [String]
}

/// Fichier de configuration présent mais illisible (encodage autre que UTF-8, droits).
public struct SettingsFileError: Error, Equatable, Sendable {
    public let message: String
}

/// Lit et modifie les réglages du catalogue dans `roadies.toml` (research R5, R10).
/// Les scalaires conservent leur texte source ; TOMLKit lit les collections.
/// Une écriture passe par un fichier candidat validé dans le même dossier, puis un `rename` atomique.
/// `@unchecked Sendable` : les écritures sont sérialisées par un verrou interne.
public final class SettingsService: @unchecked Sendable {
    /// Instance du daemon, partagée par la boîte, le lanceur et la fenêtre : une seule sauvegarde
    /// `roadies.toml.bak-…` par session. Les autres constructeurs servent aux tests.
    public static let shared = SettingsService()

    public let configPath: String
    private let eventLog: EventLog
    private let afterWrite: @Sendable () -> Void
    private let lock = NSLock()
    /// Sauvegarde déjà faite par cette instance (une seule par session).
    private var hasBackup = false
    /// Point d'injection des tests : appelé juste avant la relecture qui précède le remplacement.
    var beforeReplace: (() -> Void)?

    public init(
        configPath: String = RoadieConfigLoader.defaultConfigPath(),
        eventLog: EventLog? = nil,
        afterWrite: @escaping @Sendable () -> Void = { _ = ConfigReloadService.shared.currentConfig() }
    ) {
        self.configPath = configPath
        self.eventLog = eventLog ?? EventLog()
        self.afterWrite = afterWrite
    }

    // MARK: - Lecture

    static let unreadableMessage = tr("le fichier de configuration n'est pas lisible en UTF-8", "the configuration file is not readable as UTF-8")

    /// Contenu du fichier : absent = "" ; présent mais illisible = échec (l'écriture refuse alors tout).
    public func readConfig() -> Result<String, SettingsFileError> {
        guard FileManager.default.fileExists(atPath: configPath) else { return .success("") }
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return .failure(SettingsFileError(message: Self.unreadableMessage))
        }
        return .success(text)
    }

    /// Contenu pour l'affichage ; fichier absent ou illisible = "". L'écriture utilise `readConfig()`.
    public func configText() -> String {
        (try? readConfig().get()) ?? ""
    }

    /// Valeur du fichier, ou défaut si la clé est absente ou illisible. Complexité : O(L), L = taille du fichier.
    public func value(of descriptor: SettingDescriptor) -> (value: SettingValue, isDefault: Bool) {
        value(of: descriptor, in: configText())
    }

    /// Même règle sur un texte déjà lu. `isDefault` : la valeur effective égale le défaut (ligne absente
    /// ou valeur identique au défaut). Un alias de choix est rendu sous sa forme du catalogue. O(L).
    public func value(of descriptor: SettingDescriptor, in text: String) -> (value: SettingValue, isDefault: Bool) {
        if descriptor.collection != nil {
            guard let current = try? collection(of: descriptor, in: text).get(), let spec = descriptor.collection else {
                return (descriptor.defaultValue, true)
            }
            return (.string(SettingsCollectionCodec.summary(current)), current == spec.defaultValue)
        }
        guard descriptor.readOnlyReason == nil,
              let literal = ConfigFileEditor.literal(in: literalIndex(text), table: descriptor.tablePath, key: descriptor.key),
              var value = Self.parse(literal, kind: descriptor.kind)
        else { return (descriptor.defaultValue, true) }
        if case .string(let choice) = value { value = .string(SettingsCatalog.canonicalChoice(choice, for: descriptor.id)) }
        return (value, value == descriptor.defaultValue)
    }

    /// Index des littéraux du dernier texte lu (session 107) : une recherche large lit 230 valeurs dans le
    /// même texte. Reconstruit seulement quand le texte change. O(L) par texte, puis O(1) par valeur.
    private let indexLock = NSLock()
    private var indexedText: String?
    private var indexedLiterals: [String: String] = [:]

    private func literalIndex(_ text: String) -> [String: String] {
        indexLock.lock()
        defer { indexLock.unlock() }
        if indexedText != text {
            indexedLiterals = ConfigFileEditor.literalIndex(text)
            indexedText = text
        }
        return indexedLiterals
    }

    /// Champs qui nomment une entrée d'un tableau de tables, par ordre de préférence.
    private static let entryNameFields = ["display_name", "name", "id", "stage_id"]

    /// Valeur actuelle d'une entrée en lecture seule (FR-017) : texte de la liste sur une ligne, ou
    /// « N entrée(s) » pour un tableau de tables (avec les 5 premiers noms). O(L).
    public func readOnlySummary(of descriptor: SettingDescriptor, in text: String) -> String {
        let path = descriptor.tablePath.isEmpty ? descriptor.key : "\(descriptor.tablePath).\(descriptor.key)"
        let entries = ConfigFileEditor.arrayTables(text, table: path)
        guard entries.isEmpty else {
            let names = entries.compactMap { entry in
                Self.entryNameFields.lazy.compactMap { entry[$0] }.first.map { Self.unquoted($0) ?? $0 }
            }
            var summary = tr("\(entries.count) entrée(s)", "\(entries.count) entry(ies)")
            if !names.isEmpty {
                summary += " : " + names.prefix(5).joined(separator: ", ") + (names.count > 5 ? ", …" : "")
            }
            return summary
        }
        return ConfigFileEditor.readRawValue(text, table: descriptor.tablePath, key: descriptor.key)
            ?? tr("(aucune valeur dans le fichier)", "(no value in the file)")
    }

    /// « target_grid.rows = 4 (défaut 3, de 2 à 12) » ; nil si le nom est inconnu.
    public func describe(_ id: String) -> String? {
        guard let descriptor = SettingsCatalog.find(id: id) else { return nil }
        if let reason = descriptor.readOnlyReason { return "\(id) : \(reason)" }
        let current = Self.display(value(of: descriptor).value)
        var detail = tr("défaut \(Self.display(descriptor.defaultValue))", "default \(Self.display(descriptor.defaultValue))")
        if let constraint = Self.constraint(descriptor.kind) { detail += ", \(constraint)" }
        return "\(id) = \(current) (\(detail))"
    }

    public func validity() -> SettingsValidity {
        let items = RoadieConfigLoader.validate(path: configPath).items
        let errors = items.filter { $0.level == .error }.count
        return SettingsValidity(
            path: configPath,
            isValid: errors == 0,
            errorCount: errors,
            warningCount: items.filter { $0.level == .warning }.count,
            messages: items.filter { $0.level != .ok }.map { "\($0.path) : \($0.message)" }
        )
    }

    // MARK: - Écriture

    public func set(_ id: String, to raw: String) -> SettingChangeResult {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor = SettingsCatalog.find(id: id) else {
            return reject("unknown", tr("réglage inconnu : \(id)", "unknown setting: \(id)"))
        }
        if descriptor.id == "overview.hotkey", !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           TargetModeConfig.hotkeyParts(OverviewConfig(hotkey: raw).hotkey) == nil {
            return reject(id, tr("Enregistrez une combinaison avec un modificateur et une touche, ou laissez vide.", "Record a combination with a modifier and a key, or leave empty."))
        }
        if descriptor.collection != nil { return reject(id, tr("Utilise l’éditeur intégré de cette collection.", "Use this collection's built-in editor.")) }
        if let reason = descriptor.readOnlyReason { return reject(id, reason) }
        switch Self.convert(SettingsCatalog.canonicalChoice(raw, for: id), kind: descriptor.kind) {
        case .failure(let error): return reject(id, error.message)
        case .success(let (literal, value)): return write(descriptor, literal: literal, newValue: value)
        }
    }

    /// Retire la ligne de la clé : le défaut redevient effectif.
    public func reset(_ id: String) -> SettingChangeResult {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor = SettingsCatalog.find(id: id) else {
            return reject("unknown", tr("réglage inconnu : \(id)", "unknown setting: \(id)"))
        }
        if descriptor.collection != nil { return resetCollectionLocked(descriptor) }
        if let reason = descriptor.readOnlyReason { return reject(id, reason) }
        return write(descriptor, literal: nil, newValue: descriptor.defaultValue)
    }

    /// Séquence R5 : lecture, édition, validation du fichier de départ puis du candidat, sauvegarde,
    /// relecture (une reprise), `rename`, rechargement, journal. Un lien symbolique est suivi : la cible
    /// est remplacée, le lien reste. Complexité : O(L) par tentative (au plus deux), plus deux validations.
    private func write(_ descriptor: SettingDescriptor, literal: String?, newValue: SettingValue) -> SettingChangeResult {
        transaction(id: descriptor.id) { original in
            switch ConfigFileEditor.edit(original, table: descriptor.tablePath, key: descriptor.key, value: literal) {
            case .failure(let error): return .failure(SettingsFileError(message: Self.message(error)))
            case .success(let text): return .success((text, self.value(of: descriptor, in: original).value, newValue))
            }
        }
    }

    /// Unique point de remplacement pour scalaires, collections et réparation complète du fichier.
    private func transaction(id: String, allowInvalidOriginal: Bool = false, strictConflict: Bool = false,
                             transform: (String) -> Result<(String, SettingValue, SettingValue), SettingsFileError>) -> SettingChangeResult {
        let fileManager = FileManager.default
        let link = URL(fileURLWithPath: configPath)
        // Le candidat doit naître dans le dossier de la cible réelle : `rename` ne traverse pas les volumes
        // et, fait sur le lien, il remplacerait le lien par un fichier.
        let target = link.resolvingSymlinksInPath()
        let directory = target.deletingLastPathComponent()
        // Le radical identifie le candidat ; la validation des règles générées utilise explicitement configPath.
        let stem = target.deletingPathExtension().lastPathComponent

        for attempt in 1...2 {
            guard case .success(let original) = readConfig() else {
                return reject(id, tr("\(Self.unreadableMessage) : aucune modification", "\(Self.unreadableMessage): no change"))
            }
            let candidateText: String
            let old: SettingValue
            let newValue: SettingValue
            switch transform(original) {
            case .failure(let error): return reject(id, error.message)
            case .success(let change): (candidateText, old, newValue) = change
            }
            // Rien à écrire (rétablir une clé déjà absente).
            if candidateText == original {
                if allowInvalidOriginal, let reason = candidateErrors(configPath) {
                    return reject(id, reason)
                }
                return applied(id, old: old, new: newValue)
            }
            let start = RoadieConfigLoader.validate(path: configPath).items.filter { $0.level == .error }
            guard allowInvalidOriginal || start.isEmpty else {
                return reject(id, tr("le fichier de configuration est invalide : corrige-le d'abord (\(start.count) erreur(s))", "the configuration file is invalid: fix it first (\(start.count) error(s))"))
            }

            let candidate = directory.appendingPathComponent("\(stem).candidate-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: candidate) }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try candidateText.write(to: candidate, atomically: false, encoding: .utf8)
                try Self.copyAttributes(from: target, to: candidate)
            } catch {
                return reject(id, tr("écriture impossible : \(error.localizedDescription)", "cannot write: \(error.localizedDescription)"))
            }
            if let reason = candidateErrors(candidate.path) {
                return reject(id, reason)
            }

            // Sauvegarde à côté du chemin configuré (purgée par `FileAdministration.configBackupActions`),
            // copiée depuis la cible réelle. Retirée si cette tentative n'écrit rien.
            var backup: URL?
            if !hasBackup, fileManager.fileExists(atPath: target.path) {
                let url = link.deletingLastPathComponent()
                    .appendingPathComponent("\(link.lastPathComponent).bak-\(Self.timestamp())")
                do { try fileManager.copyItem(at: target, to: url) } catch {
                    return reject(id, tr("écriture impossible : \(error.localizedDescription)", "cannot write: \(error.localizedDescription)"))
                }
                backup = url
            }
            // Relecture juste avant le `rename`, sous le verrou de `set`/`reset` : protège contre une
            // écriture externe faite pendant la préparation. Fenêtre résiduelle incompressible : une écriture
            // externe entre cette relecture et le `rename` est perdue (aucun verrou de fichier n'est partagé
            // avec les éditeurs ; le `rename` remplace le fichier en une opération).
            beforeReplace?()
            guard case .success(let latest) = readConfig(), latest == original else {
                if let backup { try? fileManager.removeItem(at: backup) }
                if strictConflict || attempt == 2 { return reject(id, tr("le fichier a changé pendant l'écriture", "the file changed while writing")) }
                continue
            }
            guard rename(candidate.path, target.path) == 0 else {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                if let backup { try? fileManager.removeItem(at: backup) }
                return reject(id, tr("écriture impossible : \(error.localizedDescription)", "cannot write: \(error.localizedDescription)"))
            }
            if backup != nil { hasBackup = true }
            afterWrite()
            NotificationCenter.default.post(name: .roadieSettingsDidChange, object: nil, userInfo: ["configPath": configPath, "settingID": id])
            // Les composants modulaires vivent dans des processus distincts du propriétaire des paramètres.
            DistributedNotificationCenter.default().postNotificationName(
                .roadieSettingsDidChange, object: nil,
                userInfo: ["configPath": configPath, "settingID": id], deliverImmediately: true
            )
            return applied(id, old: old, new: newValue)
        }
        return reject(id, tr("le fichier a changé pendant l'écriture", "the file changed while writing"))
    }

    /// Mode POSIX du fichier d'origine (0644 pour un fichier créé) et, si le processus en a le droit,
    /// son propriétaire et son groupe, posés sur le candidat avant le `rename`.
    private static func copyAttributes(from target: URL, to candidate: URL) throws {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: target.path) else {
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: candidate.path)
            return
        }
        if let mode = attributes[.posixPermissions] {
            try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: candidate.path)
        }
        let owner = attributes.filter { $0.key == .ownerAccountID || $0.key == .groupOwnerAccountID }
        try? fileManager.setAttributes(owner, ofItemAtPath: candidate.path)
    }

    /// Décode le candidat puis valide ses règles avec les règles générées du chemin configuré.
    private func candidateErrors(_ candidate: String) -> String? {
        var errors = RoadieConfigLoader.validate(path: candidate).items.filter { $0.level == .error }
        // Le nom temporaire du candidat n'a pas le même voisin .generated.toml.
        // Utiliser le chemin configuré, comme ConfigReloadService, même si c'est un lien symbolique.
        if errors.isEmpty {
            do {
                let raw = FileManager.default.fileExists(atPath: candidate)
                    ? try String(contentsOfFile: candidate, encoding: .utf8) : ""
                let config = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
                let generatedPath = RoadieConfigLoader.generatedRulesPath(for: configPath)
                let generated = try RoadieConfigLoader.loadRulesFile(from: generatedPath)
                errors += WindowRuleValidator.validate(config.rules + generated)
            } catch {
                // Le détail du parseur pourrait contenir une valeur ; le journal conserve seulement l'identifiant.
                return tr("le fichier deviendrait invalide : les règles ne peuvent pas être lues", "the file would become invalid: the rules cannot be read")
            }
        }
        guard !errors.isEmpty else { return nil }
        let lines = errors.map { $0.path == candidate ? $0.message : "\($0.path) : \($0.message)" }
        return tr("le fichier deviendrait invalide : ", "the file would become invalid: ") + lines.joined(separator: " ; ")
    }

    // MARK: - Journal (nom et résultat seulement, jamais la valeur : R10)

    private func applied(_ id: String, old: SettingValue, new: SettingValue) -> SettingChangeResult {
        log(id, result: "applied")
        return .applied(old: old, new: new)
    }

    private func reject(_ id: String, _ reason: String) -> SettingChangeResult {
        log(id, result: "rejected")
        return .rejected(reason: reason)
    }

    private func log(_ id: String, result: String) {
        eventLog.append(RoadieEvent(type: "settings.changed", details: ["setting": id, "result": result]))
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

// MARK: - Conversions

extension SettingsService {
    struct ConversionError: Error {
        let message: String
    }

    private static let trueWords: Set<String> = ["true", "oui", "on", "1"]
    private static let falseWords: Set<String> = ["false", "non", "off", "0"]

    /// Texte saisi → littéral TOML et valeur (contracts/settings.md). O(n) sur la saisie (et la liste de choix).
    static func convert(_ raw: String, kind: SettingKind) -> Result<(String, SettingValue), ConversionError> {
        let text = raw.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .bool:
            let word = text.lowercased()
            if trueWords.contains(word) { return .success(("true", .bool(true))) }
            if falseWords.contains(word) { return .success(("false", .bool(false))) }
            return .failure(ConversionError(message: tr("valeur attendue : true, false, oui, non, on, off, 1 ou 0", "expected value: true, false, yes, no, on, off, 1 or 0")))
        case .int(let range):
            guard let number = Int(text) else {
                return .failure(ConversionError(message: tr("nombre entier attendu", "whole number expected") + rangeSuffix(range.map(display))))
            }
            if let range, !range.contains(number) {
                return .failure(ConversionError(message: tr("valeur hors plage : de \(range.lowerBound) à \(range.upperBound)", "value out of range: from \(range.lowerBound) to \(range.upperBound)")))
            }
            return .success((String(number), .int(number)))
        case .double(let range):
            guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite,
                  text.allSatisfy({ $0.isNumber || "+-.,eE".contains($0) })
            else {
                return .failure(ConversionError(message: tr("nombre attendu", "number expected") + rangeSuffix(range.map(display))))
            }
            if let range, !range.contains(number) {
                return .failure(ConversionError(message: tr("valeur hors plage : de \(display(range.lowerBound)) à \(display(range.upperBound))", "value out of range: from \(display(range.lowerBound)) to \(display(range.upperBound))")))
            }
            return .success((String(number), .double(number)))
        case .choice(let choices):
            guard let choice = choices.first(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) else {
                return .failure(ConversionError(message: tr("choix possibles : ", "possible choices: ") + choices.joined(separator: ", ")))
            }
            return .success((quoted(choice), .string(choice)))
        case .color:
            // ASCII seulement : `isHexDigit` accepte aussi les chiffres pleine chasse, illisibles par `NSColor(hex:)`.
            let digits = text.dropFirst()
            guard text.hasPrefix("#"), digits.count == 6 || digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                return .failure(ConversionError(message: tr("couleur attendue : #RRGGBB ou #RRGGBBAA", "color expected: #RRGGBB or #RRGGBBAA")))
            }
            return .success((quoted(text), .string(text)))
        case .text:
            guard !text.contains(where: \.isNewline) else {
                return .failure(ConversionError(message: tr("le texte ne doit pas contenir de saut de ligne", "the text must not contain a line break")))
            }
            return .success((quoted(text), .string(text)))
        }
    }

    /// Littéral lu dans le fichier → valeur ; nil si illisible pour ce type. O(n) sur le littéral.
    static func parse(_ literal: String, kind: SettingKind) -> SettingValue? {
        switch kind {
        case .bool:
            return literal == "true" ? .bool(true) : literal == "false" ? .bool(false) : nil
        case .int:
            return Int(literal.replacingOccurrences(of: "_", with: "")).map(SettingValue.int)
        case .double:
            return Double(literal.replacingOccurrences(of: "_", with: "")).map(SettingValue.double)
        case .choice, .color, .text:
            return unquoted(literal).map(SettingValue.string)
        }
    }

    /// Chaîne TOML entre guillemets, `"` et `\` échappés.
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Contenu d'une chaîne TOML d'une ligne : `'…'` tel quel, `"…"` avec ses échappements. O(n).
    private static func unquoted(_ literal: String) -> String? {
        guard literal.count >= 2, let quote = literal.first, quote == literal.last, quote == "\"" || quote == "'" else { return nil }
        let body = literal.dropFirst().dropLast()
        guard quote == "\"" else { return String(body) }
        var result = ""
        var iterator = body.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else { result.append(character); continue }
            switch iterator.next() {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "b": result.append("\u{08}")
            case "f": result.append("\u{0C}")
            case let escape? where escape == "u" || escape == "U":
                let hex = String((0..<(escape == "u" ? 4 : 8)).compactMap { _ in iterator.next() })
                guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else { return nil }
                result.unicodeScalars.append(scalar)
            case let other?: result.append(other)
            case nil: return nil
            }
        }
        return result
    }

    // MARK: - Textes

    static func display(_ value: SettingValue) -> String {
        switch value {
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let number): return String(number)
        case .double(let number): return display(number)
        case .string(let text): return text
        case .unset: return tr("non défini", "not set")
        }
    }

    /// `13.0` → « 13 », `0.1` → « 0.1 ».
    private static func display(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
    }

    static func display(_ range: ClosedRange<Int>) -> String {
        tr("de \(range.lowerBound) à \(range.upperBound)", "from \(range.lowerBound) to \(range.upperBound)")
    }

    static func display(_ range: ClosedRange<Double>) -> String {
        tr("de \(display(range.lowerBound)) à \(display(range.upperBound))", "from \(display(range.lowerBound)) to \(display(range.upperBound))")
    }

    private static func rangeSuffix(_ range: String?) -> String {
        range.map { " (\($0))" } ?? ""
    }

    private static func constraint(_ kind: SettingKind) -> String? {
        switch kind {
        case .int(let range?): return display(range)
        case .double(let range?): return display(range)
        case .choice(let choices): return tr("choix : ", "choices: ") + choices.joined(separator: ", ")
        default: return nil
        }
    }

    static func message(_ error: ConfigEditError) -> String {
        let prefix = tr("modification automatique impossible : ", "automatic change impossible: ")
        switch error {
        case .multilineValue(let line): return prefix + tr("valeur sur plusieurs lignes ou liste (ligne \(line))", "multi-line value or list (line \(line))")
        case .dottedKey(let line): return prefix + tr("clé en notation pointée (ligne \(line))", "dotted key (line \(line))")
        case .inlineTable(let line): return prefix + tr("table en ligne (ligne \(line))", "inline table (line \(line))")
        case .duplicateKey(let line): return prefix + tr("clé présente deux fois (ligne \(line))", "key present twice (line \(line))")
        case .duplicateTable: return prefix + tr("table présente deux fois", "table present twice")
        case .unterminatedString(let line): return prefix + tr("guillemet non fermé (ligne \(line))", "unclosed quote (line \(line))")
        case .ambiguousInsertion: return prefix + tr("fin de fichier dans une valeur ouverte", "end of file inside an open value")
        }
    }
}

// MARK: - Collections et correction intégrée du document

extension SettingsService {
    public func collection(of descriptor: SettingDescriptor) -> Result<CollectionValue, SettingsFileError> {
        readConfig().flatMap { collection(of: descriptor, in: $0) }
    }

    public func collection(of descriptor: SettingDescriptor, in text: String) -> Result<CollectionValue, SettingsFileError> {
        do { return .success(try SettingsCollectionCodec.read(descriptor, text: text)) }
        catch let error as SettingsFileError { return .failure(error) }
        catch { return .failure(SettingsFileError(message: tr("Le fichier TOML ne peut pas être lu.", "The TOML file cannot be read."))) }
    }

    public func validateCollection(_ descriptor: SettingDescriptor, value: CollectionValue) -> [String: String] {
        guard let spec = descriptor.collection else { return ["collection": tr("Collection inconnue.", "Unknown collection.")] }
        var errors = SettingsCollectionCodec.validate(spec, value: value)
        if descriptor.id == "switcher.shortcuts", case .rows(let rows) = value {
            if rows.count > WindowSwitcherConfig.maxShortcuts {
                errors["collection"] = tr("Neuf profils au maximum. Supprime un profil avant d'en ajouter un autre.", "Nine profiles at most. Delete a profile before adding another.")
            }
            for (index, row) in rows.enumerated() {
                if row.fields["release_action"] == .string("search"), row.fields["search_visibility"] == .string("never") {
                    errors["\(index).search_visibility"] = tr("Le mode Recherche nécessite un champ de recherche visible.", "Search mode needs a visible search field.")
                }
            }
            let requests = rows.enumerated().compactMap { index, row -> WindowSwitcherHotkeyRequest? in
                guard row.fields["enabled"] != .bool(false), row.fields["trigger_source"] != .string("external") else { return nil }
                let raw = row.fields["hotkey"].map(Self.display) ?? ""
                return WindowSwitcherHotkeyRequest(profileID: String(index), hotkey: raw)
            }
            // Validation pure : les caractères simples sont distingués sans lire la disposition système.
            let keys = Set(requests.compactMap { $0.hotkey.split(separator: "+").last.map(String.init) }.filter { $0.count == 1 })
            let layout = Dictionary(uniqueKeysWithValues: keys.sorted().enumerated().map { (UInt32(1024 + $0.offset), $0.element.lowercased()) })
            let plan = WindowSwitcherHotkeyPlan(requests: requests, layout: layout)
            for issue in plan.issues {
                let parts = issue.split(separator: ":")
                guard parts.count >= 2 else { continue }
                errors["\(parts[1]).hotkey"] = parts[0] == "collision"
                    ? tr("Ce raccourci, ou sa variante Maj, est déjà utilisé par un autre profil.", "This shortcut, or its Shift variant, is already used by another profile.")
                    : tr("Combinaison invalide. Exemple : ctrl+alt+tab. Laisse vide pour utiliser seulement la commande.", "Invalid combination. Example: ctrl+alt+tab. Leave empty to use only the command.")
            }
        }
        if errors.isEmpty, descriptor.id == "rules", case .rows(let rows) = value {
            do {
                // La prévalidation pure ignore les indices source et ne lit aucun fichier utilisateur.
                let fresh = rows.map { CollectionRow(fields: $0.fields) }
                let text = try SettingsCollectionWriter.edit("", descriptor: descriptor, value: .rows(fresh))
                let config = try TOMLDecoder().decode(RoadieConfig.self, from: text)
                for item in WindowRuleValidator.validate(config.rules) {
                    let key = item.path.replacingOccurrences(of: "rules[", with: "").replacingOccurrences(of: "].", with: ".")
                    errors[key] = item.message
                }
            } catch { errors["collection"] = tr("Les règles ne peuvent pas être lues.", "The rules cannot be read.") }
        }
        return errors
    }

    public func setCollection(_ id: String, _ value: CollectionValue, expected: CollectionValue? = nil) -> SettingChangeResult {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor = SettingsCatalog.find(id: id), descriptor.collection != nil else {
            return reject(id, tr("Collection inconnue : \(id).", "Unknown collection: \(id)."))
        }
        let errors = validateCollection(descriptor, value: value)
        guard errors.isEmpty else { return reject(id, errors.keys.sorted().compactMap { errors[$0] }.joined(separator: " ; ")) }
        return transaction(id: id, strictConflict: expected != nil) { original in
            do {
                let old = try self.collection(of: descriptor, in: original).get()
                if let expected, expected != old { return .failure(SettingsFileError(message: tr("La collection a changé. Recharge-la avant de modifier.", "The collection changed. Reload it before changing it."))) }
                if old == value { return .success((original, .string(SettingsCollectionCodec.summary(old)), .string(SettingsCollectionCodec.summary(value)))) }
                let text = try SettingsCollectionWriter.edit(original, descriptor: descriptor, value: value)
                return .success((text, .string(SettingsCollectionCodec.summary(old)), .string(SettingsCollectionCodec.summary(value))))
            } catch let error as SettingsFileError { return .failure(error) }
            catch { return .failure(SettingsFileError(message: tr("La collection ne peut pas être modifiée.", "The collection cannot be changed."))) }
        }
    }

    public func resetCollection(_ id: String) -> SettingChangeResult {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor = SettingsCatalog.find(id: id), descriptor.collection != nil else { return reject(id, tr("Collection inconnue : \(id).", "Unknown collection: \(id).")) }
        return resetCollectionLocked(descriptor)
    }

    private func resetCollectionLocked(_ descriptor: SettingDescriptor) -> SettingChangeResult {
        transaction(id: descriptor.id) { original in
            do {
                let old = try self.collection(of: descriptor, in: original).get()
                let text = try SettingsCollectionWriter.edit(original, descriptor: descriptor, value: nil)
                return .success((text, .string(SettingsCollectionCodec.summary(old)), descriptor.defaultValue))
            } catch let error as SettingsFileError { return .failure(error) }
            catch { return .failure(SettingsFileError(message: tr("La collection ne peut pas être rétablie.", "The collection cannot be restored."))) }
        }
    }

    /// Le texte original exact protège aussi la réparation d'un document actuellement invalide.
    public func replaceConfigText(_ text: String, expectedOriginal: String) -> SettingChangeResult {
        lock.lock()
        defer { lock.unlock() }
        return transaction(id: "*", allowInvalidOriginal: true, strictConflict: true) { original in
            guard original == expectedOriginal else { return .failure(SettingsFileError(message: tr("Le fichier a changé. Recharge-le avant de modifier.", "The file changed. Reload it before changing it."))) }
            return .success((text, .string("Configuration"), .string("Configuration")))
        }
    }
}
