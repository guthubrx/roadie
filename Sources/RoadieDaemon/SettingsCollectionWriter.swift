import Foundation
import RoadieCore
import TOMLKit

enum SettingsCollectionWriter {
    static func edit(_ original: String, descriptor: SettingDescriptor, value: CollectionValue?) throws -> String {
        guard let spec = descriptor.collection else { throw SettingsFileError(message: tr("Collection inconnue.", "Unknown collection.")) }
        switch spec.shape {
        case .list(let kind, _, _, _, _):
            let literal: String?
            if let value {
                guard case .list(let items) = value else { throw SettingsFileError(message: tr("Liste attendue.", "List expected.")) }
                literal = "[" + (try items.map { try SettingsCollectionCodec.literal($0, kind: kind) }).joined(separator: ", ") + "]"
            } else { literal = nil }
            return try result(ConfigFileEditor.editStructuredValue(original, table: descriptor.tablePath, key: descriptor.key, value: literal))
        case .advanced(let table):
            guard value != nil else { return try result(ConfigFileEditor.replaceCollectionSections(original, table: table, fragments: [])) }
            guard case .advanced(let text) = value! else { throw SettingsFileError(message: tr("Fragment TOML attendu.", "TOML fragment expected.")) }
            var fragment = text
            let path = table.components(separatedBy: ".")
            let parent = path.dropLast().joined(separator: ".")
            if ConfigFileEditor.readRawValue(text, table: parent, key: path.last!) != nil {
                // Un fragment compact [signals] hooks={...} devient une sous-table indépendante.
                let root = try TOMLTable(string: text)
                if let node = SettingsCollectionCodec.node(root, path: path) {
                    func expand(_ value: any TOMLValueConvertible) {
                        if let child = value.table {
                            child.inline = false
                            for key in child.keys { if let nested = child[key] { expand(nested) } }
                        } else if let array = value.array { for child in array { expand(child) } }
                    }
                    expand(node)
                    fragment = ConfigFileEditor.collectionComments(text) + ConfigFileEditor.collectionFragment(root.convert(to: .toml), table: table)
                }
            }
            return try result(ConfigFileEditor.replaceCollectionSections(original, table: table, fragments: fragment.isEmpty ? [] : [fragment]))
        case .rows(let table, let fields, _, _):
            guard let value else { return try result(ConfigFileEditor.replaceCollectionSections(original, table: table, fragments: [])) }
            guard case .rows(let rows) = value else { throw SettingsFileError(message: tr("Tableau de lignes attendu.", "Table of rows expected.")) }
            let root = try TOMLTable(string: original)
            let sourceArray = SettingsCollectionCodec.node(root, path: table.components(separatedBy: "."))?.array
            let fragments = ConfigFileEditor.collectionRowFragments(original, table: table)
            let oldRows: [CollectionRow]
            if case .rows(let source) = try SettingsCollectionCodec.read(descriptor, text: original) { oldRows = source }
            else { oldRows = [] }
            let generated = try rows.map { row -> String in
                let old: CollectionRow?
                var fragment: String
                if let index = row.sourceIndex {
                    guard let sourceArray, index < sourceArray.count, let sourceTable = sourceArray[index].table,
                          index < oldRows.count else { throw SettingsFileError(message: tr("La ligne source n'existe plus. Recharge la collection.", "The source row no longer exists. Reload the collection.")) }
                    old = oldRows[index]
                    if index < fragments.count {
                        fragment = ConfigFileEditor.mapCollectionHeaders(fragments[index], from: table, to: "__roadie_row", rootIsArray: false)
                    } else { fragment = canonical(sourceTable) }
                } else {
                    old = nil
                    fragment = "[__roadie_row]\n"
                }
                for field in fields {
                    let key = field.path.joined(separator: ".")
                    let newValue = row.fields[key] ?? .unset
                    if old?.fields[key] == newValue { continue }
                    let literal = newValue == .unset ? nil : try SettingsCollectionCodec.literal(newValue, kind: field.kind)
                    let parent = (["__roadie_row"] + field.path.dropLast()).joined(separator: ".")
                    let edit = ConfigFileEditor.editStructuredValue(fragment, table: parent, key: field.path.last!, value: literal)
                    switch edit {
                    case .success(let edited): fragment = edited
                    case .failure(.inlineTable), .failure(.dottedKey):
                        // Forme compacte héritée : développer cette seule ligne, pas le document.
                        let parsed = try TOMLTable(string: fragment)
                        guard let rowTable = parsed["__roadie_row"]?.table else { throw SettingsFileError(message: tr("Ligne TOML invalide.", "Invalid TOML row.")) }
                        let comments = ConfigFileEditor.collectionComments(fragment)
                        fragment = comments + canonical(rowTable)
                        fragment = try result(ConfigFileEditor.editStructuredValue(fragment, table: parent, key: field.path.last!, value: literal))
                    case .failure(let error): throw SettingsFileError(message: SettingsService.message(error))
                    }
                }
                return ConfigFileEditor.mapCollectionHeaders(fragment, from: "__roadie_row", to: table, rootIsArray: true)
            }
            return try result(ConfigFileEditor.replaceCollectionSections(original, table: table, fragments: generated))
        }
    }

    private static func canonical(_ table: TOMLTable) -> String {
        func expand(_ table: TOMLTable) {
            table.inline = false
            for key in table.keys { if let child = table[key]?.table { expand(child) } }
        }
        expand(table)
        return TOMLTable(["__roadie_row": table]).convert(to: .toml)
    }

    private static func result(_ value: Result<String, ConfigEditError>) throws -> String {
        switch value {
        case .success(let text): return text
        case .failure(let error): throw SettingsFileError(message: SettingsService.message(error))
        }
    }
}
