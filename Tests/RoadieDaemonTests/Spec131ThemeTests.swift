import AppKit
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 131 : thèmes de barre en verre d'Alfred 6.
struct Spec131ThemeTests {
    @Test func glassyThemesAreBuiltIn() throws {
        let dark = try #require(LauncherTheme.builtIn.first { $0.id == "glassy-dark" })
        let light = try #require(LauncherTheme.builtIn.first { $0.id == "glassy-light" })
        #expect(dark.name == "Glassy Dark" && dark.effect == .dark && dark.blurAppearance == .darkAqua)
        #expect(light.name == "Glassy Light" && light.effect == .light && light.blurAppearance == .aqua)
        #expect(dark.selectedBackground == "#358188E6" && light.selectedBackground == "accent")
        #expect(dark.roundness == 22 && dark.searchRoundness == 14 && dark.rowRoundness == 14)
        #expect(LauncherThemeCatalog.all().contains { $0.id == "glassy-dark" })
    }

    @Test func workflowViewStyleSetting() throws {
        #expect(TargetModeConfig().workflowViewStyle == "system")
        #expect(TargetModeConfig(workflowViewStyle: "inconnu").workflowViewStyle == "system")
        let descriptor = try #require(SettingsCatalog.find(id: "target_mode.workflow_view_style"))
        #expect(descriptor.choiceLabel("glassy-dark") == "Glassy Dark" && descriptor.choiceLabel("system") == "Comme macOS")
        #expect(Set(WorkflowViewStyle.allCases.map(\.rawValue)) == Set(TargetModeConfig.workflowViewStyles))
    }

    @MainActor @Test func stylesShapeThePanelAndItsInput() {
        func panel() -> NSPanel {
            NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable, .nonactivatingPanel],
                    backing: .buffered, defer: true)
        }
        let dark = panel(), effect = NSVisualEffectView(), field = NSTextField()
        WorkflowViewStyle.glassyDark.prepare(dark, effect: effect)
        WorkflowViewStyle.glassyDark.decorate(field)
        #expect(dark.appearance?.name == .darkAqua && effect.material == .hudWindow && dark.titlebarAppearsTransparent)
        #expect(field.isBezeled == false && (field.layer?.borderWidth ?? 0) > 0)

        let flat = NSTextField()
        WorkflowViewStyle.flatDark.decorate(flat)
        #expect(flat.layer?.borderWidth == 0 && flat.layer?.backgroundColor != nil)

        let light = panel(), lightEffect = NSVisualEffectView()
        WorkflowViewStyle.glassyLight.prepare(light, effect: lightEffect)
        #expect(light.appearance?.name == .aqua)

        let system = panel(), systemEffect = NSVisualEffectView(), plain = NSTextField()
        WorkflowViewStyle.system.prepare(system, effect: systemEffect)
        WorkflowViewStyle.system.decorate(plain)
        #expect(!system.titlebarAppearsTransparent && systemEffect.material == .popover && plain.isBezeled)
        let content = NSView()
        #expect(WorkflowViewStyle.system.wrap(content, in: system) === content)
        #expect(WorkflowViewStyle.flatDark.wrap(NSView(), in: panel()) is NSVisualEffectView)
    }
}
