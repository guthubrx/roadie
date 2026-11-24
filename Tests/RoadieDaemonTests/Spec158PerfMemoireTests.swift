import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 158 — Réutilisation des vues NavRail, cache d'icônes partagé et purge mémoire Overview.
@Suite(.serialized) @MainActor
struct Spec158PerfMemoireTests {
    private func member(_ id: UInt32, bundleID: String = "com.example.spec158", title: String = "Fenêtre") -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: id),
            bundleID: bundleID,
            title: title,
            frame: Rect(x: 0, y: 0, width: 320, height: 240)
        )
    }

    private func solidImage(
        width: Int = 64,
        height: Int = 64,
        borderColor: (UInt8, UInt8, UInt8, UInt8),
        centerColor: (UInt8, UInt8, UInt8, UInt8)
    ) throws -> NSImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let inCenter = x >= 16 && x < width - 16 && y >= 16 && y < height - 16
                let color = inCenter ? centerColor : borderColor
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = color.3
            }
        }
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        let cgImage = try #require(context.makeImage())
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func pixelRGBA(of image: NSImage, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8, UInt8) {
        let width = 64
        let height = 64
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        context.draw(cg, in: rect)
        let offset = y * bytesPerRow + x * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    @Test func railPanelRenderReusesStageCardsAndHeaderInPlace() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        config.displayLabel.enabled = true
        config.headerPosition = .top
        let stageA = PersistentStage(id: StageID(rawValue: "stage-a"), name: "Travail", members: [member(1)])
        let stageB = PersistentStage(id: StageID(rawValue: "stage-b"), name: "Web", members: [member(2)])
        let scope1 = PersistentStageScope(displayID: DisplayID(rawValue: "spec158-disp"), activeStageID: stageA.id, stages: [stageA, stageB])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spec158-rail-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        panel.position(
            on: screen,
            displayID: scope1.displayID,
            config: config,
            runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path)
        )
        let thumbnails = RailThumbnailStore()
        let liveIDs: Set<WindowID> = [WindowID(rawValue: 1), WindowID(rawValue: 2)]

        panel.render(
            content: RailDisplayContent(scope: scope1, presentationStates: [:], liveWindowIDs: liveIDs),
            displayName: "LG 4K",
            config: config,
            thumbnails: thumbnails,
            recordingStatus: nil,
            recordingIndicatorBottomOffset: 0
        )

        let cardsBefore = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        let headerBefore = panel.stack.arrangedSubviews.compactMap { $0 as? RailHeaderView }.first
        #expect(cardsBefore.count == 2)
        #expect(headerBefore != nil)

        // Deuxième rendu avec changement de stage active et de nom : mêmes instances réutilisées en place.
        let stageBRenamed = PersistentStage(id: StageID(rawValue: "stage-b"), name: "Navigation", members: [member(2, title: "Docs")])
        let scope2 = PersistentStageScope(displayID: scope1.displayID, activeStageID: stageB.id, stages: [stageA, stageBRenamed])
        panel.render(
            content: RailDisplayContent(scope: scope2, presentationStates: [:], liveWindowIDs: liveIDs),
            displayName: "LG 4K",
            config: config,
            thumbnails: thumbnails,
            recordingStatus: nil,
            recordingIndicatorBottomOffset: 0
        )

        let cardsAfter = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        let headerAfter = panel.stack.arrangedSubviews.compactMap { $0 as? RailHeaderView }.first
        #expect(cardsAfter.count == 2)
        #expect(zip(cardsBefore, cardsAfter).allSatisfy { $0 === $1 })
        #expect(headerBefore === headerAfter)
        #expect(cardsAfter[1].toolTip?.contains("Navigation") == true)

        // Réorganisation : les mêmes instances de cartes sont réutilisées dans le nouvel ordre.
        let scopeReordered = PersistentStageScope(displayID: scope1.displayID, activeStageID: stageB.id, stages: [stageBRenamed, stageA])
        panel.render(
            content: RailDisplayContent(scope: scopeReordered, presentationStates: [:], liveWindowIDs: liveIDs),
            displayName: "LG 4K",
            config: config,
            thumbnails: thumbnails,
            recordingStatus: nil,
            recordingIndicatorBottomOffset: 0
        )
        let cardsReordered = panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        #expect(cardsReordered.count == 2)
        #expect(cardsReordered[0] === cardsBefore[1])
        #expect(cardsReordered[1] === cardsBefore[0])
    }

    @Test func sharedAppIconCacheStripsWhiteBorderAndFastPathsTransparentBorder() throws {
        // 1) Icône avec cadre blanc au bord et carré bleu au centre : le bord devient transparent, le centre reste intact.
        let withWhiteBorder = try solidImage(borderColor: (250, 250, 250, 255), centerColor: (30, 120, 220, 255))
        let cleanedWhite = SharedAppIconCache.cleanEdgeWhiteBackground(of: withWhiteBorder)
        let corner = try pixelRGBA(of: cleanedWhite, x: 2, y: 2)
        let center = try pixelRGBA(of: cleanedWhite, x: 32, y: 32)
        #expect(corner.3 == 0)
        #expect(center.3 == 255)
        #expect(center.2 > 180)

        // 2) Icône à bord déjà transparent et centre blanc : court-circuit sans BFS, le centre blanc est préservé.
        let transparentBorder = try solidImage(borderColor: (0, 0, 0, 0), centerColor: (252, 252, 252, 255))
        let cleanedTransparent = SharedAppIconCache.cleanEdgeWhiteBackground(of: transparentBorder)
        let corner2 = try pixelRGBA(of: cleanedTransparent, x: 2, y: 2)
        let center2 = try pixelRGBA(of: cleanedTransparent, x: 32, y: 32)
        #expect(corner2.3 == 0)
        #expect(center2.3 == 255)
        #expect(center2.0 >= 245 && center2.1 >= 245 && center2.2 >= 245)
    }

    @Test func sharedAppIconCacheEvictsOldestQuarterInsteadOfClearingAll() throws {
        let cache = SharedAppIconCache()
        let dummy = try solidImage(borderColor: (0, 0, 0, 0), centerColor: (40, 160, 80, 255))
        for index in 0..<SharedAppIconCache.maxCount {
            cache.storeCleanedIconForTesting(dummy, for: "com.example.app.\(index)")
        }
        #expect(cache.cleanedIconCount == SharedAppIconCache.maxCount)

        // L'ajout d'une 65e entrée évince le quart le plus ancien (16 entrées), pas la totalité du cache.
        cache.storeCleanedIconForTesting(dummy, for: "com.example.app.overflow")
        let expectedCount = SharedAppIconCache.maxCount - (SharedAppIconCache.maxCount / 4) + 1
        #expect(cache.cleanedIconCount == expectedCount)
        #expect(cache.cleanedIcon(for: "com.example.app.overflow") != nil)

        cache.purge()
        #expect(cache.cleanedIconCount == 0)
    }

    @Test func overviewWallpaperCapsThumbnailsAndPurgesCleanly() throws {
        OverviewWallpaper.purge()
        defer { OverviewWallpaper.purge() }
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let context = try #require(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ))
        let image = try #require(context.makeImage())

        for index in 0..<(OverviewWallpaper.maxCachedThumbnails + 3) {
            OverviewWallpaper.storeThumbnailForTesting(image, key: "wallpaper-\(index)")
        }
        #expect(OverviewWallpaper.cachedImageCount == OverviewWallpaper.maxCachedThumbnails)

        OverviewWallpaper.purge()
        #expect(OverviewWallpaper.cachedImageCount == 0)
    }
}
