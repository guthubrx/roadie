import AppKit
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

struct Spec057SettingsTests {
    @Test func everySettingBelongsToExactlyOneNamedGroup() {
        for category in SettingCategory.allCases {
            let entries = SettingsCatalog.descriptors(in: category)
            let groups = SettingsOrganization.groups(entries)
            let ids = groups.flatMap(\.descriptors).map(\.id)
            #expect(ids.count == entries.count)
            #expect(Set(ids) == Set(entries.map(\.id)))
            #expect(groups.allSatisfy { !$0.title.isEmpty && !$0.descriptors.isEmpty })
        }
    }

    @Test func oldProfilesKeepTheirManagerAndReleaseBehavior() {
        #expect(WindowSwitcherShortcutConfig(hotkey: "ctrl+alt+tab").triggerSource == "roadie")
        #expect(WindowSwitcherShortcutConfig().triggerSource == "external")
        let profile = WindowSwitcherShortcutConfig(releaseAction: "search", triggerSource: "btt")
        #expect(profile.releaseAction == "search")
        #expect(profile.arrowNavigation && profile.mouseHover)
    }

    @Test func physicalTabIsRecordedAsTabAndDisplayedAsSymbols() {
        let value = ShortcutCapture.value(keyCode: 48, modifiers: [.command, .option], layout: [:])
        #expect(value == "alt+command+tab")
        #expect(ShortcutCapture.label(value ?? "") == "⌥ ⌘ ⇥")
        #expect(WindowSwitcherHotkey.parse(value ?? "", layout: [:])?.keyCode == 48)
    }

    @Test func keyboardLayoutAndSpecialPhysicalKeysRemainResolvable() {
        let value = ShortcutCapture.value(keyCode: 0, modifiers: .control, layout: [0: "q"])
        #expect(value == "control+q")
        #expect(WindowSwitcherHotkey.parse(value ?? "", layout: [0: "q"])?.keyCode == 0)
        let other = ShortcutCapture.value(keyCode: 24, modifiers: .command, layout: [24: "+"])
        #expect(WindowSwitcherHotkey.parse(other ?? "", layout: [:])?.keyCode == 24)
        #expect(ShortcutCapture.value(keyCode: 48, modifiers: [], layout: [:]) == nil)
    }

    @Test func directionalNavigationKeepsGeometryAndHandlesIncompleteRows() {
        let frames = (0..<5).map { CGRect(x: ($0 % 3) * 100, y: ($0 / 3) * 80, width: 90, height: 70) }
        #expect(SwitcherNavigation.destination(from: 1, direction: .right, frames: frames) == 2)
        #expect(SwitcherNavigation.destination(from: 2, direction: .down, frames: frames) == 4)
        #expect(SwitcherNavigation.destination(from: 3, direction: .up, frames: frames) == 0)
        #expect(SwitcherNavigation.destination(from: 0, direction: .left, frames: frames) == nil)
        #expect(SwitcherNavigation.destination(from: 0, direction: .down, frames: []) == nil)
    }

    @Test func contextualVisibilityPreservesExplicitChoices() {
        #expect(!SwitcherNavigation.visible("auto", automatic: false))
        #expect(SwitcherNavigation.visible("always", automatic: false))
        #expect(!SwitcherNavigation.visible("never", automatic: true))
    }
}

final class Spec057FakeBTT: BTTShortcutAPI, @unchecked Sendable {
    var values: [String: String] = [:]
    var writes: [String] = []
    var failCreateAt = 0
    var created = 0

    func list() throws -> String { "[]" }
    func read(_ uuid: String) throws -> String { values[uuid] ?? "{}" }
    func write(_ uuid: String, json: String) throws {
        var value = try BTTShortcutBindingService.dictionary(values[uuid] ?? "{}")
        for (key, item) in try BTTShortcutBindingService.dictionary(json) { value[key] = item }
        values[uuid] = try BTTShortcutBindingService.json(value)
        writes.append(uuid)
    }
    func create(json: String) throws -> String {
        created += 1
        if created == failCreateAt { throw BTTBindingError.message("refus simulé") }
        let fields = try BTTShortcutBindingService.dictionary(json)
        let id = fields["BTTUUID"] as? String ?? UUID().uuidString
        values[id] = json
        return id
    }
    func delete(_ uuid: String) throws { values[uuid] = nil }
}

