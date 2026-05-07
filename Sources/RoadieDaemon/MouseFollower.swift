import CoreGraphics
import RoadieAX
import RoadieCore

public struct MouseFollower: Sendable {
    private let isEnabled: @Sendable () -> Bool
    private let move: @Sendable (CGPoint) -> Void

    public init(
        isEnabled: @escaping @Sendable () -> Bool = {
            ((try? RoadieConfigLoader.load()) ?? RoadieConfig()).focus.mouseFollowsFocus
        },
        move: @escaping @Sendable (CGPoint) -> Void = { point in
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        }
    ) {
        self.isEnabled = isEnabled
        self.move = move
    }

    public func follow(_ window: WindowSnapshot) {
        guard isEnabled() else { return }
        move(window.frame.center)
    }
}
