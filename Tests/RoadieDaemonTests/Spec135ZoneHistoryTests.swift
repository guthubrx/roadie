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

    @MainActor @Test func corruptHistoryPreservesBytesAndResumesAfterRepair() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("zones.json")
        let invalid = Data("{".utf8)
        try invalid.write(to: file)
        let history = ZoneHistory(path: file.path)
        let fresh = zone("Nouvelle")
        #expect(history.record(fresh, element: nil, policy: ZonePolicy()) == nil)
        #expect(!history.forget(fresh))
        #expect(try Data(contentsOf: file) == invalid)
        let backups = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("zones.json.corrupt-") }
        #expect(backups.count == 1)
        if let backup = backups.first { #expect(try Data(contentsOf: backup) == invalid) }
        let recovered = zone("Restaurée", y: 220)
        try JSONEncoder().encode([recovered]).write(to: file, options: .atomic)
        _ = history.record(fresh, element: nil, policy: ZonePolicy())
        #expect(ZoneHistory(path: file.path).records == [fresh, recovered])
    }

    @MainActor @Test func historyIsKeptAcrossRestarts() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec135-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        var dropped: [String] = []
        for index in 0..<21 { dropped += history.record(zone("Zone \(index)", y: Double(index * 30)), element: nil, policy: ZonePolicy()) ?? [] }
        #expect(history.records.count == 20 && dropped == [zone("Zone 0", y: 0).key])
        history.setThumbnail(CGRect(x: 1, y: 2, width: 3, height: 4), for: history.records[0].key)
        let reloaded = ZoneHistory(path: path)
        #expect(reloaded.records == history.records && reloaded.records[0].thumbnailCrop == Rect(x: 1, y: 2, width: 3, height: 4))
        reloaded.forget(reloaded.records[0])
        #expect(ZoneHistory(path: path).records.count == 19)
    }

    /// Photo : 300 × 180 points autour de la zone, gardée dans la fenêtre.
    @MainActor @Test func photoCropsAroundTheZone() {
        let window = CGSize(width: 1200, height: 800)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window, area: CGSize(width: 440, height: 260))
                == CGRect(x: 380, y: 270, width: 440, height: 260))
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 580, y: 390, width: 40, height: 20), windowSize: window).size == CGSize(width: 300, height: 180))
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 10, y: 5, width: 40, height: 20), windowSize: window).origin == .zero)
        #expect(ZoneThumbnails.crop(zone: CGRect(x: 1180, y: 790, width: 10, height: 5), windowSize: window).maxX == 1200)
        #expect(ZoneThumbnails.crop(zone: .zero, windowSize: CGSize(width: 250, height: 150)) == CGRect(x: 0, y: 0, width: 250, height: 150))
        #expect(ZoneThumbnails.fileName("299224|12|-3") == "299224-12--3.png")
    }

    @MainActor @Test func removingZoneDuringCapturePreventsOrphanThumbnail() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec159-thumbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let thumbs = ZoneThumbnails(folder: dir.path)
        let key = "299224|12|8"
        let token = thumbs.beginCapture(for: key)
        // Suppression survenue pendant la capture asynchrone.
        thumbs.remove(key)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cgImage = try #require(context.makeImage())
        let stored = await thumbs.store((cgImage, CGSize(width: 8, height: 8)), key: key, crop: CGRect(x: 0, y: 0, width: 8, height: 8), token: token)
        #expect(!stored)
        #expect(!FileManager.default.fileExists(atPath: thumbs.path(for: key)))
        #expect(thumbs.image(for: key) == nil)

        // Suppression pendant l'écriture détachée : le fichier temporaire est nettoyé, rien n'est publié.
        let midFlightToken = thumbs.beginCapture(for: key)
        let midFlightStored = await thumbs.store(
            (cgImage, CGSize(width: 8, height: 8)),
            key: key,
            crop: CGRect(x: 0, y: 0, width: 8, height: 8),
            token: midFlightToken,
            afterTemporaryWrite: { thumbs.remove(key) }
        )
        #expect(!midFlightStored)
        #expect(!FileManager.default.fileExists(atPath: thumbs.path(for: key)))
        #expect((try FileManager.default.contentsOfDirectory(atPath: dir.path)).isEmpty)
        #expect(thumbs.image(for: key) == nil)

        // Une nouvelle capture valide sur la même clé n'est pas effacée par un ancien jeton obsolète.
        let freshToken = thumbs.beginCapture(for: key)
        #expect(await thumbs.store((cgImage, CGSize(width: 8, height: 8)), key: key, crop: CGRect(x: 0, y: 0, width: 8, height: 8), token: freshToken))
        #expect(!(await thumbs.store((cgImage, CGSize(width: 8, height: 8)), key: key, crop: CGRect(x: 0, y: 0, width: 8, height: 8), token: token)))
        #expect(FileManager.default.fileExists(atPath: thumbs.path(for: key)))
        #expect(thumbs.image(for: key) != nil)

        // Et `setThumbnail` renvoie false si la zone a déjà été oubliée ou si le fichier est illisible.
        let historyPath = dir.appendingPathComponent("zones.json").path
        let history = ZoneHistory(path: historyPath)
        let z = zone("Zone supprimée")
        _ = history.record(z, element: nil, policy: ZonePolicy())
        #expect(history.forget(z))
        #expect(!history.setThumbnail(CGRect(x: 0, y: 0, width: 8, height: 8), for: z.key))
        try Data("{".utf8).write(to: URL(fileURLWithPath: historyPath))
        #expect(!history.setThumbnail(CGRect(x: 0, y: 0, width: 8, height: 8), for: z.key))
    }
}