struct Spec057BTTTests {
    @Test func payloadRunsTheRightProfileAndUsesTheRealKey() throws {
        let service = BTTShortcutBindingService()
        let profile = BTTBinding(profileID: "test'quote", name: "Test", hotkey: "command+tab", source: "btt", enabled: true)
        let json = try BTTShortcutBindingService.dictionary(service.payload(profile, backwards: false, layout: [:], enabled: false))
        #expect(json["BTTShortcutKeyCode"] as? Int == 48)
        #expect(json["BTTLayoutIndependentChar"] as? String == "\t")
        #expect(json["BTTEnabled"] as? Int == 0)
        #expect((json["BTTShellTaskActionScript"] as? String)?.contains("'test'\\''quote'") == true)
        let reverse = try BTTShortcutBindingService.dictionary(service.payload(profile, backwards: true, layout: [:], enabled: false))
        #expect(reverse["BTTShortcutModifierKeys"] as? Int == 1179648)
        #expect((reverse["BTTShellTaskActionScript"] as? String)?.contains("--hold 'command'") == true)
    }

    @Test func failedSecondTriggerCreationRollsBackTheFirst() throws {
        let api = Spec057FakeBTT()
        api.failCreateAt = 2
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        let new = BTTBinding(profileID: "p", name: "Test", hotkey: "command+tab", source: "btt", enabled: true)
        #expect(throws: BTTBindingError.self) { try service.prepare(old: old, new: new, layout: [:]) }
        #expect(api.values.isEmpty)
    }

    @Test func preparationRemainsDisabledUntilCommitAndCanRollback() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        let new = BTTBinding(profileID: "p", name: "Test", hotkey: "command+tab", source: "btt", enabled: true)
        let mutation = try service.prepare(old: old, new: new, layout: [:])
        #expect(try api.values.values.allSatisfy { try BTTShortcutBindingService.dictionary($0)["BTTEnabled"] as? Int == 0 })
        try service.activate(mutation)
        #expect(try api.values.values.allSatisfy { try BTTShortcutBindingService.dictionary($0)["BTTEnabled"] as? Int == 1 })
        try service.rollback(mutation)
        #expect(api.values.isEmpty)
    }
}


struct Spec057CompatibilityTests {
    @Test func legacyProfilesArePresentedWithTheirActualOwnerWithoutRewriting() throws {
        let descriptor = try #require(SettingsCatalog.find(id: "switcher.shortcuts"))
        let text = "[[switcher.shortcuts]]\nid = \"legacy\"\nhotkey = \"ctrl+alt+tab\"\n"
        let value = try SettingsCollectionCodec.read(descriptor, text: text)
        guard case .rows(let rows) = value else { Issue.record("Profils attendus"); return }
        #expect(rows.first?.fields["trigger_source"] == .string("roadie"))
        #expect(text.contains("trigger_source") == false)
    }

    @Test func shiftAlreadyInTheBindingDoesNotCreateADuplicateReverseTrigger() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        let new = BTTBinding(profileID: "p", name: "Test", hotkey: "command+shift+tab", source: "btt", enabled: true)
        let mutation = try service.prepare(old: old, new: new, layout: [:])
        #expect(mutation.created.count == 1)
        try service.rollback(mutation)
        #expect(api.values.isEmpty)
    }

    @Test func aLinkedTriggerChangedByTheUserIsNeverOverwritten() throws {
        let api = Spec057FakeBTT()
        api.values["foreign"] = "{\"BTTShellTaskActionScript\":\"/usr/bin/say hello\"}"
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "command+tab", source: "btt", enabled: true, forwardID: "foreign")
        var new = old
        new.source = "roadie"
        #expect(throws: BTTBindingError.self) { try service.prepare(old: old, new: new, layout: [:]) }
        #expect(api.writes.isEmpty)
        #expect(api.values["foreign"] == "{\"BTTShellTaskActionScript\":\"/usr/bin/say hello\"}")
    }

    @Test func appearanceOverridesDoNotChangeTheSharedAppearance() {
        let common = WindowSwitcherConfig(fontSize: 16, preview: true)
        let profile = WindowSwitcherShortcutConfig(styleOverride: "icons", previewOverride: false, fontSizeOverride: 24)
        let appearance = WindowSwitcherAppearance(config: common, profile: profile)
        #expect(appearance.style == .icons)
        #expect(appearance.fontSize == 24)
        #expect(!appearance.preview)
        #expect(WindowSwitcherAppearance(config: common).fontSize == 16)
    }

    @Test func changingReleasePolicyKeepsExplicitPersistentSessionsOpen() {
        var state = WindowSwitcherSessionState(stayOpen: false, fromHotkey: false, heldAtStart: true, backwards: false)
        _ = state.ready()
        state.configure(stayOpen: false)
        let accepted = state.modifiers(held: false)
        #expect(!accepted)
    }
}

