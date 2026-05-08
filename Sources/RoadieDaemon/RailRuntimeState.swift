import Foundation
import RoadieCore

public struct RailRuntimeState: Equatable, Codable, Sendable {
    public var visibleWidths: [String: Double]

    public init(visibleWidths: [String: Double] = [:]) {
        self.visibleWidths = visibleWidths
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
}
