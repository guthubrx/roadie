import AppKit
import Foundation
import RoadieCore

/// Effets réels d'un workflow, dans le démon (SPEC-088 FR-008). Le journal ne reçoit ni saisie ni
/// argument (FR-011) ; la notification passe par `osascript`, comme celles de Roadie.
final class AlfredLiveEffects: AlfredEffects, @unchecked Sendable {
    private let events: EventLog
    private let webSearchURL: String
    private let reopen: @MainActor @Sendable (String) -> Void

    init(events: EventLog, webSearchURL: String, reopen: @escaping @MainActor @Sendable (String) -> Void) {
        self.events = events
        self.webSearchURL = webSearchURL
        self.reopen = reopen
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

    func log(_ type: String, _ details: [String: String]) {
        events.append(RoadieEvent(type: "launcher.\(type)", details: details))
    }

    /// Application par identifiant de paquet ou par chemin.
    private static func application(_ value: String) -> URL? {
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }
}
