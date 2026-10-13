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

    @Test
    func scanIsRetriedOnlyWhileAFullyExploredElectronTreeHasNoWebArea() {
        #expect(AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 0))
        #expect(AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 1))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 2))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: true, exploredFully: true, retries: 0))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: false, retries: 0))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: false, sawWebArea: false, exploredFully: true, retries: 0))
    }

    @Test
    func electronBundlesAreDetectedByTheirFramework() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let electron = root.appendingPathComponent("Electron.app")
        let native = root.appendingPathComponent("Native.app")
        try FileManager.default.createDirectory(
            at: electron.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: native.appendingPathComponent("Contents/Frameworks"), withIntermediateDirectories: true)

        #expect(AppTargetQueryService.isElectronBundle(at: electron))
        #expect(!AppTargetQueryService.isElectronBundle(at: native))
        #expect(!AppTargetQueryService.isElectronBundle(at: nil))
    }

    @Test
    func elementsAreClippedToTheWindowSoTheirClickPointStaysInside() {
        let window = Rect(x: 100, y: 100, width: 400, height: 300)

        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 150, width: 20, height: 20), in: window)
            == Rect(x: 150, y: 150, width: 20, height: 20))
        let clipped = AppTargetQueryService.visibleFrame(Rect(x: 480, y: 380, width: 60, height: 60), in: window)
        #expect(clipped == Rect(x: 480, y: 380, width: 20, height: 20))
        #expect(clipped.map { window.cgRect.contains(CGPoint(x: $0.cgRect.midX, y: $0.cgRect.midY)) } == true)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 900, width: 20, height: 20), in: window) == nil)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 500, y: 150, width: 20, height: 20), in: window) == nil)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 900, width: 20, height: 20), in: nil)
            == Rect(x: 150, y: 900, width: 20, height: 20))
    }
}
