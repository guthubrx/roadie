import AppKit
import ApplicationServices
import Foundation
import RoadieCore

/// Menus de l'application active dans la barre (session 131), comme la tâche « clic dans un menu » d'Alfred :
/// `menu exporter` liste les éléments de ses menus, Retour en choisit un. Les éléments deviennent des lignes
/// « Système » (`menu:<rang>`) : la barre les affiche, les confirme et les lance comme les autres commandes.
/// Lecture par l'accessibilité, bornée et hors du fil principal ; l'application lue est celle qui était au premier
/// plan à l'ouverture de la barre.
@MainActor
final class LauncherMenuSearch {
    static let shared = LauncherMenuSearch()

    /// Élément de menu : chemin des titres (« Fichier › Exporter… »), raccourci affiché, activé.
    struct Entry: Equatable, Sendable {
        let path: [String]
        let shortcut: String
        let enabled: Bool
        var title: String { path.last ?? "" }
    }

    /// Préfixes qui ouvrent la recherche dans les menus, en français et en anglais.
    nonisolated static let keywords = ["menu", "menus"]

    /// Recherche tapée après `menu ` ; nil si la saisie n'est pas une recherche de menus. O(t).
    nonisolated static func query(_ text: String) -> String? {
        let lower = text.lowercased()
        for keyword in keywords where lower == keyword || lower.hasPrefix(keyword + " ") {
            return String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Éléments activés qui correspondent : titre d'abord, puis chemin complet ; ordre des menus à égalité. O(e × t).
    nonisolated static func matches(_ query: String, in entries: [Entry], limit: Int = 30) -> [(index: Int, entry: Entry)] {
        let scored: [(index: Int, entry: Entry, score: Int)] = entries.enumerated().compactMap { index, entry in
            guard entry.enabled, !entry.title.isEmpty else { return nil }
            if query.isEmpty { return (index, entry, 0) }
            if let score = LauncherMatch.score(query, in: entry.title) { return (index, entry, score * 2) }
            return LauncherMatch.score(query, in: entry.path.joined(separator: " ")).map { (index, entry, $0) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.prefix(limit).map { ($0.index, $0.entry) }
    }

    /// Lignes de la barre pour cette recherche. O(e × t).
    func rows(_ query: String) -> [LauncherSystemCommand] {
        Self.matches(query, in: entries).map { index, entry in
            LauncherSystemCommand(id: "menu:\(index)", title: entry.title, keywords: [], symbol: "filemenu.and.selection", confirms: false,
                                  detail: ([appName] + entry.path.dropLast()).joined(separator: " › ")
                                      + (entry.shortcut.isEmpty ? "" : "  \(entry.shortcut)"))
        }
    }

    private(set) var entries: [Entry] = []
    private var elements: [AXUIElement] = []
    private(set) var appName = ""
    private(set) var loadedPID: pid_t?
    private var loadingPID: pid_t?

    /// Lit les menus de l'application `pid` (une fois par ouverture de la barre) ; `done` est appelé à la fin. O(e).
    func load(pid: pid_t, appName: String, events: EventLog, done: @escaping @MainActor () -> Void) {
        guard loadedPID != pid, loadingPID != pid else { return }
        loadingPID = pid
        entries = []
        elements = []
        self.appName = appName
        Task {
            let started = Date()
            let read = await Task.detached(priority: .userInitiated) { ReadMenus(items: Self.read(pid: pid)) }.value.items
            guard self.loadingPID == pid else { return }
            self.entries = read.map(\.entry)
            self.elements = read.map(\.element)
            self.loadedPID = pid
            self.loadingPID = nil
            events.append(RoadieEvent(type: "launcher.menus", details: [
                "count": String(read.count), "ms": String(Int(Date().timeIntervalSince(started) * 1000))]))
            done()
        }
    }

    /// Nouvelle ouverture de la barre : les menus seront relus.
    func reset() {
        loadedPID = nil
        loadingPID = nil
        entries = []
        elements = []
    }

    var isLoading: Bool { loadingPID != nil }

    /// Choisit l'élément de ce rang : l'application repasse devant, puis l'élément est pressé. Faux s'il n'existe plus.
    @discardableResult
    func press(_ index: Int) -> Bool {
        guard elements.indices.contains(index), let pid = loadedPID else { return false }
        let element = elements[index]
        NSRunningApplication(processIdentifier: pid)?.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
        return true
    }

    /// Résultat de lecture passé du fil de fond au fil principal. `@unchecked Sendable` : les éléments AX sont des
    /// références Core Foundation immuables, utilisables depuis n'importe quel fil (pressés ensuite sur le principal).
    private struct ReadMenus: @unchecked Sendable { let items: [(entry: Entry, element: AXUIElement)] }

    /// Parcours des menus : barre de menus, puis menus et sous-menus ; menu Apple écarté. Bornes : profondeur 6,
    /// 2 000 éléments, 0,8 s, 0,25 s par appel AX. O(e).
    nonisolated static func read(pid: pid_t) -> [(entry: Entry, element: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        let deadline = Date().addingTimeInterval(0.8)
        var found: [(entry: Entry, element: AXUIElement)] = []
        var visited = 0
        func walk(_ node: AXUIElement, path: [String], depth: Int) {
            guard depth < 6, visited < 2_000, Date() < deadline else { return }
            for child in children(node) {
                visited += 1
                guard visited < 2_000, Date() < deadline else { return }
                let title = string(child, kAXTitleAttribute) ?? ""
                let role = string(child, kAXRoleAttribute) ?? ""
                if role == kAXMenuBarItemRole as String {
                    // Le menu Apple (premier, sans titre utile pour l'application) est écarté.
                    if found.isEmpty, path.isEmpty, title == "Apple" || title.isEmpty { continue }
                    walk(child, path: [title], depth: depth + 1)
                } else if role == kAXMenuRole as String {
                    walk(child, path: path, depth: depth + 1)
                } else if role == kAXMenuItemRole as String, !title.isEmpty {
                    let sub = children(child)
                    if sub.isEmpty {
                        let enabled = (value(child, kAXEnabledAttribute) as? Bool) ?? true
                        found.append((Entry(path: path + [title], shortcut: shortcut(child), enabled: enabled), child))
                    } else {
                        walk(child, path: path + [title], depth: depth + 1)
                    }
                }
            }
        }
        walk(bar, path: [], depth: 0)
        return found
    }

    nonisolated private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(owner, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// Raccourci d'un élément : touches de modification puis caractère (« ⇧⌘E »). O(1).
    nonisolated private static func shortcut(_ item: AXUIElement) -> String {
        guard let key = string(item, kAXMenuItemCmdCharAttribute), !key.isEmpty else { return "" }
        let modifiers = (value(item, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0
        return menuShortcut(key: key, modifiers: modifiers)
    }

    /// Masque AX des raccourcis : 1 Maj, 2 Option, 4 Contrôle, 8 sans Commande. O(1).
    nonisolated static func menuShortcut(key: String, modifiers: Int) -> String {
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key
    }
}
