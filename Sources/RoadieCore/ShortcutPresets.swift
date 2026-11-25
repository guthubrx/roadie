import Foundation

/// Identifiants des jeux de raccourcis clavier autonomes fournis avec Roadie (Spec 166).
/// Tous les raccourcis sont enregistrés directement par `RoadieCommandHotkeys` (Carbon)
/// sans nécessiter BetterTouchTool ni Karabiner, et utilisent uniquement des touches
/// universelles compatibles AZERTY et QWERTY.
public enum ShortcutPresetID: String, CaseIterable, Codable, Sendable {
    case standard
    case vim
    case minimal

    public var titleFR: String {
        switch self {
        case .standard: "Standard (flèches)"
        case .vim: "Vim / AeroSpace (HJKL)"
        case .minimal: "Minimal (essentiels)"
        }
    }

    public var titleEN: String {
        switch self {
        case .standard: "Standard (arrows)"
        case .vim: "Vim / AeroSpace (HJKL)"
        case .minimal: "Minimal (essentials)"
        }
    }

    public var summaryFR: String {
        switch self {
        case .standard: "Navigation ⌥+flèches, déplacement ⌥⇧+flèches, stages ⌥1–5, onglets BSP, scratchpad et vue d'ensemble."
        case .vim: "Navigation ⌥+HJKL, déplacement ⌥⇧+HJKL, stages ⌥1–5, onglets BSP, scratchpad et vue d'ensemble."
        case .minimal: "10 raccourcis essentiels : focus ⌥+flèches, stages ⌥1–4, maximiser et vue d'ensemble."
        }
    }

    public var summaryEN: String {
        switch self {
        case .standard: "Navigation ⌥+arrows, move ⌥⇧+arrows, stages ⌥1–5, BSP tabs, scratchpad, and overview."
        case .vim: "Navigation ⌥+HJKL, move ⌥⇧+HJKL, stages ⌥1–5, BSP tabs, scratchpad, and overview."
        case .minimal: "10 essential shortcuts: ⌥+arrow focus, stages ⌥1–4, maximize, and overview."
        }
    }
}

public struct ShortcutPreset: Equatable, Codable, Sendable {
    public var id: ShortcutPresetID
    public var titleFR: String
    public var titleEN: String
    public var summaryFR: String
    public var summaryEN: String
    public var shortcuts: [CommandShortcut]

    public init(id: ShortcutPresetID, shortcuts: [CommandShortcut]) {
        self.id = id
        self.titleFR = id.titleFR
        self.titleEN = id.titleEN
        self.summaryFR = id.summaryFR
        self.summaryEN = id.summaryEN
        self.shortcuts = shortcuts
    }
}

public struct ShortcutMergeReport: Equatable, Codable, Sendable {
    public var preset: ShortcutPresetID
    public var added: [CommandShortcut]
    public var skippedExistingCommands: [String]
    public var skippedKeyCollisions: [String]
    public var resultingShortcuts: [CommandShortcut]

    public init(
        preset: ShortcutPresetID,
        added: [CommandShortcut],
        skippedExistingCommands: [String],
        skippedKeyCollisions: [String],
        resultingShortcuts: [CommandShortcut]
    ) {
        self.preset = preset
        self.added = added
        self.skippedExistingCommands = skippedExistingCommands
        self.skippedKeyCollisions = skippedKeyCollisions
        self.resultingShortcuts = resultingShortcuts
    }
}

public enum ShortcutPresets {
    public static let all: [ShortcutPreset] = ShortcutPresetID.allCases.map(preset(for:))

