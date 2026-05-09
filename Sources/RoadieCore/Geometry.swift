import CoreGraphics

public struct Rect: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}

public struct Insets: Equatable, Codable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let zero = Insets(top: 0, right: 0, bottom: 0, left: 0)
}

public extension CGRect {
    func inset(by insets: Insets) -> CGRect {
        CGRect(
            x: origin.x + insets.left,
            y: origin.y + insets.top,
            width: max(0, width - insets.left - insets.right),
            height: max(0, height - insets.top - insets.bottom)
        )
    }

    func isEquivalent(to other: CGRect, tolerancePoints: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerancePoints
            && abs(minY - other.minY) <= tolerancePoints
            && abs(width - other.width) <= tolerancePoints
            && abs(height - other.height) <= tolerancePoints
    }
}

public extension Rect {
    func isEquivalent(to other: Rect, tolerancePoints: Double = 2) -> Bool {
        cgRect.isEquivalent(to: other.cgRect, tolerancePoints: CGFloat(tolerancePoints))
    }
}
