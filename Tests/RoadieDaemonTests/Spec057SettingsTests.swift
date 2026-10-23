import AppKit
import Foundation
import RoadieCore
import RoadieAX
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
    var listed = "[]"
    var listFails = false
    var omitEnabledDefaults = false

    func list() throws -> String {
        if listFails { throw BTTBindingError.message("Lecture indisponible") }
        return listed
    }
    func read(_ uuid: String) throws -> String {
        guard omitEnabledDefaults else { return values[uuid] ?? "{}" }
        var value = try BTTShortcutBindingService.dictionary(values[uuid] ?? "{}")
        for key in ["BTTEnabled", "BTTEnabled2"] where value[key] as? Int == 1 { value[key] = nil }
        return try BTTShortcutBindingService.json(value)
    }
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
    @Test func anEmptyBTTCombinationCreatesNoBinding() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        var new = old; new.source = "btt"
        let mutation = try service.prepare(old: old, new: new, layout: [:])
        try service.activate(mutation)
        #expect(mutation.created.isEmpty && api.values.isEmpty)
    }

    @Test func unreadableOrAmbiguousLegacyBindingsStopTheTransfer() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "all", name: "Test", hotkey: "", source: "external", enabled: true)
        var new = old; new.source = "roadie"; new.hotkey = "command+tab"
        api.listFails = true
        #expect(throws: BTTBindingError.self) { try service.prepare(old: old, new: new, layout: [:]) }
        api.listFails = false
        let script = service.executable + " switcher cycle --hold cmd"
        api.listed = String(decoding: try JSONSerialization.data(withJSONObject: [
            ["BTTUUID": "a", "BTTShellTaskActionScript": script],
            ["BTTUUID": "b", "BTTShellTaskActionScript": script]
        ]), as: UTF8.self)
        #expect(throws: BTTBindingError.self) { try service.prepare(old: old, new: new, layout: [:]) }
        #expect(api.writes.isEmpty)
    }

    @Test func activationAcceptsBTTOmittedDefaultsButRejectsAnUnknownTrigger() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        var new = old; new.source = "btt"; new.hotkey = "command+tab"
        let mutation = try service.prepare(old: old, new: new, layout: [:])
        api.omitEnabledDefaults = true
        try service.activate(mutation)
        api.values[mutation.binding.forwardID] = "{}"
        #expect(throws: BTTBindingError.self) { try service.activate(mutation) }
    }

    @Test func deletingAProfileRemovesOnlyItsDisabledBindings() throws {
        let api = Spec057FakeBTT()
        let service = BTTShortcutBindingService(api: api)
        let old = BTTBinding(profileID: "p", name: "Test", hotkey: "", source: "external", enabled: true)
        var new = old; new.source = "btt"; new.hotkey = "command+tab"
        let created = try service.prepare(old: old, new: new, layout: [:])
        try service.activate(created)
        var disabled = created.binding; disabled.source = "external"; disabled.enabled = false
        let removed = try service.prepare(old: created.binding, new: disabled, layout: [:])
        api.values["foreign"] = "{\"BTTShellTaskActionScript\":\"/usr/bin/true\"}"
        try service.discard(removed)
        #expect(Set(api.values.keys) == ["foreign"])
    }

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

@MainActor
struct Spec057EditorRecoveryTests {
    @Test func rejectedChangesDoNotLeavePhantomRowsOrDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roadies.toml")
        let original = "[[switcher.shortcuts]]\nid = \"p\"\nname = \"Initial\"\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path), afterWrite: {})
        let descriptor = try #require(SettingsCatalog.find(id: "switcher.shortcuts"))
        let editor = SettingsCollectionEditorModel(descriptor: descriptor, service: service)
        let id = try #require(editor.rows.first?.id)
        let updated = editor.updateRow(id, values: ["scope": "invalid"])
        #expect(!updated)
        try original.replacingOccurrences(of: "Initial", with: "Externe").write(to: file, atomically: true, encoding: .utf8)
        let removed = editor.removeRow(id)
        #expect(!removed && editor.rows.count == 1)
        editor.reload()
        #expect(editor.rows.first?.raw["name"] == "Externe")
        #expect(editor.messages.isEmpty)
    }
}

@MainActor
struct Spec057PanelInteractionTests {
    @Test func arrowAndMouseEventsSelectWithoutActivatingUntilClick() throws {
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "icons", preview: false)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(), navigationModifiers: [.command])
        let entries = (1...20).map { i in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(i)), pid: 1,
                appName: "Test", bundleID: "fixture.test", title: "Document \(i)", frame: Rect(x: 0, y: 0, width: 600, height: 400),
                isOnScreen: true, isTileCandidate: true), scope: nil)
        }
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let views = descendants(try #require(panel.contentView))
        let cards = views.compactMap { $0 as? WindowSwitcherCardView }
        let nextRow = try #require(cards.first(where: { $0.frame.minY > cards[0].frame.minY }))
        var selected = entries[0].id
        var activated: WindowID?
        panel.onHighlight = { selected = $0; panel.select($0, previewImage: nil) }
        panel.onSelect = { activated = $0 }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            panel.sendEvent(event)
        }
        try key(124, flags: .command)
        #expect(selected == entries[1].id)
        try key(123, flags: .command)
        #expect(selected == entries[0].id)
        try key(125, flags: .command)
        #expect(selected == nextRow.entryID)
        try key(126, flags: .command)
        #expect(selected == entries[0].id)
        let point = cards[1].convert(CGPoint(x: cards[1].bounds.midX, y: cards[1].bounds.midY), to: nil)
        panel.hover(at: point)
        #expect(selected == entries[1].id)
        try key(124)
        #expect(selected == entries[2].id)
        panel.hover(at: point)
        #expect(selected == entries[2].id)
        #expect(activated == nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        cards[1].mouseDown(with: click)
        #expect(activated == entries[1].id)
        panel.configure(profile: WindowSwitcherShortcutConfig(arrowNavigation: false, mouseHover: false))
        try key(123)
        panel.hover(at: CGPoint(x: point.x + 1, y: point.y))
        #expect(selected == entries[2].id)
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

