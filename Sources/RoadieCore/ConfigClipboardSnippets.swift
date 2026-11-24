import Foundation

/// Configuration de l'historique local et sécurisé du presse-papiers (`[clipboard]`, Spec 163).
public struct ClipboardConfig: Equatable, Codable, Sendable {
    public static let defaultExcludedBundles: [String] = [
        "org.keepassxc.keepassxc",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
    ]

    public var enabled: Bool
    public var maxItems: Int
    public var retentionDays: Int
    public var excludedBundles: [String]

    public init(
        enabled: Bool = true,
        maxItems: Int = 200,
        retentionDays: Int = 7,
        excludedBundles: [String] = ClipboardConfig.defaultExcludedBundles
    ) {
        self.enabled = enabled
        self.maxItems = min(2000, max(10, maxItems))
        self.retentionDays = min(90, max(1, retentionDays))
        self.excludedBundles = excludedBundles
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxItems = "max_items"
        case retentionDays = "retention_days"
        case excludedBundles = "excluded_bundles"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            maxItems: try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? 200,
            retentionDays: try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 7,
            excludedBundles: try c.decodeIfPresent([String].self, forKey: .excludedBundles) ?? Self.defaultExcludedBundles
        )
    }
}

/// Définition d'un snippet local (`[[snippets.items]]`, Spec 163).
public struct SnippetItem: Equatable, Codable, Sendable {
    public var keyword: String
    public var title: String
    public var body: String

    public init(keyword: String, title: String = "", body: String) {
        self.keyword = keyword
        self.title = title
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case keyword
        case title
        case body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyword = try c.decode(String.self, forKey: .keyword)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.body = try c.decode(String.self, forKey: .body)
    }
}

/// Configuration des snippets et de l'expandeur de texte local (`[snippets]`, Spec 163).
public struct SnippetsConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    /// Auto-expansion clavier globale (désactivée par défaut par sécurité).
    public var autoExpand: Bool
    public var items: [SnippetItem]

    public init(
        enabled: Bool = true,
        autoExpand: Bool = false,
        items: [SnippetItem] = []
    ) {
        self.enabled = enabled
        self.autoExpand = autoExpand
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case autoExpand = "auto_expand"
        case items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.autoExpand = try c.decodeIfPresent(Bool.self, forKey: .autoExpand) ?? false
        self.items = try c.decodeIfPresent([SnippetItem].self, forKey: .items) ?? []
    }
}
