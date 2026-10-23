import Foundation
import TOMLKit

/// Lecture sémantique avec TOMLKit ; l'écriture conserve séparément le texte source.
enum SettingsCollectionCodec {
    static func node(_ root: TOMLTable, path: [String]) -> (any TOMLValueConvertible)? {
        var current: (any TOMLValueConvertible)? = root
        for key in path { current = current?.table?[key] }
        return current
    }

    static func scalar(_ value: any TOMLValueConvertible, kind: SettingKind) -> SettingValue? {
        switch kind {
        case .bool: return value.bool.map(SettingValue.bool)
        case .int: return value.int.map(SettingValue.int)
        case .double:
            return (value.double ?? value.int.map(Double.init)).map(SettingValue.double)
        case .text, .color, .choice: return value.string.map(SettingValue.string)
        }
    }

    static func read(_ descriptor: SettingDescriptor, text: String) throws -> CollectionValue {
        guard let spec = descriptor.collection else { throw SettingsFileError(message: "Ce réglage n'est pas une collection.") }
        let root = try TOMLTable(string: text)
        let path = (descriptor.tablePath.isEmpty ? [] : descriptor.tablePath.components(separatedBy: ".")) + [descriptor.key]
        guard let value = node(root, path: path) else { return spec.defaultValue }
        switch spec.shape {
        case .list(let kind, _, _, _, _):
            guard let array = value.array else { throw SettingsFileError(message: "Liste attendue pour \(descriptor.id).") }
            let values = try array.map { item in
                guard let result = scalar(item, kind: kind) else { throw SettingsFileError(message: "Type invalide dans \(descriptor.id).") }
                return result
            }
            return .list(values)
        case .rows(_, let fields, _, _):
            guard let array = value.array else { throw SettingsFileError(message: "Tableau de lignes attendu pour \(descriptor.id).") }
            return .rows(try array.enumerated().map { index, item in
                guard let table = item.table else { throw SettingsFileError(message: "Ligne invalide dans \(descriptor.id).") }
                var values: [String: SettingValue] = [:]
                for field in fields {
                    let key = field.path.joined(separator: ".")
                    if let raw = node(table, path: field.path) {
                        guard let result = scalar(raw, kind: field.kind) else { throw SettingsFileError(message: "Type invalide : \(key).") }
                        values[key] = result
                    } else if descriptor.id == "switcher.shortcuts", key == "trigger_source" {
                        let keyText = table["hotkey"]?.string ?? ""
                        values[key] = .string(keyText.isEmpty ? "external" : "roadie")
                    } else { values[key] = field.defaultValue }
                }
                return CollectionRow(fields: values, sourceIndex: index)
            })
        case .advanced(let table): return .advanced(ConfigFileEditor.collectionFragment(text, table: table))
        }
    }

    static func summary(_ value: CollectionValue) -> String {
        switch value {
        case .list(let values): return values.map(SettingsService.display).joined(separator: ", ")
        case .rows(let rows): return "\(rows.count) entrée(s)"
        case .advanced(let text): return text.isEmpty ? "Aucune entrée" : "Structure avancée"
        }
    }

    static func literal(_ value: SettingValue, kind: SettingKind) throws -> String {
        guard value != .unset else { throw SettingsFileError(message: "Valeur manquante.") }
        // Conversion stricte : évite de transformer une chaîne en nombre ou inversement.
        let validType: Bool
        switch (kind, value) {
        case (.bool, .bool), (.int, .int), (.double, .double), (.double, .int),
             (.text, .string), (.color, .string), (.choice, .string): validType = true
        default: validType = false
        }
        guard validType else { throw SettingsFileError(message: "Type de valeur incorrect.") }
        switch SettingsService.convert(SettingsService.display(value), kind: kind) {
        case .success(let converted): return converted.0
        case .failure(let error): throw SettingsFileError(message: error.message)
        }
    }

    static func validate(_ spec: CollectionSpec, value: CollectionValue) -> [String: String] {
        var errors: [String: String] = [:]
        switch (spec.shape, value) {
        case (.list(let kind, _, let minCount, let unique, let sorted), .list(let values)):
            if values.count < minCount { errors["collection"] = "Au moins \(minCount) élément(s) sont nécessaires." }
            for (index, item) in values.enumerated() {
                do { _ = try literal(item, kind: kind) } catch { errors[String(index)] = (error as? SettingsFileError)?.message ?? error.localizedDescription }
                if unique, values[..<index].contains(item) { errors[String(index)] = "Valeur déjà présente." }
                if sorted, index > 0, case .double(let current) = item,
                   case .double(let previous) = values[index - 1], previous > current {
                    errors[String(index)] = "Les valeurs doivent être dans l'ordre croissant."
                }
            }
        case (.rows(_, let fields, let uniqueKey, let oneOf), .rows(let rows)):
            var keys: [SettingValue] = []
            var indices: Set<Int> = []
            for (index, row) in rows.enumerated() {
                if let source = row.sourceIndex, source < 0 || !indices.insert(source).inserted {
                    errors["\(index)"] = "Identifiant de ligne source invalide ou utilisé deux fois."
                }
                for field in fields {
                    let key = field.path.joined(separator: ".")
                    let item = row.fields[key] ?? .unset
                    if item == .unset || (field.required && item == .string("")) {
                        if field.required { errors["\(index).\(key)"] = "Ce champ est obligatoire." }
                    } else {
                        do { _ = try literal(item, kind: field.kind) } catch { errors["\(index).\(key)"] = (error as? SettingsFileError)?.message ?? error.localizedDescription }
                    }
                }
                for group in oneOf where !group.contains(where: { row.fields[$0] != nil && row.fields[$0] != .unset && row.fields[$0] != .string("") }) {
                    errors["\(index).\(group[0])"] = "Renseigne au moins un de ces champs : " + group.joined(separator: ", ")
                }
                if let key = uniqueKey, let value = row.fields[key], value != .unset {
                    if keys.contains(value) { errors["\(index).\(key)"] = "Identifiant déjà utilisé." }
                    keys.append(value)
                }
            }
        case (.advanced(let table), .advanced(let text)):
            do {
                let root = try TOMLTable(string: text)
                if root.keys.isEmpty { return [:] }
                let path = table.components(separatedBy: ".")
                var current = root
                for part in path.dropLast() {
                    guard Set(current.keys).isSubset(of: [part]), let child = current[part]?.table else {
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
                        errors["collection"] = "Ce fragment doit contenir uniquement \(table)."; return errors
                    }
                    current = child
                }
                if !Set(current.keys).isSubset(of: [path.last!]) { errors["collection"] = "Ce fragment doit contenir uniquement \(table)." }
            } catch { errors["collection"] = "Le fragment TOML est invalide." }
        default: errors["collection"] = "Format de collection incorrect."
        }
        return errors
    }
}
