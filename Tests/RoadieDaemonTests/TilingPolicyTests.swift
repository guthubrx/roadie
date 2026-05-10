import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct TilingPolicyTests {
    private func window(
        id: UInt32 = 1,
        bundleID: String = "com.example.app",
        appName: String = "ExampleApp",
        title: String = "Window 1",
        frame: Rect = Rect(x: 0, y: 0, width: 800, height: 600),
        isTileCandidate: Bool = true,
        subrole: String? = "AXStandardWindow",
        role: String? = "AXWindow",
        furniture: WindowFurniture? = nil
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 1234,
            appName: appName,
            bundleID: bundleID,
            title: title,
            frame: frame,
            isOnScreen: true,
            isTileCandidate: isTileCandidate,
            subrole: subrole,
            role: role,
            furniture: furniture
        )
    }

    private func config(
        allowedSubroles: [String] = ["AXStandardWindow"],
        floatingBundles: [String] = [],
        rules: [WindowRule] = []
    ) -> RoadieConfig {
        RoadieConfig(
            tiling: TilingConfig(allowedSubroles: allowedSubroles),
            exclusions: ExclusionsConfig(floatingBundles: floatingBundles),
            rules: rules
        )
    }

    @Test
    func standardWindowIsTiled() {
        let result = SnapshotService.applyTilingPolicy(to: window(), config: config())
        #expect(result.isTileCandidate == true)
    }

    @Test
    func modalStandardWindowIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(furniture: WindowFurniture(
                hasCloseButton: true,
                hasFullscreenButton: true,
                fullscreenButtonEnabled: true,
                isFocused: true,
                isMain: true,
                isModal: true
            )),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func smallSettingsWindowIsExcludedEvenWhenStandard() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                title: "Finder Settings",
                frame: Rect(x: 0, y: 0, width: 420, height: 360),
                furniture: WindowFurniture(hasCloseButton: true, hasMinimizeButton: true, isResizable: false)
            ),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func smallNonResizableStandardProgressWindowIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                bundleID: "dev.orbstack.OrbStack",
                appName: "OrbStack",
                title: "Updating OrbStack",
                frame: Rect(x: 0, y: 0, width: 400, height: 140),
                furniture: WindowFurniture(
                    hasCloseButton: true,
                    hasMinimizeButton: true,
                    isMain: true,
                    isResizable: false
                )
            ),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func smallResizableStandardWindowStillTiles() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                title: "Small Utility",
                frame: Rect(x: 0, y: 0, width: 420, height: 360),
                furniture: WindowFurniture(
                    hasCloseButton: true,
                    hasMinimizeButton: true,
                    isMain: true,
                    isResizable: true
                )
            ),
            config: config()
        )
        #expect(result.isTileCandidate == true)
    }

    @Test
    func unidentifiedSmallUntitledWindowIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                title: "",
                frame: Rect(x: 0, y: 0, width: 420, height: 360),
                subrole: nil,
                role: nil,
                furniture: nil
            ),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func unidentifiedLittleSnitchUrlPanelIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                bundleID: "at.obdev.littlesnitch",
                appName: "Little Snitch",
                title: "Untitled",
                frame: Rect(x: 1361, y: 248, width: 550, height: 166),
                subrole: nil,
                role: nil,
                furniture: nil
            ),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func unidentifiedSmallDocumentWindowStillTilesWhenNotPanelShaped() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(
                title: "Document",
                frame: Rect(x: 0, y: 0, width: 420, height: 360),
                subrole: nil,
                role: nil,
                furniture: nil
            ),
            config: config()
        )
        #expect(result.isTileCandidate == true)
    }

    @Test
    func manageRuleCanForceModalWindow() {
        let rule = WindowRule(
            id: "force-modal",
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(manage: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(furniture: WindowFurniture(isModal: true)),
            config: config(rules: [rule])
        )
        #expect(result.isTileCandidate == true)
    }

    @Test
    func dialogSubroleIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXDialog"),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func floatingWindowSubroleIsExcluded() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXFloatingWindow"),
            config: config()
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func unknownSubroleFallsBackToTileCandidateFlag() {
        // AX absent (app sandboxee) -> on respecte la decision CG d'origine.
        let tiled = SnapshotService.applyTilingPolicy(
            to: window(isTileCandidate: true, subrole: nil),
            config: config()
        )
        #expect(tiled.isTileCandidate == true)

        let nonTiled = SnapshotService.applyTilingPolicy(
            to: window(isTileCandidate: false, subrole: nil),
            config: config()
        )
        #expect(nonTiled.isTileCandidate == false)
    }

    @Test
    func customAllowedSubrolesPermitsDialog() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXDialog"),
            config: config(allowedSubroles: ["AXStandardWindow", "AXDialog"])
        )
        #expect(result.isTileCandidate == true)
    }

    @Test
    func floatingBundlesExcludesEntireApp() {
        let result = SnapshotService.applyTilingPolicy(
            to: window(bundleID: "com.apple.systempreferences"),
            config: config(floatingBundles: ["com.apple.systempreferences"])
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func ruleManageOverridesSubroleExclusion() {
        // Une fenetre AXDialog devrait etre tilee si une regle force action.manage = true
        let rule = WindowRule(
            id: "force-tile-myapp",
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(manage: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXDialog"),
            config: config(rules: [rule])
        )
        #expect(result.isTileCandidate == true)
    }

    @Test
    func ruleExcludeOverridesEvenStandardWindow() {
        let rule = WindowRule(
            id: "exclude-prefs",
            match: RuleMatch(titleRegex: "(Preferences|Settings|Edit Session)"),
            action: RuleAction(exclude: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(title: "Edit Session"),
            config: config(rules: [rule])
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func ruleFloatingBehavesLikeExclude() {
        let rule = WindowRule(
            id: "floating-rule",
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(floating: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(),
            config: config(rules: [rule])
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func ruleSubroleMatchTargetsDialogsOnly() {
        // Une regle avec match.subrole = "AXDialog" cible uniquement les dialogs
        let rule = WindowRule(
            id: "manage-dialogs",
            match: RuleMatch(subrole: "AXDialog"),
            action: RuleAction(manage: true)
        )
        let dialog = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXDialog"),
            config: config(rules: [rule])
        )
        let standard = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXStandardWindow"),
            config: config(rules: [rule])
        )
        #expect(dialog.isTileCandidate == true)
        #expect(standard.isTileCandidate == true)
    }

    @Test
    func ruleManageDoesNotForceTilingIfBaseCriteriaFailed() {
        // Si la fenetre est trop petite (isTileCandidate = false par CG), une regle
        // manage = true ne force pas l'inclusion.
        let rule = WindowRule(
            id: "force-tile",
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(manage: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(isTileCandidate: false),
            config: config(rules: [rule])
        )
        #expect(result.isTileCandidate == false)
    }

    @Test
    func popupWithoutFurnitureIsExcluded() {
        // Une "fenetre" AX sans aucun bouton ni focus -> popup/tooltip
        let popup = WindowSnapshot(
            id: WindowID(rawValue: 99), pid: 1, appName: "Popup", bundleID: "com.x",
            title: "", frame: Rect(x: 0, y: 0, width: 200, height: 100),
            isOnScreen: true, isTileCandidate: true,
            subrole: "AXUnknown",
            furniture: WindowFurniture()  // tout false -> popup
        )
        let result = SnapshotService.applyTilingPolicy(to: popup, config: config())
        #expect(result.isTileCandidate == false)
    }

    @Test
    func popupGateRespectsToggle() {
        let popup = WindowSnapshot(
            id: WindowID(rawValue: 99), pid: 1, appName: "Popup", bundleID: "com.x",
            title: "", frame: Rect(x: 0, y: 0, width: 200, height: 100),
            isOnScreen: true, isTileCandidate: true,
            subrole: "AXUnknown",
            furniture: WindowFurniture()
        )
        let cfg = RoadieConfig(
            tiling: TilingConfig(
                allowedSubroles: ["AXStandardWindow", "AXUnknown"],
                popupFilter: false  // explicitly off
            )
        )
        let result = SnapshotService.applyTilingPolicy(to: popup, config: cfg)
        #expect(result.isTileCandidate == true)
    }

    @Test
    func windowWithFullscreenButtonIsConsideredReal() {
        // Meme si subrole = AXDialog, si on a fullscreenButton + isMain -> popup gate ne s'applique pas
        // (mais subrole gate exclut quand meme).
        let dialog = WindowSnapshot(
            id: WindowID(rawValue: 99), pid: 1, appName: "App", bundleID: "com.x",
            title: "", frame: Rect(x: 0, y: 0, width: 200, height: 100),
            isOnScreen: true, isTileCandidate: true,
            subrole: "AXDialog",
            furniture: WindowFurniture(hasFullscreenButton: true, isMain: true)
        )
        let result = SnapshotService.applyTilingPolicy(to: dialog, config: config())
        // popup gate OK (a des boutons), mais subrole gate exclut quand meme
        #expect(result.isTileCandidate == false)
    }

    @Test
    func standardWindowAlwaysPassesPopupGate() {
        // Un AXStandardWindow passe la popup gate meme sans aucun bouton (cas edge improbable).
        let win = WindowSnapshot(
            id: WindowID(rawValue: 1), pid: 1, appName: "App", bundleID: "com.x",
            title: "Main", frame: Rect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true, isTileCandidate: true,
            subrole: "AXStandardWindow",
            furniture: WindowFurniture()  // pas de boutons
        )
        let result = SnapshotService.applyTilingPolicy(to: win, config: config())
        #expect(result.isTileCandidate == true)
    }

    @Test
    func windowFurnitureIsLikelyRealWindowLogic() {
        let empty = WindowFurniture()
        #expect(empty.isLikelyRealWindow == false)

        let close = WindowFurniture(hasCloseButton: true)
        #expect(close.isLikelyRealWindow == true)

        let focused = WindowFurniture(isFocused: true)
        #expect(focused.isLikelyRealWindow == true)
    }

    @Test
    func priorityOrdersRulesCorrectly() {
        // Rule de priorite haute = "manage", rule basse = "exclude". Manage gagne.
        let manageRule = WindowRule(
            id: "manage",
            priority: 100,
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(manage: true)
        )
        let excludeRule = WindowRule(
            id: "exclude",
            priority: 1,
            match: RuleMatch(app: "ExampleApp"),
            action: RuleAction(exclude: true)
        )
        let result = SnapshotService.applyTilingPolicy(
            to: window(subrole: "AXDialog"),
            config: config(rules: [excludeRule, manageRule])
        )
        #expect(result.isTileCandidate == true)
    }
}
