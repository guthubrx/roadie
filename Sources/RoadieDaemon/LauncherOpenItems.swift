import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

/// Document ou onglet ouvert, même dans une stage cachée (SPEC-082). Gardé en mémoire le temps de la
/// barre ; rien n'est journalisé ni écrit.
struct LauncherOpenItem: Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Sendable { case document, tab }

    let kind: Kind
    /// Fenêtre gérée qui l'affiche ; nil pour un onglet dont la fenêtre n'a pas été retrouvée.
    let windowID: WindowID?
    let bundleID: String
    let appName: String
    /// Nom du fichier ou titre de l'onglet.
    let title: String
    /// Application, dossier ou adresse, stage.
    let detail: String
    let url: String?
    /// Onglet : rang de sa fenêtre et son rang dans la fenêtre, pour AppleScript (à partir de 1).
    let browserWindow: Int?
    let tabIndex: Int?

    var id: String {
        switch kind {
        case .document: "doc:\(windowID?.rawValue ?? 0):\(title)"
        case .tab: "tab:\(bundleID):\(browserWindow ?? 0):\(tabIndex ?? 0)"
        }
    }

    /// Correspondance : le titre, puis l'adresse (qui contient la saisie). O(q × t).
    func score(_ query: String) -> Int? {
        if let score = LauncherMatch.score(query, in: title) { return score }
        let needle = LauncherMatch.fold(query)
        guard needle.count >= 3, let url, LauncherMatch.fold(url).contains(needle) else { return nil }
        return 1
    }
}

/// Onglets des navigateurs scriptables (SPEC-082 R2) : Chromium et Safari. Firefox n'en expose pas.
enum LauncherBrowsers {
    static let chromium = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi"]
    static let safari = "com.apple.Safari"
    static var all: [String] { chromium + [safari] }

