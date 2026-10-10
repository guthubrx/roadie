import Foundation
import RoadieCore

public struct RailRuntimeState: Equatable, Codable, Sendable {
    public var visibleWidths: [String: Double]
    public var isPinned: Bool
    public var stageLabelsVisibleUntil: Double?

    public init(
        visibleWidths: [String: Double] = [:],
        isPinned: Bool = false,
        stageLabelsVisibleUntil: Double? = nil
    ) {
        self.visibleWidths = visibleWidths
        self.isPinned = isPinned
        self.stageLabelsVisibleUntil = stageLabelsVisibleUntil
    }

    enum CodingKeys: String, CodingKey {
        case visibleWidths
        case isPinned
        case stageLabelsVisibleUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleWidths = try container.decodeIfPresent([String: Double].self, forKey: .visibleWidths) ?? [:]
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        stageLabelsVisibleUntil = try container.decodeIfPresent(Double.self, forKey: .stageLabelsVisibleUntil)
    }
}

public struct RailRuntimeStateStore: Sendable {
    private let url: URL

    public init(path: String = "~/.local/state/roadies/rail.json") {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    /// Lecture sans verrou (écriture atomique par rename, cf. `JSONPersistence.load`).
    public func load() -> RailRuntimeState {
        JSONPersistence.load(RailRuntimeState.self, from: url, default: RailRuntimeState())
    }

    public func save(_ state: RailRuntimeState) {
        mutate { $0 = state }
    }

    public func setVisibleWidth(_ width: Double, for displayID: DisplayID) {
        mutate { $0.visibleWidths[displayID.rawValue] = width }
    }

    @discardableResult
    public func setPinned(_ pinned: Bool) -> RailRuntimeState {
        mutate { state in
            state.isPinned = pinned
            return state
        }
    }

    @discardableResult
    public func togglePinned() -> RailRuntimeState {
        mutate { state in
            state.isPinned.toggle()
            return state
        }
    }

    @discardableResult
    public func showStageLabels(for seconds: Double, now: Date = Date()) -> RailRuntimeState {
        mutate { state in
            state.stageLabelsVisibleUntil = seconds > 0 ? now.addingTimeInterval(seconds).timeIntervalSince1970 : nil
            return state
        }
    }

    @discardableResult
    public func hideStageLabels() -> RailRuntimeState {
        mutate { state in
            state.stageLabelsVisibleUntil = 0
            return state
        }
    }

    /// Transaction exclusive entre processus (rail, CLI, daemon) : SPEC-016 FR-013.
    @discardableResult
    private func mutate<R>(_ body: (inout RailRuntimeState) -> R) -> R {
        JSONPersistence.mutate(RailRuntimeState.self, at: url, default: RailRuntimeState(), label: "rail runtime state", body)
    }
}
