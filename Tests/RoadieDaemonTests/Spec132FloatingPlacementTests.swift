import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 132 : fenêtres flottantes décalées hors du rail à leur apparition, et place retenue par règle.
struct Spec132FloatingPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

    private func window(_ id: UInt32, _ frame: CGRect, title: String = "a.txt Info", onScreen: Bool = true) -> WindowSnapshot {
        WindowSnapshot(id: WindowID(rawValue: id), pid: 690, appName: "Finder", bundleID: "com.apple.finder", title: title,
                       frame: Rect(frame), isOnScreen: onScreen, isTileCandidate: false, subrole: "AXStandardWindow", role: "AXWindow")
    }

    private func store() -> FloatingFrameStore {
        FloatingFrameStore(path: FileManager.default.temporaryDirectory.appendingPathComponent("spec132-\(UUID().uuidString).json").path)
    }

    @Test func windowsOpeningOverTheRailMoveToItsRight() {
        let info = CGRect(x: 10, y: 10, width: 390, height: 1000)
        #expect(FloatingPlacement.placement(for: info, displays: [screen], railWidth: 150, avoidRail: true, remembered: nil)
                == CGRect(x: 158, y: 10, width: 390, height: 1000))
        // Sur le second écran, le rail est à son bord gauche.
        #expect(FloatingPlacement.placement(for: info.offsetBy(dx: 1920, dy: 0), displays: [screen, right], railWidth: 150, avoidRail: true,
                                            remembered: nil)?.minX == 2078)
        // Déjà à droite du rail, réglage coupé, ou trop large pour tenir : rien ne bouge.
        #expect(FloatingPlacement.placement(for: info.offsetBy(dx: 200, dy: 0), displays: [screen], railWidth: 150, avoidRail: true, remembered: nil) == nil)
        #expect(FloatingPlacement.placement(for: info, displays: [screen], railWidth: 150, avoidRail: false, remembered: nil) == nil)
        #expect(FloatingPlacement.placement(for: CGRect(x: 0, y: 0, width: 1900, height: 900), displays: [screen], railWidth: 150,
                                            avoidRail: true, remembered: nil) == nil)
    }

    @Test func rememberedPlaceWinsWhileItsScreenIsThere() {
        let info = CGRect(x: 10, y: 10, width: 390, height: 1000)
        let kept = CGRect(x: 2400, y: 80, width: 500, height: 700)
        #expect(FloatingPlacement.placement(for: info, displays: [screen, right], railWidth: 150, avoidRail: true, remembered: kept) == kept)
        // Écran débranché : la place retenue est ignorée, le rail reste évité.
        #expect(FloatingPlacement.placement(for: info, displays: [screen], railWidth: 150, avoidRail: true, remembered: kept)?.minX == 158)
        // Déjà à sa place : aucune écriture.
        #expect(FloatingPlacement.placement(for: kept, displays: [screen, right], railWidth: 150, avoidRail: true, remembered: kept) == nil)
    }

    @Test func onlyAppearingWindowsMoveAndMovedOnesAreRemembered() {
        let frames = store()
        defer { try? FileManager.default.removeItem(atPath: frames.path) }
        let placement = FloatingPlacement(store: frames)
        let key: (WindowSnapshot) -> String? = { $0.appName == "Finder" ? "finder-get-info" : nil }
        func observe(_ windows: [WindowSnapshot]) -> [FloatingPlacement.Move] {
            placement.observe(windows, displays: [screen, right], avoidRail: true, railWidth: { 150 }, key: key)
        }
        // Au démarrage, une fenêtre déjà ouverte sur le rail reste où elle est.
        let old = window(1, CGRect(x: 10, y: 10, width: 300, height: 300))
        #expect(observe([old]).isEmpty)
        // Une fenêtre qui apparaît sur le rail est décalée.
        let info = window(2, CGRect(x: 10, y: 10, width: 390, height: 1000))
        let moves = observe([old, info])
        #expect(moves.map(\.frame) == [CGRect(x: 158, y: 10, width: 390, height: 1000)] && moves.first?.reason == "rail")
        placement.applied(info.id, frame: moves[0].frame)
        #expect(observe([old, window(2, moves[0].frame)]).isEmpty)
        #expect(frames.load().isEmpty)
        // L'utilisateur la déplace et l'agrandit : la place est retenue sous l'identifiant de la règle.
        let kept = CGRect(x: 2400, y: 80, width: 500, height: 700)
        #expect(observe([old, window(2, kept)]).isEmpty)
        #expect(frames.load()["finder-get-info"]?.cgRect == kept)
        // Elle est fermée, une autre fiche s'ouvre : elle reprend cette place, même après un redémarrage.
        let reopened = FloatingPlacement(store: frames)
        _ = reopened.observe([old], displays: [screen, right], avoidRail: true, railWidth: { 150 }, key: key)
        let next = reopened.observe([old, window(3, CGRect(x: 10, y: 10, width: 390, height: 1000), title: "b.pdf Info")],
                                    displays: [screen, right], avoidRail: true, railWidth: { 150 }, key: key)
        #expect(next.map(\.frame) == [kept] && next.first?.reason == "remembered")
    }

    @Test func windowsWithoutTheChoiceAreNotRemembered() {
        let frames = store()
        defer { try? FileManager.default.removeItem(atPath: frames.path) }
        let placement = FloatingPlacement(store: frames)
        _ = placement.observe([], displays: [screen], avoidRail: true, railWidth: { 150 }, key: { _ in nil })
        let note = window(4, CGRect(x: 400, y: 100, width: 300, height: 200), title: "Note")
        _ = placement.observe([note], displays: [screen], avoidRail: true, railWidth: { 150 }, key: { _ in nil })
        _ = placement.observe([window(4, CGRect(x: 600, y: 100, width: 300, height: 200), title: "Note")],
                              displays: [screen], avoidRail: true, railWidth: { 150 }, key: { _ in nil })
        #expect(frames.load().isEmpty)
    }

    @Test func rulesAndListRowsChooseToRememberThePlace() throws {
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: """
            [exclusions]
            floating_avoid_rail = false
            [[exclusions.floating_windows]]
            app = "Thunderbird"
            title = "# Reminder"
            remember_frame = true
            [[rules]]
            id = "finder-get-info"
            match = { app = "Finder", title_regex = " Info$" }
            action = { exclude = true, remember_frame = true }
            """)
        #expect(config.exclusions.floatingAvoidRail == false)
        #expect(RoadieConfig().exclusions.floatingAvoidRail)
        let rules = config.rules + FloatingWindowTitles.rules(config.exclusions.floatingWindows)
        #expect(FloatingPlacement.rememberKey(for: window(5, .zero), rules: rules) == "finder-get-info")
        var reminder = window(6, .zero, title: "2 Reminders")
        reminder.appName = "Thunderbird"
        #expect(FloatingPlacement.rememberKey(for: reminder, rules: rules)?.hasPrefix(FloatingWindowTitles.rulePrefix) == true)
        // Sans la case, la règle ne retient rien.
        let plain = FloatingWindowTitles.rules([FloatingWindowConfig(app: "Thunderbird", title: "# Reminder")])
        #expect(FloatingPlacement.rememberKey(for: reminder, rules: plain) == nil)
        // Le validateur connaît les nouvelles clés.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("spec132-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[exclusions]\nfloating_avoid_rail = false\n[[exclusions.floating_windows]]\napp = \"T\"\ntitle = \"x\"\nremember_frame = true\n"
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(RoadieConfigLoader.validate(path: file.path).items.allSatisfy { !$0.message.contains("remember_frame") && !$0.message.contains("floating_avoid_rail") })
    }

    @Test func candidatesAreUnmanagedRealWindowsOfOtherApps() {
        let display = DisplaySnapshot(id: DisplayID(rawValue: "main"), index: 1, name: "main", frame: Rect(screen), visibleFrame: Rect(screen), isMain: true)
        var dialog = window(8, .zero)
        dialog.subrole = "AXDialog"
        var panel = window(9, .zero)
        panel.subrole = "AXFloatingWindow"
        var own = window(10, .zero)
        own.pid = 42
        var tiled = window(11, .zero)
        tiled.isTileCandidate = true
        let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [display],
                                      windows: [window(7, .zero), dialog, panel, own, tiled].map { ScopedWindowSnapshot(window: $0, scope: nil) },
                                      state: RoadieState())
        #expect(FloatingPlacement.candidates(in: snapshot, ownPID: 42).map(\.id.rawValue) == [7, 8])
    }
}
