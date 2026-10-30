import CoreGraphics
import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 135 : historique des zones de la recherche à l'écran, parcouru par ⌥Tab.
struct Spec135ZoneHistoryTests {
    private func zone(_ title: String, window: UInt32 = 169648, width: Double = 1200, height: Double = 800) -> ZoneRecord {
        ZoneRecord(appName: "Microsoft Excel", bundleID: "com.microsoft.Excel", pid: 7965, windowID: window, windowTitle: "Classeur",
                   title: title, relative: Rect(x: 100, y: 40, width: 80, height: 20), windowWidth: width, windowHeight: height, date: Date())
    }

    @Test func firstChoiceSkipsTheZoneWeAreAlreadyIn() {
        #expect(ZoneNavigation.firstIndex(count: 3, mostRecentWindow: 1, frontWindow: 2, reverse: false) == 0)
        #expect(ZoneNavigation.firstIndex(count: 3, mostRecentWindow: 1, frontWindow: 1, reverse: false) == 1)
        #expect(ZoneNavigation.firstIndex(count: 1, mostRecentWindow: 1, frontWindow: 1, reverse: false) == 0)
        #expect(ZoneNavigation.firstIndex(count: 3, mostRecentWindow: 1, frontWindow: 2, reverse: true) == 2)
    }

    @Test func clickPointPrefersTheLiveElementThenTheRelativePlace() {
        let record = zone("Développeur")
        let window = Rect(x: 2000, y: 100, width: 1200, height: 800)
        // Élément encore lisible dans la fenêtre : son centre, même s'il a bougé.
        #expect(ZoneNavigation.point(for: record, elementFrame: Rect(x: 2300, y: 160, width: 40, height: 20), windowFrame: window)
                == CGPoint(x: 2320, y: 170))
        // Élément illisible ou hors de la fenêtre : position relative, fenêtre de même taille.
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: window) == CGPoint(x: 2140, y: 150))
        #expect(ZoneNavigation.point(for: record, elementFrame: Rect(x: -900, y: 0, width: 10, height: 10), windowFrame: window)
                == CGPoint(x: 2140, y: 150))
        // Fenêtre redimensionnée ou introuvable : rien à cliquer.
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: Rect(x: 0, y: 0, width: 900, height: 800)) == nil)
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: nil) == nil)
    }

    @MainActor @Test func historyKeepsTwentyDistinctZonesAcrossRestarts() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        for index in 0..<25 { history.record(zone("Zone \(index)"), element: nil) }
        history.record(zone("Zone 20"), element: nil)
        #expect(history.records.count == 20 && history.records.first?.title == "Zone 20")
        #expect(Set(history.records.map(\.key)).count == 20)
        // Même zone dans une autre fenêtre : distincte.
        history.record(zone("Zone 20", window: 1), element: nil)
        #expect(history.records.prefix(2).map(\.windowID) == [1, 169648])
        let reloaded = ZoneHistory(path: path)
        #expect(reloaded.records == history.records)
        reloaded.forget(reloaded.records[0])
        #expect(ZoneHistory(path: path).records.first?.title == "Zone 20" && ZoneHistory(path: path).records.count == 19)
    }

    @Test func shortcutIsReadAndShiftGoesBack() throws {
        #expect(TargetModeConfig().zoneHistoryHotkey.isEmpty)
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: "[experimental.target_mode]\nzone_history_hotkey = \"alt+tab\"\n")
        let hotkey = config.experimental.targetMode.zoneHistoryHotkey
        #expect(TargetModeConfig.hotkeyParts(hotkey) != nil)
        #expect(TargetModeConfig.hotkeyParts(ZoneNavigation.hotkey(hotkey, reverse: true)) != nil)
        #expect(ZoneNavigation.hotkey(hotkey, reverse: false) == hotkey)
        #expect(ZoneNavigation.hotkey("", reverse: true).isEmpty && ZoneNavigation.hotkey("shift+alt+tab", reverse: true).isEmpty)
        #expect(SettingsCatalog.find(id: "target_mode.zone_history_hotkey")?.category == .raccourcis)
    }
}