    public static func preset(for id: ShortcutPresetID) -> ShortcutPreset {
        switch id {
        case .standard:
            return ShortcutPreset(id: .standard, shortcuts: [
                CommandShortcut(keys: "alt+left", command: "focus left"),
                CommandShortcut(keys: "alt+right", command: "focus right"),
                CommandShortcut(keys: "alt+up", command: "focus up"),
                CommandShortcut(keys: "alt+down", command: "focus down"),
                CommandShortcut(keys: "alt+shift+left", command: "move left"),
                CommandShortcut(keys: "alt+shift+right", command: "move right"),
                CommandShortcut(keys: "alt+shift+up", command: "move up"),
                CommandShortcut(keys: "alt+shift+down", command: "move down"),
                CommandShortcut(keys: "alt+control+left", command: "tab prev"),
                CommandShortcut(keys: "alt+control+right", command: "tab next"),
                CommandShortcut(keys: "alt+t", command: "tab stack right"),
                CommandShortcut(keys: "alt+shift+t", command: "tab unstack"),
                CommandShortcut(keys: "alt+m", command: "toggle maximize"),
                CommandShortcut(keys: "alt+f", command: "toggle floating"),
                CommandShortcut(keys: "alt+b", command: "balance"),
                CommandShortcut(keys: "alt+s", command: "scratchpad toggle"),
                CommandShortcut(keys: "alt+o", command: "overview toggle"),
                CommandShortcut(keys: "alt+1", command: "stage switch-position 1"),
                CommandShortcut(keys: "alt+2", command: "stage switch-position 2"),
                CommandShortcut(keys: "alt+3", command: "stage switch-position 3"),
                CommandShortcut(keys: "alt+4", command: "stage switch-position 4"),
                CommandShortcut(keys: "alt+5", command: "stage switch-position 5"),
                CommandShortcut(keys: "alt+shift+1", command: "stage assign-position 1"),
                CommandShortcut(keys: "alt+shift+2", command: "stage assign-position 2"),
                CommandShortcut(keys: "alt+shift+3", command: "stage assign-position 3"),
                CommandShortcut(keys: "alt+shift+4", command: "stage assign-position 4"),
                CommandShortcut(keys: "alt+shift+5", command: "stage assign-position 5"),
            ])
        case .vim:
            return ShortcutPreset(id: .vim, shortcuts: [
                CommandShortcut(keys: "alt+h", command: "focus left"),
                CommandShortcut(keys: "alt+l", command: "focus right"),
                CommandShortcut(keys: "alt+k", command: "focus up"),
                CommandShortcut(keys: "alt+j", command: "focus down"),
                CommandShortcut(keys: "alt+shift+h", command: "move left"),
                CommandShortcut(keys: "alt+shift+l", command: "move right"),
                CommandShortcut(keys: "alt+shift+k", command: "move up"),
                CommandShortcut(keys: "alt+shift+j", command: "move down"),
                CommandShortcut(keys: "alt+control+h", command: "tab prev"),
                CommandShortcut(keys: "alt+control+l", command: "tab next"),
                CommandShortcut(keys: "alt+t", command: "tab stack right"),
                CommandShortcut(keys: "alt+shift+t", command: "tab unstack"),
                CommandShortcut(keys: "alt+m", command: "toggle maximize"),
                CommandShortcut(keys: "alt+f", command: "toggle floating"),
                CommandShortcut(keys: "alt+b", command: "balance"),
                CommandShortcut(keys: "alt+s", command: "scratchpad toggle"),
                CommandShortcut(keys: "alt+o", command: "overview toggle"),
                CommandShortcut(keys: "alt+1", command: "stage switch-position 1"),
                CommandShortcut(keys: "alt+2", command: "stage switch-position 2"),
                CommandShortcut(keys: "alt+3", command: "stage switch-position 3"),
                CommandShortcut(keys: "alt+4", command: "stage switch-position 4"),
                CommandShortcut(keys: "alt+5", command: "stage switch-position 5"),
                CommandShortcut(keys: "alt+shift+1", command: "stage assign-position 1"),
                CommandShortcut(keys: "alt+shift+2", command: "stage assign-position 2"),
                CommandShortcut(keys: "alt+shift+3", command: "stage assign-position 3"),
                CommandShortcut(keys: "alt+shift+4", command: "stage assign-position 4"),
                CommandShortcut(keys: "alt+shift+5", command: "stage assign-position 5"),
            ])
        case .minimal:
            return ShortcutPreset(id: .minimal, shortcuts: [
                CommandShortcut(keys: "alt+left", command: "focus left"),
                CommandShortcut(keys: "alt+right", command: "focus right"),
                CommandShortcut(keys: "alt+up", command: "focus up"),
                CommandShortcut(keys: "alt+down", command: "focus down"),
                CommandShortcut(keys: "alt+m", command: "toggle maximize"),
                CommandShortcut(keys: "alt+o", command: "overview toggle"),
                CommandShortcut(keys: "alt+1", command: "stage switch-position 1"),
                CommandShortcut(keys: "alt+2", command: "stage switch-position 2"),
                CommandShortcut(keys: "alt+3", command: "stage switch-position 3"),
                CommandShortcut(keys: "alt+4", command: "stage switch-position 4"),
            ])
        }
    }

