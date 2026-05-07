import Foundation
import RoadieCore

public struct LayoutIntent: Equatable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case auto
        case command
    }

    public var scope: StageScope
    public var windowIDs: [WindowID]
    public var placements: [WindowID: Rect]
    public var createdAt: Date
    public var source: Source

    public init(
        scope: StageScope,
        windowIDs: [WindowID],
        placements: [WindowID: Rect],
        createdAt: Date = Date(),
        source: Source = .auto
    ) {
        self.scope = scope
        self.windowIDs = windowIDs
        self.placements = placements
        self.createdAt = createdAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case windowIDs
        case placements
        case createdAt
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scope = try container.decode(StageScope.self, forKey: .scope)
        self.windowIDs = try container.decode([WindowID].self, forKey: .windowIDs)
        self.placements = try container.decode([WindowID: Rect].self, forKey: .placements)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.source = (try container.decodeIfPresent(LayoutIntent.Source.self, forKey: .source)) ?? .auto
    }
}

public struct LayoutIntentStore: Sendable {
    private let url: URL

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-layout-intents-\(ProcessInfo.processInfo.processIdentifier).json"
        }
        return "~/.roadies/layout-intents.json"
    }

    public func intent(for scope: StageScope) -> LayoutIntent? {
        load()[scope.description]
    }

    public func save(_ intent: LayoutIntent) {
        var intents = load()
        intents[intent.scope.description] = intent
        write(intents)
    }

    public func touch(scope: StageScope, at date: Date = Date()) {
        guard var intent = intent(for: scope) else { return }
        intent.createdAt = date
        save(intent)
    }

    public func remove(scope: StageScope) {
        var intents = load()
        intents.removeValue(forKey: scope.description)
        write(intents)
    }

    public func prune(keepingDisplayIDs displayIDs: Set<DisplayID>) {
        var intents = load()
        intents = intents.filter { _, intent in displayIDs.contains(intent.scope.displayID) }
        write(intents)
    }

    private func load() -> [String: LayoutIntent] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: LayoutIntent].self, from: data)) ?? [:]
    }

    private func write(_ intents: [String: LayoutIntent]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(intents).write(to: url, options: .atomic)
        } catch {
            fputs("roadie: failed to persist layout intent: \(error)\n", stderr)
        }
    }
}
