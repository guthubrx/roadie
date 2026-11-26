import Foundation
import RoadieAX
import RoadieCore

/// Empreinte topologique portable d'un ensemble d'écrans (Spec 170) :
/// indépendante des UUID matériels, fondée sur le nombre d'écrans et leurs résolutions logiques triées.
public struct DisplayTopologySignature: Codable, Equatable, Hashable, Sendable {
    public var displayCount: Int
    public var dimensions: [String]

    public init(displayCount: Int, dimensions: [String]) {
        self.displayCount = displayCount
        self.dimensions = dimensions.sorted()
    }

    public init(displays: [DisplaySnapshot]) {
        let dims = displays.map { "\(Int($0.frame.width.rounded()))x\(Int($0.frame.height.rounded()))" }.sorted()
        self.displayCount = displays.count
        self.dimensions = dims
    }

    public var description: String {
        dimensions.joined(separator: "+")
    }
}

/// Profil matériel de disposition associé à une topologie d'écrans (ex. « Portable », « Bureau 4K », « Présentation »).
public struct DisplayProfile: Codable, Equatable, Sendable {
    public var name: String
    public var signature: DisplayTopologySignature
    public var defaultStrategy: WindowManagementMode
    public var gapsOuter: Double
    public var gapsInner: Double
    public var scrollingColumnWidth: Double
    public var projectName: String?
    public var updatedAt: Date

    public init(
        name: String,
        signature: DisplayTopologySignature,
        defaultStrategy: WindowManagementMode,
        gapsOuter: Double = 8,
        gapsInner: Double = 4,
        scrollingColumnWidth: Double = 0.65,
        projectName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.signature = signature
        self.defaultStrategy = defaultStrategy
        self.gapsOuter = gapsOuter
        self.gapsInner = gapsInner
        self.scrollingColumnWidth = scrollingColumnWidth
        self.projectName = projectName
        self.updatedAt = updatedAt
    }
}

public struct DisplayProfileBook: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var profiles: [DisplayProfile]

    public init(schemaVersion: Int = 1, profiles: [DisplayProfile] = []) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }
}

/// Persistance atomique locale des profils d'écrans (`~/.roadies/display-profiles.json`).
public struct DisplayProfileStore: Sendable {
    public let url: URL

    public init(url: URL = DisplayProfileStore.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".roadies", isDirectory: true)
            .appendingPathComponent("display-profiles.json")
    }

    public func load() -> DisplayProfileBook {
        guard let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(DisplayProfileBook.self, from: data)
        else {
            return DisplayProfileBook()
        }
        return book
    }

    public func save(_ book: DisplayProfileBook) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(book)
        let tmp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

/// Service de gestion et de rappel conditionnel des profils matériels d'écrans (Spec 170).
/// Zéro timer, zéro basculement automatique tant que `tiling.display_profiles_enabled == false`.
public struct DisplayProfileService: Sendable {
    public let store: DisplayProfileStore

    public init(store: DisplayProfileStore = DisplayProfileStore()) {
        self.store = store
    }

    public func list() -> [DisplayProfile] {
        store.load().profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    public func saveCurrent(
        name: String,
        displays: [DisplaySnapshot],
        tiling: TilingConfig,
        projectName: String? = nil,
        now: Date = Date()
    ) throws -> DisplayProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "RoadieDisplayProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nom de profil vide"])
        }
        let profile = DisplayProfile(
            name: trimmed,
            signature: DisplayTopologySignature(displays: displays),
            defaultStrategy: tiling.defaultStrategy,
            gapsOuter: tiling.gapsOuter,
            gapsInner: tiling.gapsInner,
            scrollingColumnWidth: tiling.scrollingColumnWidth,
            projectName: projectName,
            updatedAt: now
        )
        var book = store.load()
        book.profiles.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        book.profiles.append(profile)
        try store.save(book)
        return profile
    }

    @discardableResult
    public func delete(name: String) throws -> Bool {
        var book = store.load()
        let before = book.profiles.count
        book.profiles.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard book.profiles.count != before else { return false }
        try store.save(book)
        return true
    }

    /// Recherche le profil correspondant le mieux à la topologie d'écrans courante :
    /// d'abord signature exacte (nombre + résolutions), sinon même nombre d'écrans (le plus récent).
    public func match(displays: [DisplaySnapshot]) -> DisplayProfile? {
        let profiles = store.load().profiles
        guard !profiles.isEmpty else { return nil }
        let sig = DisplayTopologySignature(displays: displays)
        if let exact = profiles.first(where: { $0.signature == sig }) {
            return exact
        }
        return profiles
            .filter { $0.signature.displayCount == sig.displayCount }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    /// Garde de sécurité (FR-003) : le rappel automatique ne s'exécute jamais si l'interrupteur
    /// `tiling.display_profiles_enabled` est éteint, ni dans les `graceSeconds` (60 s) suivant
    /// une modification manuelle de disposition par l'utilisateur.
    public static func shouldAutoApply(
        enabled: Bool,
        lastManualChangeAt: Date?,
        now: Date = Date(),
        graceSeconds: TimeInterval = 60
    ) -> Bool {
        guard enabled else { return false }
        if let lastManualChangeAt, now.timeIntervalSince(lastManualChangeAt) < graceSeconds {
            return false
        }
        return true
    }
}
