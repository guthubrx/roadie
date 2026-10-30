import CoreGraphics
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 135 : historique des zones de la recherche à l'écran, retrouvées et recliquées.
struct Spec135ZoneHistoryTests {
    private func zone(_ title: String, window: UInt32 = 169648, y: Double = 40, width: Double = 1200, height: Double = 800) -> ZoneRecord {
        ZoneRecord(appName: "Microsoft Excel", bundleID: "com.microsoft.Excel", pid: 7965, windowID: window, windowTitle: "Classeur",
                   title: title, relative: Rect(x: 100, y: y, width: 80, height: 20), windowWidth: width, windowHeight: height, date: Date())
    }

    @Test func clickPointPrefersTheLiveElementThenTheRelativePlace() {
        let record = zone("Développeur")
        let window = Rect(x: 2000, y: 100, width: 1200, height: 800)
        #expect(ZoneNavigation.point(for: record, elementFrame: Rect(x: 2300, y: 160, width: 40, height: 20), windowFrame: window)
                == CGPoint(x: 2320, y: 170))
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: window) == CGPoint(x: 2140, y: 150))
        #expect(ZoneNavigation.point(for: record, elementFrame: Rect(x: -900, y: 0, width: 10, height: 10), windowFrame: window)
                == CGPoint(x: 2140, y: 150))
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: Rect(x: 0, y: 0, width: 900, height: 800)) == nil)
        #expect(ZoneNavigation.point(for: record, elementFrame: nil, windowFrame: nil) == nil)
    }

    /// Essai du 30 octobre 2026 : trois lignes « AXButton » de T3 Code ne laissaient qu'une zone.
    @MainActor @Test func distinctPlacesWithTheSameTextAreDistinctZones() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        for y in [40.0, 120, 200] { history.record(zone("AXButton", y: y), element: nil, policy: ZonePolicy()) }
        history.record(zone("AXButton", y: 122), element: nil, policy: ZonePolicy())
        #expect(history.records.map(\.relative.y) == [122, 200, 40])
        #expect(ZoneRecord.label(title: "AXButton", searchText: "Recherche à l'écran\nil y a 2 h", subtitle: "") == "Recherche à l'écran")
        #expect(ZoneRecord.label(title: "Développeur", searchText: "x", subtitle: "") == "Développeur")
        #expect(ZoneRecord.label(title: "AXCell", searchText: nil, subtitle: "B12") == "B12")
    }

    @MainActor @Test func historyIsKeptAcrossRestarts() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        var dropped: [String] = []
        for index in 0..<21 { dropped += history.record(zone("Zone \(index)", y: Double(index * 30)), element: nil, policy: ZonePolicy()) }
        #expect(history.records.count == 20 && dropped == [zone("Zone 0", y: 0).key])
        history.setThumbnail(CGRect(x: 1, y: 2, width: 3, height: 4), for: history.records[0].key)
        let reloaded = ZoneHistory(path: path)
        #expect(reloaded.records == history.records && reloaded.records[0].thumbnailCrop == Rect(x: 1, y: 2, width: 3, height: 4))
        reloaded.forget(reloaded.records[0])
        #expect(ZoneHistory(path: path).records.count == 19)
    }

    /// Photo : 300 × 180 points autour de la zone, gardée dans la fenêtre ; zone entourée dans la photo.
    @MainActor @Test func photoCropsAroundTheZoneAndRingsIt() {
        let window = CGSize(width: 1200, height: 800)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window, area: CGSize(width: 440, height: 260))
                == CGRect(x: 380, y: 270, width: 440, height: 260))
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window).size == CGSize(width: 300, height: 180))
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 10, y: 5, width: 40, height: 20), windowSize: window).origin == .zero)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 1180, y: 790, width: 10, height: 5), windowSize: window).maxX == 1200)
        #expect(ZoneThumbnails.crop(zone: .zero, windowSize: CGSize(width: 250, height: 150)) == CGRect(x: 0, y: 0, width: 250, height: 150))
        // Entourage : axe vertical retourné, 3 points de marge.
        #expect(ZoneThumbnails.ring(zone: CGRect(x: 580, y: 390, width: 40, height: 20), crop: CGRect(x: 380, y: 270, width: 440, height: 260))
                == CGRect(x: 197, y: 117, width: 46, height: 26))
        // Ligne de T3 Code presque aussi large que la photo (essai) : l'entourage reste dans la photo.
        let crop = CGRect(x: 9.5, y: 556, width: 300, height: 180)
        let wide = ZoneThumbnails.ring(zone: CGRect(x: 10, y: 646, width: 439, height: 80), crop: crop)
        #expect(wide.map { CGRect(origin: .zero, size: crop.size).contains($0) } == true)
        #expect(ZoneThumbnails.fileName("299224|12|-3") == "299224-12--3.png")
    }
}
