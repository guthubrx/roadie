import Foundation
import Testing
import RoadieCore
import RoadieDaemon

private struct FakeAppTargetProvider: AppTargetProviding {
    var items: [AppElementCandidate]
    var clickResult: TargetActionResult = TargetActionResult(changed: true, message: "clicked")

    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(targets: AppTargetQueryService.targets(from: items, config: config))
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        TargetActionResult(changed: clickResult.changed, message: "\(action.rawValue) \(target.id)", target: target, error: clickResult.error)
    }
}

@Suite
struct AppTargetQueryServiceTests {
    @Test
    func appTargetsAreDisabledUnlessConfiguredOrOverridden() {
        let service = AppTargetQueryService(provider: FakeAppTargetProvider(items: []))

        let report = service.query(config: AppTargetsConfig(enabled: false), enabledOverride: false)

        #expect(report.targets.isEmpty)
        #expect(report.error == "app_targets_disabled")
    }

    @Test
    func appTargetsFilterRolesAndPreserveActionableElements() {
        let provider = FakeAppTargetProvider(items: [
            AppElementCandidate(id: "1", role: "AXButton", title: "OK", frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: []),
            AppElementCandidate(id: "2", role: "AXStaticText", title: "Label", frame: Rect(x: 0, y: 30, width: 20, height: 20), actions: []),
            AppElementCandidate(id: "3", role: "AXStaticText", title: "Clickable", frame: Rect(x: 0, y: 60, width: 20, height: 20), actions: ["AXPress"]),
        ])
        let service = AppTargetQueryService(provider: provider)
        let config = AppTargetsConfig(enabled: true, includeRoles: ["AXButton"])

        let report = service.query(config: config)

        #expect(report.targets.map(\.title) == ["OK", "Clickable"])
        #expect(report.targets.allSatisfy { $0.actions.contains(.click) })
        #expect(report.targets.allSatisfy { $0.actions.contains(.doubleClick) })
        #expect(report.targets.allSatisfy { $0.actions.contains(.rightClick) })
    }

    @Test
    func clickVariantsAreRoutedToProvider() {
        let target = RoadieTarget(
            id: "app:1/0",
            kind: .appElement,
            title: "OK",
            source: .app,
            frame: Rect(x: 0, y: 0, width: 100, height: 40),
            actions: [.click, .doubleClick, .rightClick]
        )
        let service = AppTargetQueryService(provider: FakeAppTargetProvider(items: []))

        let result = service.click(target, action: .rightClick)

        #expect(result.changed)
        #expect(result.message == "right-click app:1/0")
    }
}
