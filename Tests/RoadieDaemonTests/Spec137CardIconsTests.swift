import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 137 : icônes du coin des cartes (× et sens interdit), listes d'exclusion annulables.
struct Spec137CardIconsTests {
    @Test func noEntrySignAddsTheAppOnceToTheChosenList() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spec137-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("roadies.toml")
        try "[switcher]\nexcluded_bundles = [\"com.apple.finder\"]\n".write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: folder.appendingPathComponent("events.jsonl").path), afterWrite: {})
        #expect(SwitcherExclusions.add("com.google.Chrome", to: SwitcherExclusions.windows, settings: service))
        #expect(!SwitcherExclusions.add("com.google.Chrome", to: SwitcherExclusions.windows, settings: service))
        #expect(SwitcherExclusions.add("com.microsoft.Excel", to: SwitcherExclusions.clickZones, settings: service))
        #expect(!SwitcherExclusions.add("", to: SwitcherExclusions.clickZones, settings: service))
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: String(contentsOf: file, encoding: .utf8))
        #expect(config.switcher.excludedBundles == ["com.apple.finder", "com.google.Chrome"])
        #expect(config.switcher.zoneClickExcludedBundles == ["com.microsoft.Excel"])
        #expect(SettingsCatalog.find(id: SwitcherExclusions.clickZones)?.category == .selecteur)
    }

    @MainActor @Test func bannedAppLosesItsClickZonesOnly() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec137-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        func zone(_ title: String, bundle: String, y: Double, click: Bool) -> ZoneRecord {
            ZoneRecord(appName: title, bundleID: bundle, pid: 1, windowID: 10, windowTitle: "", title: title,
                       relative: Rect(x: 0, y: y, width: 10, height: 10), windowWidth: 100, windowHeight: 100, date: Date(), fromClick: click)
        }
        for (title, bundle, y, click) in [("clic Excel", "com.microsoft.Excel", 0.0, true), ("recherche Excel", "com.microsoft.Excel", 30, false),
                                          ("clic Chrome", "com.google.Chrome", 60, true)] {
            history.record(zone(title, bundle: bundle, y: y, click: click), element: nil, policy: ZonePolicy())
        }
        #expect(history.forgetClicks(bundleID: "com.microsoft.Excel").count == 1)
        #expect(history.records.map(\.title) == ["clic Chrome", "recherche Excel"])
        #expect(ZoneHistory(path: path).records.count == 2)
    }
}
