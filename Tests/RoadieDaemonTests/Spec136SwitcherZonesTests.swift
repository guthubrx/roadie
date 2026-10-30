import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 136 : zones dans le sélecteur de fenêtres, conservation et zones des clics ordinaires.
struct Spec136SwitcherZonesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func zone(_ title: String, window: UInt32 = 10, y: Double = 40, hoursAgo: Double = 0, click: Bool = false) -> ZoneRecord {
        ZoneRecord(appName: "Excel", bundleID: "com.microsoft.Excel", pid: 7, windowID: window, windowTitle: "Classeur",
                   title: title, relative: Rect(x: 100, y: y, width: 80, height: 20), windowWidth: 1200, windowHeight: 800,
                   date: now.addingTimeInterval(-hoursAgo * 3600), fromClick: click)
    }

    private func window(_ id: UInt32, stage: String = "1") -> WindowSwitcherEntry {
        let snapshot = WindowSnapshot(id: WindowID(rawValue: id), pid: 7, appName: "Excel", bundleID: "com.microsoft.Excel", title: "Classeur \(id)",
                                      frame: Rect(x: 0, y: 0, width: 1200, height: 800), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: DisplayID(rawValue: "main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: stage))
        return WindowSwitcherEntry(window: snapshot, scope: scope, stageName: "Stage \(stage)")
    }

    @Test func policyKeepsRecentZonesAndCapsClicksPerWindow() {
        let policy = ZonePolicy(maxCount: 4, maxAge: 24 * 3600, clicksPerWindow: 2)
        let records = [zone("c1", y: 0, click: true), zone("s1", y: 30), zone("c2", y: 60, click: true), zone("c3", y: 90, click: true),
                       zone("autre", window: 11, y: 0, click: true), zone("vieille", y: 120, hoursAgo: 25)]
        // c3 dépasse les deux zones de clics de la fenêtre 10 ; « vieille » a plus de 24 h ; la recherche n'est pas plafonnée.
        #expect(policy.kept(records, now: now).map(\.title) == ["c1", "s1", "c2", "autre"])
        #expect(ZonePolicy(maxCount: 2).kept(records, now: now).map(\.title) == ["c1", "s1"])
    }

    @Test func zonesBecomeSwitcherEntriesOfTheirWindows() {
        let records = [zone("Développeur", window: 10, y: 0), zone("Fermée", window: 99), zone("Cellule B12", window: 11, y: 30),
                       zone("Fichier", window: 10, y: 60)]
        let built = WindowSwitcherZones.build(records: records, windows: [window(10), window(11, stage: "2")])
        #expect(built.entries.map(\.window.title) == ["Développeur", "Cellule B12", "Fichier"])
        #expect(Set(built.entries.map(\.id)).count == 3 && built.entries.allSatisfy { $0.id.rawValue >= WindowSwitcherZones.firstID })
        #expect(built.entries.map(\.stageName) == ["Stage 1", "Stage 2", "Stage 1"])
        #expect(built.recentIDs == built.entries.map(\.id))
        #expect(built.zones[built.entries[1].id]?.window.id == WindowID(rawValue: 11))
        // Fenêtre 10 au premier plan : elle porte la zone la plus récente, la sélection initiale passe à la suivante.
        var profile = WindowSwitcherShortcutConfig(id: "zones", source: "zones")
        profile.scope = "all"
        let context = WindowSwitcherZones.context(WindowSwitcherContext(focusedWindowID: WindowID(rawValue: 10)), built: built)
        let model = WindowSwitcherModel(entries: built.entries, profile: profile, context: context, recentIDs: built.recentIDs)
        #expect(model.selected?.window.title == "Cellule B12")
        // Ailleurs : la plus récente d'abord.
        let elsewhere = WindowSwitcherZones.context(WindowSwitcherContext(focusedWindowID: WindowID(rawValue: 42)), built: built)
        #expect(WindowSwitcherModel(entries: built.entries, profile: profile, context: elsewhere, recentIDs: built.recentIDs).selected?.window.title
                == "Développeur")
    }

    @Test func clickZoneIsTheSmallElementOrABoxAroundTheClick() {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let button = CGRect(x: 400, y: 300, width: 90, height: 24)
        #expect(ZoneClickRecorder.zone(click: CGPoint(x: 420, y: 310), element: button, window: window) == button)
        // Élément trop grand (zone de texte, page web) : rectangle de 160 × 44 autour du clic, gardé dans la fenêtre.
        #expect(ZoneClickRecorder.zone(click: CGPoint(x: 600, y: 500), element: window, window: window) == CGRect(x: 520, y: 478, width: 160, height: 44))
        #expect(ZoneClickRecorder.zone(click: CGPoint(x: 105, y: 105), element: nil, window: window).origin == CGPoint(x: 100, y: 100))
    }

    @Test func configurationReadsSourceAndZoneSettings() throws {
        #expect(WindowSwitcherShortcutConfig().source == "windows" && WindowSwitcherShortcutConfig(source: "autre").source == "windows")
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: """
            [switcher]
            zone_history_size = 80
            zone_history_hours = 0
            zone_clicks_per_window = 5
            [[switcher.shortcuts]]
            id = "zones"
            hotkey = "alt+tab"
            source = "zones"
            """)
        #expect(config.switcher.zoneHistorySize == 50 && config.switcher.zoneHistoryHours == 1 && config.switcher.zoneClicksPerWindow == 5)
        #expect(config.switcher.shortcuts.first { $0.id == "zones" }?.source == "zones")
        let defaults = WindowSwitcherConfig()
        #expect(defaults.zoneHistorySize == 20 && defaults.zoneHistoryHours == 24 && defaults.zoneClicksPerWindow == 3)
        for id in ["switcher.zone_history_size", "switcher.zone_history_hours", "switcher.zone_clicks_per_window"] {
            #expect(SettingsCatalog.find(id: id)?.category == .selecteur, "\(id)")
        }
        #expect(SettingsCatalog.find(id: "target_mode.zone_history_hotkey") == nil)
    }

    /// Essai du 30 octobre 2026 : ⌥Tab répété doit aller et revenir entre deux zones, comme ⌘Tab entre deux fenêtres
    /// (toutes les zones de l'essai étaient dans la même fenêtre de T3 Code).
    @MainActor @Test func repeatedSwitchesGoBackAndForth() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec136-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let history = ZoneHistory(path: path)
        for (title, y) in [("C", 60.0), ("B", 30), ("A", 0)] {
            history.record(zone(title, y: y), element: nil, policy: ZonePolicy(), now: now)
        }
        var profile = WindowSwitcherShortcutConfig(id: "zones", source: "zones")
        profile.scope = "all"
        func choose() -> String? {
            let built = WindowSwitcherZones.build(records: history.records, windows: [window(10)])
            let context = WindowSwitcherZones.context(WindowSwitcherContext(focusedWindowID: WindowID(rawValue: 10)), built: built)
            let chosen = WindowSwitcherModel(entries: built.entries, profile: profile, context: context, recentIDs: built.recentIDs).selected
            guard let chosen, let record = built.zones[chosen.id]?.record else { return nil }
            history.touch(record, now: now)
            return record.title
        }
        #expect([choose(), choose(), choose()] == ["B", "A", "B"])
    }
}
