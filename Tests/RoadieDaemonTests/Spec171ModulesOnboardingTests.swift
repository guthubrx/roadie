import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 171 — Tableau de bord central Modules on/off et checklist Onboarding 1er lancement.
@Suite(.serialized)
struct Spec171ModulesOnboardingTests {
    @Test func everyModuleMapsToAnExistingBooleanSettingDescriptor() throws {
        #expect(RoadieModuleCatalog.all.count >= 14)
        let ids = RoadieModuleCatalog.all.map(\.settingID)
        #expect(Set(ids).count == ids.count)

        for module in RoadieModuleCatalog.all {
            let descriptor = try #require(SettingsCatalog.find(id: module.settingID), "Module orphelin : \(module.settingID)")
            #expect(descriptor.kind == .bool, "Le module \(module.settingID) doit être un interrupteur booléen")
            #expect(!module.titleFR.isEmpty && !module.titleEN.isEmpty)
            #expect(!module.summaryFR.isEmpty && !module.summaryEN.isEmpty)
            if module.offByDefault {
                #expect(descriptor.defaultValue == .bool(false), "\(module.settingID) marqué offByDefault mais défaut != false")
            } else {
                #expect(descriptor.defaultValue == .bool(true), "\(module.settingID) défaut attendu true")
            }
        }

        // Vérifier que les 3 nouveaux modules (Specs 168-170) sont présents et que OCR / Profils sont éteints par défaut
        #expect(ids.contains("target_mode.file_dialog_jump"))
        #expect(ids.contains("app_targets.ocr_fallback"))
        #expect(ids.contains("tiling.display_profiles_enabled"))
    }

    @Test func onboardingChecklistReportsReadyAndMissingSteps() {
        let missing = OnboardingChecklist.evaluate(
            permissions: PermissionSnapshot(accessibilityTrusted: false, screenRecordingGranted: false),
            config: RoadieConfig(),
            configFileExists: false
        )
        #expect(!missing.ready)
        #expect(missing.steps.first(where: { $0.id == "accessibility" })?.done == false)
        #expect(missing.steps.first(where: { $0.id == "config_file" })?.done == false)
        #expect(missing.quickActions.count == 3)

        let ready = OnboardingChecklist.evaluate(
            permissions: PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true),
            config: RoadieConfig(rules: [], shortcuts: [CommandShortcut(keys: "alt+h", command: "focus left")]),
            configFileExists: true
        )
        #expect(ready.ready)
        #expect(ready.steps.allSatisfy { $0.done })
    }

    @Test func launcherHistoryNavigatorStepsOlderNewerAndRestoresDraft() throws {
        var nav = LauncherHistoryNavigator(entries: ["safari perso", "12*4.5", "cb devis"])
        #expect(!nav.isActive)

        // ↑ depuis une barre vide rappelle la plus récente, puis les plus anciennes jusqu'au bout
        #expect(nav.stepOlder(currentQuery: "") == "safari perso")
        #expect(nav.isActive)
        #expect(nav.stepOlder(currentQuery: "safari perso") == "12*4.5")
        #expect(nav.stepOlder(currentQuery: "12*4.5") == "cb devis")
        #expect(nav.stepOlder(currentQuery: "cb devis") == nil)

        // ↓ redescend vers plus récent puis restaure le brouillon initial
        #expect(nav.stepNewer() == "12*4.5")
        #expect(nav.stepNewer() == "safari perso")
        #expect(nav.stepNewer() == "")
        #expect(!nav.isActive)

        // Si la requête courante est déjà la dernière entrée (reprise 5 min), ↑ saute directement à la précédente
        #expect(nav.stepOlder(currentQuery: "safari perso") == "12*4.5")
        #expect(nav.stepNewer() == "safari perso")
        #expect(!nav.isActive)

        // Le réglage interrupteur existe et vaut true par défaut
        let defaults = RoadieConfig()
        #expect(defaults.experimental.targetMode.historyArrowNavigation)
        let desc = try #require(SettingsCatalog.find(id: "target_mode.history_arrow_navigation"))
        #expect(desc.defaultValue == .bool(true))
    }
}
