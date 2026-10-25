import CoreGraphics
import Foundation
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
