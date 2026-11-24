import AppKit
import Carbon
import Foundation
import RoadieCore

/// Résultat pur d'expansion d'un snippet local (Spec 163).
public struct ExpandedSnippet: Equatable, Sendable {
    public let text: String
    /// Nombre de caractères à reculer depuis la fin pour placer le curseur à l'emplacement `{cursor}`, ou `nil`.
    public let cursorOffsetFromEnd: Int?

    public init(text: String, cursorOffsetFromEnd: Int? = nil) {
        self.text = text
        self.cursorOffsetFromEnd = cursorOffsetFromEnd
    }
}

/// Expansion dynamique en une passe et recherche locale des snippets (`[snippets]`, Spec 163).
public enum SnippetsService {
    private static let tokens = ["{datetime}", "{date}", "{time}", "{clipboard}", "{cursor}"]

    /// Étend les variables `{date}`, `{time}`, `{datetime}`, `{clipboard}` et `{cursor}` en une seule
    /// passe linéaire : le contenu issu de `{clipboard}` n'est jamais ré-interprété. O(n).
    public static func expand(
        _ body: String,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        clipboardText: String? = nil
    ) -> ExpandedSnippet {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone

        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "HH:mm"
        let timeString = dateFormatter.string(from: now)

        let dateTimeString = "\(dateString) \(timeString)"
        let clip = clipboardText ?? ""

        var output = ""
        output.reserveCapacity(body.count + clip.count)
        var cursorPositionInOutput: Int?
        var idx = body.startIndex

        while idx < body.endIndex {
            if body[idx] == "{" {
                if let matched = matchToken(in: body, at: idx) {
                    switch matched {
                    case "{date}":
                        output.append(dateString)
                    case "{time}":
                        output.append(timeString)
                    case "{datetime}":
                        output.append(dateTimeString)
                    case "{clipboard}":
                        output.append(clip)
                    case "{cursor}":
                        if cursorPositionInOutput == nil {
                            cursorPositionInOutput = output.count
                        }
                    default:
                        output.append(matched)
                    }
                    idx = body.index(idx, offsetBy: matched.count)
                    continue
                }
            }
            output.append(body[idx])
            idx = body.index(after: idx)
        }

        let offsetFromEnd = cursorPositionInOutput.map { max(0, output.count - $0) }
        return ExpandedSnippet(text: output, cursorOffsetFromEnd: offsetFromEnd)
    }

    private static func matchToken(in text: String, at index: String.Index) -> String? {
        for token in tokens where text[index...].hasPrefix(token) {
            return token
        }
        return nil
    }

    public static func find(keyword: String, in items: [SnippetItem]) -> SnippetItem? {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return items.first { $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle }
    }

    public static func search(_ query: String, in items: [SnippetItem], limit: Int = 20) -> [SnippetItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(items.prefix(max(1, limit))) }
        let needle = LauncherMatch.fold(trimmed)
        let scored: [(SnippetItem, Int)] = items.compactMap { item in
            let kw = LauncherMatch.fold(item.keyword)
            let title = LauncherMatch.fold(item.title)
            let body = LauncherMatch.fold(item.body)
            if kw == needle { return (item, 100) }
            if kw.hasPrefix(needle) { return (item, 80) }
            if title.hasPrefix(needle) { return (item, 60) }
            if kw.contains(needle) || title.contains(needle) { return (item, 40) }
            if body.contains(needle) { return (item, 20) }
            return nil
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.keyword.count < $1.0.keyword.count }
            .prefix(max(1, limit))
            .map(\.0)
    }
}

/// Tampon circulaire pur de saisie clavier pour l'auto-expansion optionnelle (`snippets.auto_expand`).
public struct SnippetTypingBuffer: Equatable, Sendable {
    public private(set) var text: String = ""
    private let capacity: Int

    public init(capacity: Int = 48) {
        self.capacity = max(8, capacity)
    }

    public mutating func reset() {
        text.removeAll(keepingCapacity: true)
    }

