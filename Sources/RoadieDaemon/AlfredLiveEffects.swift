import AppKit
import Foundation
import RoadieCore

/// Effets réels d'un workflow, dans le démon (SPEC-088 FR-008). Le journal ne reçoit ni saisie ni
/// argument (FR-011) ; la notification passe par `osascript`, comme celles de Roadie.
final class AlfredLiveEffects: AlfredEffects, @unchecked Sendable {
    private let events: EventLog
    private let webSearchURL: String
    private let reopen: @MainActor @Sendable (String) -> Void
    private let presentGrid: @MainActor @Sendable (AlfredGridView) -> Void

    init(events: EventLog, webSearchURL: String, reopen: @escaping @MainActor @Sendable (String) -> Void,
         presentGrid: @escaping @MainActor @Sendable (AlfredGridView) -> Void = { _ in }) {
        self.events = events
        self.webSearchURL = webSearchURL
        self.reopen = reopen
        self.presentGrid = presentGrid
    }

    func openURL(_ url: String, browser: String?) async {
        guard let target = URL(string: url) ?? url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:)) else { return }
        await MainActor.run {
            if let browser, let app = Self.application(browser) {
                NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }

    func open(path: String, with app: String?) async {
        let target = path.hasPrefix("/") ? URL(fileURLWithPath: path) : (URL(string: path) ?? URL(fileURLWithPath: path))
        await MainActor.run {
            if let app, let application = Self.application(app) {
                NSWorkspace.shared.open([target], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }

    func reveal(_ paths: [String]) async {
        let urls = paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func launch(_ paths: [String]) async {
        await MainActor.run { for path in paths where !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
    }

    /// Copie ; `paste` : ⌘V simulé dans l'application au premier plan, une fois la barre fermée.
    func copy(_ text: String, paste: Bool) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        guard paste else { return }
        try? await Task.sleep(for: .milliseconds(150))
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    func notify(title: String, text: String) async {
        let script = "display notification \"\(text.applescriptEscaped)\" with title \"\(title.applescriptEscaped)\""
        _ = await LauncherBrowsers.run(script, timeout: 3)
    }

    func playSound(_ name: String, system: Bool) async {
        await MainActor.run {
            let sound = system ? NSSound(named: NSSound.Name(name)) : NSSound(contentsOfFile: name, byReference: true)
            sound?.play()
        }
    }

    func speak(_ text: String) async {
        guard !text.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func webSearch(_ text: String) async {
        guard let url = LauncherWeb.searchURL(webSearchURL, query: text) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    func showBar(_ text: String) async {
        let reopen = reopen
        await MainActor.run { reopen(text) }
    }

    /// Grille (SPEC-092) : la barre se rouvre en tuiles.
    func showGrid(_ view: AlfredGridView) async {
        let presentGrid = presentGrid
        await MainActor.run { presentGrid(view) }
    }

    func log(_ type: String, _ details: [String: String]) {
        events.append(RoadieEvent(type: "launcher.\(type)", details: details))
    }

    // MARK: - Étape 2 (SPEC-089)

    /// Codes de touche ANSI des lettres et chiffres, pour une combinaison donnée par son caractère.
    private static let keyCodes: [Character: CGKeyCode] = {
        let letters: [(Character, CGKeyCode)] = [("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8),
            ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20),
            ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29), ("o", 31), ("u", 32), ("i", 34), ("p", 35),
            ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46), (" ", 49)]
        return Dictionary(uniqueKeysWithValues: letters)
    }()

    func keyCombo(keyCode: Int, character: String, modifiers: Int, count: Int) async {
        let code = keyCode >= 0 ? CGKeyCode(keyCode) : character.lowercased().first.flatMap { Self.keyCodes[$0] }
        guard let code else { return }
        var flags: CGEventFlags = []
        if modifiers & 1_048_576 != 0 { flags.insert(.maskCommand) }
        if modifiers & 524_288 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 262_144 != 0 { flags.insert(.maskControl) }
        if modifiers & 131_072 != 0 { flags.insert(.maskShift) }
        if modifiers & 8_388_608 != 0 { flags.insert(.maskSecondaryFn) }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func largeType(_ text: String) async {
        await MainActor.run { LargeTypePanel.show(text) }
    }

    func terminal(command: String) async {
        _ = await LauncherBrowsers.run("tell application \"Terminal\"\nactivate\ndo script \"\(command.applescriptEscaped)\"\nend tell", timeout: 5)
    }

    func terminal(folder: String) async {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        await MainActor.run {
            NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// `shortcuts run` avec fichiers d'entrée et de sortie temporaires ; 30 s au plus.
    func shortcut(_ name: String, input: String?) async -> String {
        guard !name.isEmpty else { return "" }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var arguments = ["run", name, "-o", folder.appendingPathComponent("out").path]
        if let input {
            let file = folder.appendingPathComponent("in.txt")
            try? input.write(to: file, atomically: true, encoding: .utf8)
            arguments += ["-i", file.path]
        }
        let workflow = AlfredWorkflow(id: "shortcut", bundleID: "", name: name, description: "", version: "", folder: folder, source: .roadie,
                                      disabled: false, objects: [:], connections: [:], variables: [:], userSettings: [], prefs: [:])
        let script = AlfredScript(language: 0, source: #"exec /usr/bin/shortcuts "$@""#)
        _ = await AlfredScriptRunner.run(script, query: "", arguments: arguments, workflow: workflow, variables: [:], timeout: 30)
        return (try? String(contentsOf: folder.appendingPathComponent("out"), encoding: .utf8)) ?? ""
    }

    /// `display dialog` : le bouton 1 d'Alfred est le bouton par défaut, à droite.
    func dialog(title: String, text: String, buttons: [String]) async -> Int? {
        let shown = buttons.enumerated().filter { !$0.element.isEmpty }.reversed()
        guard !shown.isEmpty else { return nil }
        let list = shown.map { "\"\($0.element.applescriptEscaped)\"" }.joined(separator: ", ")
        let script = "button returned of (display dialog \"\(text.applescriptEscaped)\" with title \"\(title.applescriptEscaped)\" buttons {\(list)} default button \"\(buttons[0].applescriptEscaped)\")"
        guard let answer = await LauncherBrowsers.run(script, timeout: 600)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return buttons.firstIndex(of: answer).map { $0 + 1 }
    }

    /// Application par identifiant de paquet ou par chemin.
    private static func application(_ value: String) -> URL? {
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }
}

/// Grand texte (Large Type d'Alfred) : panneau plein écran, fermé au clic, à une touche ou après 30 s.
@MainActor
final class LargeTypePanel {
    private static var panel: NSPanel?
    private static var monitors: [Any] = []

    static func show(_ text: String) {
        close()
        guard let screen = NSScreen.main ?? NSScreen.screens.first, !text.isEmpty else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: min(180, max(36, screen.frame.width / CGFloat(max(8, min(40, text.count))))), weight: .bold)
        label.frame = screen.frame.insetBy(dx: 80, dy: 80).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        label.maximumNumberOfLines = 0
        panel.contentView?.addSubview(label)
        panel.orderFrontRegardless()
        self.panel = panel
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { _ in Task { @MainActor in close() } },
                    NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in Task { @MainActor in close() }; return event }]
            .compactMap { $0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { MainActor.assumeIsolated { if self.panel === panel { close() } } }
    }

    static func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
    }
}