    /// Fusionne un préréglage dans `existing` sans écraser les raccourcis utilisateur par défaut.
    /// Si `replaceExisting` est vrai, remplace les raccourcis gérés par Roadie (en conservant les
    /// entrées explicitement liées à BetterTouchTool via `bttUUID`). O(n + p).
    public static func merge(
        _ id: ShortcutPresetID,
        into existing: [CommandShortcut],
        replaceExisting: Bool = false
    ) -> ShortcutMergeReport {
        let base: [CommandShortcut] = replaceExisting
            ? existing.filter { !$0.bttUUID.isEmpty }
            : existing

        var usedCommands = Set(base.map { normalizedCommand($0.command) })
        var usedKeys = Set(base.filter(\.enabled).map(\.keys).filter { !$0.isEmpty })
        var result = base
        var added: [CommandShortcut] = []
        var skippedCommands: [String] = []
        var skippedKeys: [String] = []

        for candidate in preset(for: id).shortcuts {
            let cmd = normalizedCommand(candidate.command)
            if usedCommands.contains(cmd) {
                skippedCommands.append(candidate.command)
                continue
            }
            if usedKeys.contains(candidate.keys) {
                skippedKeys.append("\(candidate.keys) -> \(candidate.command)")
                continue
            }
            result.append(candidate)
            added.append(candidate)
            usedCommands.insert(cmd)
            usedKeys.insert(candidate.keys)
        }

        return ShortcutMergeReport(
            preset: id,
            added: added,
            skippedExistingCommands: skippedCommands,
            skippedKeyCollisions: skippedKeys,
            resultingShortcuts: result
        )
    }

    /// Génère un fichier `config.toml` initial propre prêt à l'emploi pour une première installation.
    public static func renderDefaultConfigTOML(preset: ShortcutPresetID? = .standard) -> String {
        var lines: [String] = [
            "# Configuration Roadie générée automatiquement (Spec 166)",
            "# Documentation : https://github.com/guthubrx/roadie/blob/main/docs/fr/configuration-rules.md",
            "",
            "[tiling]",
            "default_strategy = \"spatialBsp\"",
            "scrolling_smooth_scroll = true",
            "scrolling_trackpad_gestures = true",
            "scrolling_trackpad_fingers = 3",
            "",
        ]
        if let preset {
            lines.append("# Raccourcis globaux autonomes (préréglage : \(preset.rawValue), sans BetterTouchTool)")
            for shortcut in Self.preset(for: preset).shortcuts {
                lines.append("[[shortcuts]]")
                lines.append("keys = \(tomlString(shortcut.keys))")
                lines.append("command = \(tomlString(shortcut.command))")
                lines.append("enabled = true")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func tomlFragment(for shortcut: CommandShortcut) -> String {
        var lines = [
            "[[shortcuts]]",
            "keys = \(tomlString(shortcut.keys))",
            "command = \(tomlString(shortcut.command))",
            "enabled = \(shortcut.enabled ? "true" : "false")",
        ]
        if !shortcut.bttUUID.isEmpty {
            lines.append("btt_uuid = \(tomlString(shortcut.bttUUID))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func normalizedCommand(_ command: String) -> String {
        command
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    private static func tomlString(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
