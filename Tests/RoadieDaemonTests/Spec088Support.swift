import Foundation
@testable import RoadieDaemon

/// Workflow d'essai écrit pour les tests (aucun workflow tiers copié) : objets, flèches, variables.
struct WorkflowFixture {
    var objects: [[String: Any]] = []
    var connections: [String: [[String: Any]]] = [:]
    var variables: [String: String] = [:]
    var settings: [[String: Any]] = []
    var prefs: [String: Any]?
    var name = "Essai"
    var bundleID = "test.roadie.essai"

    /// `externalID` : brique visée par un déclencheur externe (`inboundconfig`, Alfred 5.5, SPEC-092).
    mutating func add(_ uid: String, _ type: String, _ config: [String: Any] = [:], externalID: String? = nil) {
        var object: [String: Any] = ["uid": uid, "type": "alfred.workflow.\(type)", "config": config]
        if let externalID { object["inboundconfig"] = ["externalid": externalID] }
        objects.append(object)
    }

    mutating func link(_ from: String, _ to: String, modifiers: Int = 0, branch: String? = nil) {
        var link: [String: Any] = ["destinationuid": to, "modifiers": modifiers, "modifiersubtext": "", "vitoclose": false]
        if let branch { link["sourceoutputuid"] = branch }
        connections[from, default: []].append(link)
    }

    /// Écrit le dossier et lit le workflow. Le dossier est dans le répertoire temporaire.
    func write(in parent: URL? = nil, files: [String: String] = [:]) throws -> AlfredWorkflow {
        let parent = parent ?? FileManager.default.temporaryDirectory.appendingPathComponent("roadie-088-\(UUID().uuidString)")
        let folder = parent.appendingPathComponent("user.workflow.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plist: [String: Any] = ["bundleid": bundleID, "name": name, "objects": objects, "connections": connections,
                                    "variables": variables, "userconfigurationconfig": settings, "disabled": false]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: folder.appendingPathComponent("info.plist"))
        if let prefs {
            try PropertyListSerialization.data(fromPropertyList: prefs, format: .xml, options: 0).write(to: folder.appendingPathComponent("prefs.plist"))
        }
        for (name, content) in files {
            let url = folder.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        guard let workflow = AlfredWorkflow.load(folder: folder, source: .roadie) else { throw FixtureError.missing }
        return workflow
    }
}

/// Effets factices : chaque appel est noté, rien ne touche le Mac.
final class RecordedEffects: AlfredEffects, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }
    private func note(_ text: String) { lock.withLock { recorded.append(text) } }

    func openURL(_ url: String, browser: String?) async { note("url:\(url)") }
    func open(path: String, with app: String?) async { note("open:\(path)") }
    func reveal(_ paths: [String]) async { note("reveal:\(paths.joined(separator: ","))") }
    func launch(_ paths: [String]) async { note("launch:\(paths.joined(separator: ","))") }
    func copy(_ text: String, paste: Bool) async { note("copy:\(text)") }
    func notify(title: String, text: String) async { note("notify:\(title)|\(text)") }
    func playSound(_ name: String, system: Bool) async { note("sound:\(name)") }
    func speak(_ text: String) async { note("speak:\(text)") }
    func webSearch(_ text: String) async { note("web:\(text)") }
    func showBar(_ text: String) async { note("bar:\(text)") }
    func log(_ type: String, _ details: [String: String]) {}
    var dialogChoice: Int? = 1
    func keyCombo(keyCode: Int, character: String, modifiers: Int, count: Int) async { note("keys:\(keyCode):\(character):\(modifiers):\(count)") }
    func largeType(_ text: String) async { note("large:\(text)") }
    func terminal(command: String) async { note("terminal:\(command)") }
    func terminal(folder: String) async { note("terminal-folder:\(folder)") }
    func shortcut(_ name: String, input: String?) async -> String { note("shortcut:\(name):\(input ?? "-")"); return "sortie" }
    func dialog(title: String, text: String, buttons: [String]) async -> Int? { note("dialog:\(title)"); return dialogChoice }
    func systemCommand(_ id: String) async { note("system:\(id)") }
    func music(_ script: String) async { note("music:" + (script.split(separator: "\n").dropFirst().first.map(String.init) ?? "")) }
    private var recordedGrids: [AlfredGridView] = []
    var lastGrid: AlfredGridView? { lock.withLock { recordedGrids.last } }
    var grids: [AlfredGridView] { lock.withLock { recordedGrids } }
    func showGrid(_ view: AlfredGridView) async {
        lock.withLock { recordedGrids.append(view) }
        note("grid:\(view.items.count):\(view.columns)")
    }
    private var recordedTexts: [AlfredTextView] = []
    var lastText: AlfredTextView? { lock.withLock { recordedTexts.last } }
    func showText(_ view: AlfredTextView) async {
        lock.withLock { recordedTexts.append(view) }
        note("text:\(view.behaviour.rawValue)")
    }
    private var recordedMedia: [AlfredMediaView] = []
    var lastMedia: AlfredMediaView? { lock.withLock { recordedMedia.last } }
    func showMedia(_ view: AlfredMediaView) async {
        lock.withLock { recordedMedia.append(view) }
        note("media:\(view.kind.rawValue)")
    }
}

enum FixtureError: Error { case missing }
