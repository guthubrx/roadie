import CoreGraphics
import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 135 : historique des zones de la recherche à l'écran, parcouru par ⌥Tab.
struct Spec135ZoneHistoryTests {
    private func zone(_ title: String, window: UInt32 = 169648, y: Double = 40, width: Double = 1200, height: Double = 800) -> ZoneRecord {
        ZoneRecord(appName: "Microsoft Excel", bundleID: "com.microsoft.Excel", pid: 7965, windowID: window, windowTitle: "Classeur",
                   title: title, relative: Rect(x: 100, y: y, width: 80, height: 20), windowWidth: width, windowHeight: height, date: Date())
    }

    /// Essai du 30 octobre 2026 : trois lignes « AXButton » de T3 Code ne laissaient qu'une zone.
    @MainActor @Test func distinctPlacesWithTheSameTextAreDistinctZones() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        for y in [40.0, 120, 200] { history.record(zone("AXButton", y: y), element: nil) }
        history.record(zone("AXButton", y: 122), element: nil)
        #expect(history.records.map(\.relative.y) == [122, 200, 40])
        #expect(ZoneRecord.label(title: "AXButton", searchText: "Recherche à l'écran\nil y a 2 h", subtitle: "") == "Recherche à l'écran")
        #expect(ZoneRecord.label(title: "Développeur", searchText: "x", subtitle: "") == "Développeur")
        #expect(ZoneRecord.label(title: "AXCell", searchText: nil, subtitle: "B12") == "B12")
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
        for index in 0..<25 { history.record(zone("Zone \(index)", y: Double(index * 30)), element: nil) }
        history.record(zone("Zone 20", y: 600), element: nil)
        #expect(history.records.count == 20 && history.records.first?.title == "Zone 20")
        #expect(Set(history.records.map(\.key)).count == 20)
        // Même zone dans une autre fenêtre : distincte.
        history.record(zone("Zone 20", window: 1, y: 600), element: nil)
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

    /// Vignette : rectangle de 440 × 260 points centré sur la zone, gardé dans la fenêtre ; zone entourée dedans.
    @MainActor @Test func thumbnailCropsAroundTheZoneAndRingsIt() {
        let window = CGSize(width: 1200, height: 800)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window, area: CGSize(width: 440, height: 260))
                == CGRect(x: 380, y: 270, width: 440, height: 260))
        // Rectangle par défaut : 300 × 180 points, affiché à l'échelle 1 dans la carte (lisibilité).
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window).size == CGSize(width: 300, height: 180))
        #expect(ZoneSwitcherPanel.cardCount(screenWidth: 1512) == 4 && ZoneSwitcherPanel.cardCount(screenWidth: 3840) == 7)
        #expect(ZoneSwitcherPanel.cardCount(screenWidth: 200) == 1)
        // Près d'un bord : décalée pour rester dans la fenêtre ; petite fenêtre : la fenêtre entière.
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 10, y: 5, width: 40, height: 20), windowSize: window).origin == .zero)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 1180, y: 790, width: 10, height: 5), windowSize: window).maxX == 1200)
        #expect(ZoneThumbnails.crop(zone: .zero, windowSize: CGSize(width: 250, height: 150)) == CGRect(x: 0, y: 0, width: 250, height: 150))
        // Entourage : même échelle que la vignette, axe vertical retourné, 3 points de marge.
        let ring = ZoneSwitcherPanel.highlight(zone: CGRect(x: 580, y: 390, width: 40, height: 20),
                                               crop: CGRect(x: 380, y: 270, width: 440, height: 260), in: CGSize(width: 440, height: 260))
        #expect(ring == CGRect(x: 197, y: 117, width: 46, height: 26))
        #expect(ZoneThumbnails.fileName("299224|12|-3") == "299224-12--3.png")
        // Ligne de T3 Code presque aussi large que la vignette (439 points sur 440) : entourage gardé dans l'image.
        let wide = ZoneSwitcherPanel.highlight(zone: CGRect(x: 10, y: 646, width: 439, height: 80),
                                               crop: CGRect(x: 9.5, y: 556, width: 440, height: 260), in: CGSize(width: 228, height: 136))
        let shown = CGRect(x: 0, y: 0, width: 228, height: 136)
        #expect(wide.map { shown.contains($0) } == true && (wide?.width ?? 0) > 220)
    }

    @MainActor @Test func droppedZonesAndThumbnailsAreReported() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        var dropped: [String] = []
        for index in 0..<21 { dropped += history.record(zone("Zone \(index)", y: Double(index * 30)), element: nil) }
        #expect(dropped == [zone("Zone 0", y: 0).key])
        history.setThumbnail(CGRect(x: 1, y: 2, width: 3, height: 4), for: history.records[0].key)
        #expect(ZoneHistory(path: path).records[0].thumbnailCrop == Rect(x: 1, y: 2, width: 3, height: 4))
    }
}