    /// Une ligne par onglet : fenêtre, gauche, haut, droite, bas, onglet, actif, titre, adresse ; séparées
    /// par des tabulations. `tell application id` lancerait le navigateur : l'appelant vérifie d'abord
    /// qu'il tourne.
    static func listScript(bundleID: String) -> String? {
        let isSafari = bundleID == safari
        guard isSafari || chromium.contains(bundleID) else { return nil }
        let active = isSafari ? "index of current tab of w" : "active tab index of w"
        let title = isSafari ? "name of t" : "title of t"
        return """
        set out to ""
        tell application id "\(bundleID)"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                try
                    set b to bounds of w
                    set act to \(active)
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        set u to ""
                        try
                            set u to URL of t
                        end try
                        set out to out & wi & tab & (item 1 of b) & tab & (item 2 of b) & tab & (item 3 of b) & tab & (item 4 of b) & tab & ti & tab & (ti = act) & tab & (\(title)) & tab & u & linefeed
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    struct Tab: Equatable, Sendable {
        let window: Int
        let bounds: CGRect
        let index: Int
        let isActive: Bool
        let title: String
        let url: String
    }

    /// Lecture de la sortie ; une ligne mal formée est ignorée. Le titre peut contenir une tabulation :
    /// l'adresse est le dernier champ. O(n).
    static func parse(_ output: String) -> [Tab] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 9, let window = Int(fields[0]), let left = Double(fields[1]), let top = Double(fields[2]),
                  let right = Double(fields[3]), let bottom = Double(fields[4]), let index = Int(fields[5]) else { return nil }
            return Tab(window: window, bounds: CGRect(x: left, y: top, width: right - left, height: bottom - top), index: index,
                       isActive: fields[6] == "true", title: fields[7..<(fields.count - 1)].joined(separator: "\t"), url: fields[fields.count - 1])
        }
    }

    /// Fenêtre gérée du navigateur au même cadre (2 points de tolérance). O(w).
    static func window(matching bounds: CGRect, among windows: [(WindowID, CGRect)]) -> WindowID? {
        windows.first { _, frame in
            abs(frame.minX - bounds.minX) <= 2 && abs(frame.minY - bounds.minY) <= 2
                && abs(frame.width - bounds.width) <= 2 && abs(frame.height - bounds.height) <= 2
        }?.0
    }

    /// Sélectionne l'onglet et met sa fenêtre devant dans le navigateur ; Roadie montre ensuite sa stage.
    static func activateScript(bundleID: String, window: Int, tab: Int) -> String {
        if bundleID == safari {
            return """
            tell application id "\(bundleID)"
                set current tab of window \(window) to tab \(tab) of window \(window)
                set index of window \(window) to 1
            end tell
            """
        }
        return """
        tell application id "\(bundleID)"
            set active tab index of window \(window) to \(tab)
            set index of window \(window) to 1
        end tell
        """
    }

    /// `osascript` dans son propre processus, 2 s au plus : un navigateur bloqué ne retient pas la barre.
    /// nil si le script échoue (autorisation refusée, navigateur fermé entre-temps).
    static func run(_ script: String, timeout: TimeInterval = 2) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stop.cancel()
                continuation.resume(returning: process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil)
            }
        }
    }
}

/// Choix d'un onglet de Firefox (session 104) : Firefox n'a pas de dictionnaire AppleScript, mais ses
/// onglets sont des boutons d'accessibilité (`AXRadioButton`) titrés comme l'onglet. Un appui le choisit.
enum FirefoxTabSelector {
    /// Cherche dans la fenêtre donnée, sinon dans toutes les fenêtres de Firefox ; vrai si un onglet a été
    /// pressé. Parcours en largeur borné : 14 niveaux, 4 000 éléments par fenêtre. File lue par un indice
    /// (et non `removeFirst`, O(n) par retrait) : O(n) par fenêtre, n ≤ 4 000 (audit du 29 octobre 2026).
    static func select(title: String, in windows: [AXUIElement]) -> Bool {
        for window in windows {
            var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
            var head = 0
            while head < queue.count, head < 4_000 {
                let (element, depth) = queue[head]
                head += 1
                if string(element, kAXRoleAttribute) == kAXRadioButtonRole, string(element, kAXTitleAttribute) == title {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                }
                guard depth < 14 else { continue }
                var children: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                      let list = children as? [AXUIElement] else { continue }
                queue += list.map { ($0, depth + 1) }
            }
        }
        return false
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// Verbes d'un onglet ouvert (session 131), comme les tâches navigateur d'Alfred : fermer l'onglet, l'ouvrir dans une
/// nouvelle fenêtre. Safari et Chromium par AppleScript ; Firefox, sans dictionnaire, par l'accessibilité (onglet
/// pressé puis ⌘W) et par sa ligne de commande (`--new-window`).
enum LauncherTabActions {
    enum Action: Equatable, Sendable { case close, newWindow }

    /// Script d'un navigateur scriptable ; nil pour un autre navigateur ou sans rang connu. O(1).
    static func script(_ action: Action, bundleID: String, window: Int?, tab: Int?, url: String?) -> String? {
        let isSafari = bundleID == LauncherBrowsers.safari
        guard isSafari || LauncherBrowsers.chromium.contains(bundleID) else { return nil }
        switch action {
        case .close:
            guard let window, let tab else { return nil }
            return "tell application id \"\(bundleID)\" to close tab \(tab) of window \(window)"
        case .newWindow:
            guard let url, !url.isEmpty else { return nil }
            let address = url.applescriptEscaped
            if isSafari {
                return "tell application id \"\(bundleID)\"\nmake new document with properties {URL:\"\(address)\"}\nactivate\nend tell"
            }
            return "tell application id \"\(bundleID)\"\nset w to make new window\nset URL of active tab of w to \"\(address)\"\nactivate\nend tell"
        }
    }

    /// Arguments de `open` pour une nouvelle fenêtre de Firefox sur l'adresse. O(1).
    static func firefoxNewWindowArguments(url: String) -> [String] { ["-na", "Firefox", "--args", "--new-window", url] }

    /// Exécute le verbe ; vrai si le navigateur l'a accepté. O(1) appels.
    @MainActor static func perform(_ action: Action, on item: LauncherOpenItem) async -> Bool {
        if let script = script(action, bundleID: item.bundleID, window: item.browserWindow, tab: item.tabIndex, url: item.url) {
            return await LauncherBrowsers.run(script, timeout: 5) != nil
        }
        guard LauncherBookmarkBrowsers.bundleIDs("firefox").contains(item.bundleID),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first else { return false }
        switch action {
        case .newWindow:
            guard let url = item.url else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = firefoxNewWindowArguments(url: url)
            return (try? process.run()) != nil
        case .close:
            let pid = app.processIdentifier, windowID = item.windowID, title = item.title
            let pressed = await Task.detached(priority: .userInitiated) { () -> Bool in
                let elements = axWindowElements(pid: pid)
                let known = windowID.flatMap { elements[CGWindowID($0.rawValue)] }
                return FirefoxTabSelector.select(title: title, in: known.map { [$0] } ?? Array(elements.values))
            }.value
            guard pressed else { return false }
            app.activate()
            try? await Task.sleep(for: .milliseconds(150))
            // ⌘W (code 13) envoyé à Firefox seul, une fois son onglet choisi.
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: down)
                event?.flags = .maskCommand
                event?.postToPid(pid)
            }
            return true
        }
    }
}
