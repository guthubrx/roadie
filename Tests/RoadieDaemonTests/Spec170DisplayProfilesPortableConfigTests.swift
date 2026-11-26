import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 170 — Profils matériels d'écrans automatiques (`display_profiles_enabled`) & Export/Import portable.
@Suite(.serialized)
struct Spec170DisplayProfilesPortableConfigTests {
    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec170-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func display(_ id: String, w: Double, h: Double) -> DisplaySnapshot {
        let rect = Rect(x: 0, y: 0, width: w, height: h)
        return DisplaySnapshot(id: DisplayID(rawValue: id), index: 1, name: id, frame: rect, visibleFrame: rect, isMain: true)
    }

    @Test func displayProfilesDisabledByDefaultAndLoadsFromToml() throws {
        let defaults = RoadieConfig()
        #expect(!defaults.tiling.displayProfilesEnabled)

        let dir = try tempDir("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roadies.toml")
        try """
        [tiling]
        display_profiles_enabled = true
        """.write(to: file, atomically: true, encoding: .utf8)

        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(loaded.tiling.displayProfilesEnabled)
        #expect(!RoadieConfigLoader.validate(path: file.path).hasErrors)

        let desc = try #require(SettingsCatalog.find(id: "tiling.display_profiles_enabled"))
        #expect(desc.defaultValue == .bool(false))
    }

    @Test func topologyMatchingAndRecentManualChangeGraceWork() throws {
        let dir = try tempDir("profiles")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DisplayProfileStore(url: dir.appendingPathComponent("display-profiles.json"))
        let service = DisplayProfileService(store: store)

        let laptop = [display("retina-a", w: 1800, h: 1169)]
        let office = [display("retina-a", w: 1800, h: 1169), display("lg-4k-a", w: 3840, h: 2160)]

        _ = try service.saveCurrent(name: "Portable", displays: laptop, tiling: TilingConfig(defaultStrategy: .scrolling, gapsOuter: 4))
        _ = try service.saveCurrent(name: "Bureau", displays: office, tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 10), projectName: "Travail")

        // Même si les UUID d'écrans changent sur un autre Mac/dock, la signature topologique retrouve le profil
        let officeOtherUUIDs = [display("other-lg", w: 3840, h: 2160), display("other-retina", w: 1800, h: 1169)]
        let matchedOffice = try #require(service.match(displays: officeOtherUUIDs))
        #expect(matchedOffice.name == "Bureau")
        #expect(matchedOffice.defaultStrategy == .spatialBsp)
        #expect(matchedOffice.projectName == "Travail")

        let now = Date(timeIntervalSince1970: 2_000_000)
        // Désactivé -> jamais auto-appliqué
        #expect(!DisplayProfileService.shouldAutoApply(enabled: false, lastManualChangeAt: nil, now: now))
        // Activé mais modification manuelle il y a 20 s (< 60 s) -> protégé
        #expect(!DisplayProfileService.shouldAutoApply(enabled: true, lastManualChangeAt: now.addingTimeInterval(-20), now: now))
        // Activé et dernière modif > 60 s -> autorisé
        #expect(DisplayProfileService.shouldAutoApply(enabled: true, lastManualChangeAt: now.addingTimeInterval(-120), now: now))

        #expect(try service.delete(name: "Portable"))
        #expect(service.list().map(\.name) == ["Bureau"])
    }

    @Test func portableExportSanitizesPathsAndImportValidatesAndBacksUp() throws {
        let dir = try tempDir("portable")
        defer { try? FileManager.default.removeItem(at: dir) }

        let srcConfig = dir.appendingPathComponent("src.toml")
        try """
        [tiling]
        default_strategy = "scrolling"
        display_profiles_enabled = true

        [launcher]
        file_excluded_folders = ["/Users/alice/Private"]
        """.write(to: srcConfig, atomically: true, encoding: .utf8)

        let srcProjects = StageProjectStore(path: dir.appendingPathComponent("src-projects.json").path)
        try srcProjects.save(StageProject(
            name: "Dev",
            savedAt: Date(),
            windows: [],
            tree: nil,
            extraURLs: ["/Users/alice/Code/roadie"],
            launchApps: ["com.apple.Terminal"],
            notes: "Workspace principal"
        ))

        let srcProfiles = DisplayProfileStore(url: dir.appendingPathComponent("src-profiles.json"))
        let profileService = DisplayProfileService(store: srcProfiles)
        _ = try profileService.saveCurrent(name: "Bureau", displays: [display("d1", w: 3840, h: 2160)], tiling: TilingConfig(defaultStrategy: .spatialBsp))

        let bundleURL = dir.appendingPathComponent("roadie-export.json")
        let exporter = PortableConfigService()
        let exported = try exporter.exportBundle(
            to: bundleURL,
            configPath: srcConfig.path,
            projectStore: srcProjects,
            profileStore: srcProfiles,
            homeDirectory: "/Users/alice"
        )
        #expect(!exported.configToml.contains("/Users/alice/"))
        #expect(exported.configToml.contains("~/Private"))
        #expect(exported.projects.first?.extraURLs == ["~/Code/roadie"])
        #expect(exported.displayProfiles.count == 1)

        // Import sur un autre Mac : dry-run d'abord
        let dstConfig = dir.appendingPathComponent("dst.toml")
        try "[tiling]\ndefault_strategy = \"bsp\"\n".write(to: dstConfig, atomically: true, encoding: .utf8)
        let dstProjects = StageProjectStore(path: dir.appendingPathComponent("dst-projects.json").path)
        let dstProfiles = DisplayProfileStore(url: dir.appendingPathComponent("dst-profiles.json"))

        let dryReport = exporter.importBundle(
            from: bundleURL,
            configPath: dstConfig.path,
            projectStore: dstProjects,
            profileStore: dstProfiles,
            dryRun: true
        )
        #expect(dryReport.valid && dryReport.dryRun)
        #expect(dryReport.projectsImported == 1 && dryReport.profilesImported == 1)
        #expect(try String(contentsOf: dstConfig, encoding: .utf8).contains("bsp"))

        // Import réel : backup automatique + restauration complète
        let realReport = exporter.importBundle(
            from: bundleURL,
            configPath: dstConfig.path,
            projectStore: dstProjects,
            profileStore: dstProfiles,
            dryRun: false
        )
        #expect(realReport.valid && !realReport.dryRun)
        let bak = try #require(realReport.backupPath)
        #expect(FileManager.default.fileExists(atPath: bak))
        #expect(try String(contentsOf: dstConfig, encoding: .utf8).contains("scrolling"))
        #expect(dstProjects.load().projects[LauncherMatch.fold("Dev")] != nil)
        #expect(dstProfiles.load().profiles.count == 1)
    }
}
