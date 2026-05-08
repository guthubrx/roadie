import Foundation
import RoadieCore

public struct RailRuntimeState: Equatable, Codable, Sendable {
    public var visibleWidths: [String: Double]
    public var isPinned: Bool

    public init(visibleWidths: [String: Double] = [:], isPinned: Bool = false) {
        self.visibleWidths = visibleWidths
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case visibleWidths
        case isPinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleWidths = try container.decodeIfPresent([String: Double].self, forKey: .visibleWidths) ?? [:]
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

public struct RailRuntimeStateStore: Sendable {
    private let url: URL

    public init(path: String = "~/.local/state/roadies/rail.json") {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public func load() -> RailRuntimeState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RailRuntimeState.self, from: data)
        else {
            return RailRuntimeState()
        }
        return state
    }

    public func save(_ state: RailRuntimeState) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func setVisibleWidth(_ width: Double, for displayID: DisplayID) {
        var state = load()
        state.visibleWidths[displayID.rawValue] = width
        save(state)
    }

    @discardableResult
    public func setPinned(_ pinned: Bool) -> RailRuntimeState {
        var state = load()
        state.isPinned = pinned
        save(state)
        return state
    }

    @discardableResult
    public func togglePinned() -> RailRuntimeState {
        var state = load()
        state.isPinned.toggle()
        save(state)
        return state
    }
}
