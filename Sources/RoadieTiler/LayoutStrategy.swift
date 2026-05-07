public protocol LayoutStrategy: Sendable {
    func plan(_ request: LayoutRequest) -> LayoutPlan
}
