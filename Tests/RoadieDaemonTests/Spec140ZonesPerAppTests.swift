import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 140 : nombre de zones de clics par fenêtre propre à une application ; les autres prennent la valeur globale.
struct Spec140ZonesPerAppTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func click(_ title: String, app: String, bundle: String, window: UInt32, y: Double) -> ZoneRecord {
        ZoneRecord(appName: app, bundleID: bundle, pid: 1, windowID: window, windowTitle: "", title: title,
                   relative: Rect(x: 0, y: y, width: 10, height: 10), windowWidth: 100, windowHeight: 100, date: now, fromClick: true)
    }

    @Test func eachAppUsesItsOwnCountOrTheGlobalOne() throws {
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: """
            [switcher]
            zone_clicks_per_window = 2
            [[switcher.zone_clicks_per_app]]
            app = "com.microsoft.Excel"
            count = 4
            [[switcher.zone_clicks_per_app]]
            app = "Finder"
            count = 0
            [[switcher.zone_clicks_per_app]]
            app = "T3 Code"
            count = 42
            """)
        let rows = config.switcher.zoneClicksPerApp
        #expect(rows.map(\.count) == [4, 0, 10])
        let policy = ZonePolicy(clicksPerWindow: config.switcher.zoneClicksPerWindow, clicksPerApp: ZonePolicy.perApp(rows))
        #expect(policy.clicksPerWindow(bundleID: "com.microsoft.Excel", appName: "Microsoft Excel") == 4)
        #expect(policy.clicksPerWindow(bundleID: "com.apple.finder", appName: "finder") == 0)
        #expect(policy.clicksPerWindow(bundleID: "com.google.Chrome", appName: "Google Chrome") == 2)
        // Excel garde 4 zones par fenêtre, Chrome 2 (valeur globale), Finder aucune.
        var records: [ZoneRecord] = []
        for index in 0..<5 {
            records.append(click("x\(index)", app: "Microsoft Excel", bundle: "com.microsoft.Excel", window: 1, y: Double(index * 20)))
            records.append(click("c\(index)", app: "Google Chrome", bundle: "com.google.Chrome", window: 2, y: Double(index * 20)))
            records.append(click("f\(index)", app: "Finder", bundle: "com.apple.finder", window: 3, y: Double(index * 20)))
        }
        let kept = policy.kept(records, now: now)
        #expect(kept.filter { $0.windowID == 1 }.count == 4 && kept.filter { $0.windowID == 2 }.count == 2 && kept.filter { $0.windowID == 3 }.isEmpty)
        #expect(SettingsCatalog.find(id: "switcher.zone_clicks_per_app")?.category == .selecteur)
    }
}