    public mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }

    /// Ajoute un caractère et renvoie le snippet dont le mot-clé vient de se terminer sur un délimiteur (espace).
    public mutating func append(_ character: Character, items: [SnippetItem]) -> SnippetItem? {
        if character == " " {
            let matched = matchSuffix(in: items)
            reset()
            return matched
        }
        if character.isNewline || character == "\t" {
            reset()
            return nil
        }
        text.append(character)
        if text.count > capacity {
            text.removeFirst(text.count - capacity)
        }
        return nil
    }

    private func matchSuffix(in items: [SnippetItem]) -> SnippetItem? {
        guard !text.isEmpty else { return nil }
        for item in items {
            let kw = item.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard kw.count >= 2, text.hasSuffix(kw) else { continue }
            // Exige un début de tampon ou un séparateur non alphanumérique avant le mot-clé.
            let prefixLen = text.count - kw.count
            if prefixLen == 0 { return item }
            let boundaryIndex = text.index(text.startIndex, offsetBy: prefixLen - 1)
            let before = text[boundaryIndex]
            if !before.isLetter && !before.isNumber {
                return item
            }
        }
        return nil
    }
}

/// Auto-expandeur clavier optionnel, STRICTEMENT inactif tant que `snippets.enabled && snippets.auto_expand`
/// n'est pas activé (0 moniteur installé par défaut). Ignore toujours la saisie sécurisée macOS.
@MainActor
public final class SnippetAutoExpander {
    public static let shared = SnippetAutoExpander()

    private let configLoader: () -> RoadieConfig
    private var configObservers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var buffer = SnippetTypingBuffer()
    private var started = false
    private var isExpanding = false
    var hasActiveKeyMonitor: Bool { keyMonitor != nil }

    public init(configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }) {
        self.configLoader = configLoader
    }

    public func start() {
        guard !started else { return }
        started = true
        for name: Notification.Name in [.roadieConfigDidReload, .roadieSettingsDidChange] {
            configObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncMonitorForCurrentConfig() }
            })
        }
        syncMonitorForCurrentConfig()
    }

    public func stop() {
        started = false
        configObservers.forEach { NotificationCenter.default.removeObserver($0) }
        configObservers.removeAll()
        uninstallKeyMonitor()
    }

    func syncMonitorForCurrentConfig() {
        guard started else { return }
        let snippets = configLoader().snippets
        guard snippets.enabled, snippets.autoExpand, !snippets.items.isEmpty else {
            uninstallKeyMonitor()
            return
        }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyEvent(event) }
        }
    }

    private func uninstallKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        buffer.reset()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard !isExpanding else { return }
        // Sécurité absolue : ne jamais observer ni étendre dans un champ mot de passe / saisie sécurisée.
        guard !IsSecureEventInputEnabled() else {
            buffer.reset()
            return
        }
        let config = configLoader()
        guard config.snippets.enabled, config.snippets.autoExpand else {
            uninstallKeyMonitor()
            return
        }
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased(),
           config.clipboard.excludedBundles.contains(where: { $0.lowercased() == bundle }) {
            buffer.reset()
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if !mods.isEmpty {
            buffer.reset()
            return
        }
        if event.keyCode == 51 { // Backspace
            buffer.backspace()
            return
        }
        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            buffer.reset()
            return
        }
        if let matched = buffer.append(ch, items: config.snippets.items) {
            performExpansion(for: matched)
        }
    }

    private func performExpansion(for item: SnippetItem) {
        isExpanding = true
        defer { isExpanding = false }

        let pasteboard = NSPasteboard.general
        let rawTypes = Set(pasteboard.types?.map(\.rawValue) ?? [])
        let pasteboardIsSensitive = ClipboardSecurityFilter.hasForbiddenPasteboardType(rawTypes)
        let previousText = pasteboardIsSensitive ? nil : pasteboard.string(forType: .string)
        let expanded = SnippetsService.expand(item.body, clipboardText: previousText)
        // Supprimer le mot-clé tapé + l'espace déclencheur.
        let deleteCount = item.keyword.trimmingCharacters(in: .whitespacesAndNewlines).count + 1
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<deleteCount {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
        // Copier avec marqueur TransientType pour ne pas polluer l'historique presse-papiers.
        ClipboardMonitor.copyToPasteboard(expanded.text, transient: true)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        if let offset = expanded.cursorOffsetFromEnd, offset > 0 {
            for _ in 0..<offset {
                if let down = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: false) {
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                }
            }
        }
        // Restaurer le presse-papiers antérieur après un court délai (avec marqueur transitoire).
        if let previousText {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                ClipboardMonitor.copyToPasteboard(previousText, transient: true)
            }
        }
    }
}
