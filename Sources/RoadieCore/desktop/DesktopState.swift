import Foundation
import TOMLKit

/// État complet d'un desktop macOS, persisté dans `~/.config/roadies/desktops/<uuid>.toml`.
/// Le `TreeNode` n'est PAS sérialisé : il est reconstruit en mémoire au switch in à
/// partir des `memberWindows` dans `stages` (cohérent avec le pattern V1 SPEC-002).
public struct DesktopState: Codable, Sendable {
    public var desktopUUID: String
    public var displayName: String?
    public var tilerStrategy: TilerStrategy
    public var currentStageID: StageID?
    public var version: Int
    public var gapsOverride: GapsOverride?
    /// Stages persistés sur ce desktop (au moins 1 par convention, peut être vide au boot).
    /// Les éléments sont du type `Stage` du target RoadieStagePlugin via la clé `members`,
    /// mais on ne dépend pas de ce target dans RoadieCore. On stocke un type miroir.
    public var stages: [PersistedStage]

    public init(desktopUUID: String,
                displayName: String? = nil,
                tilerStrategy: TilerStrategy = .bsp,
                currentStageID: StageID? = nil,
                version: Int = 1,
                gapsOverride: GapsOverride? = nil,
                stages: [PersistedStage] = []) {
        self.desktopUUID = desktopUUID
        self.displayName = displayName
        self.tilerStrategy = tilerStrategy
        self.currentStageID = currentStageID
        self.version = version
        self.gapsOverride = gapsOverride
        self.stages = stages
    }

    enum CodingKeys: String, CodingKey {
        case desktopUUID = "desktop_uuid"
        case displayName = "display_name"
        case tilerStrategy = "tiler_strategy"
        case currentStageID = "current_stage_id"
        case version
        case gapsOverride = "gaps_override"
        case stages
    }

    // MARK: - Lifecycle

    /// État vierge utilisé au premier accès à un desktop jamais visité (FR-006).
    public static func empty(uuid: String,
                             defaultStage: StageID? = nil,
                             tilerStrategy: TilerStrategy = .bsp) -> DesktopState {
        var stages: [PersistedStage] = []
        if let id = defaultStage {
            stages = [PersistedStage(id: id.value, displayName: "main")]
        }
        return DesktopState(desktopUUID: uuid,
                            tilerStrategy: tilerStrategy,
                            currentStageID: defaultStage,
                            stages: stages)
    }

    // MARK: - Persistance

    /// Dossier des states V2 (créé à la demande).
    public static let stateDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/roadies/desktops", isDirectory: true)
    }()

    /// Chemin du fichier d'état pour un UUID donné.
    public static func path(for uuid: String) -> URL {
        stateDir.appendingPathComponent("\(uuid).toml", isDirectory: false)
    }

    /// Écriture atomique : écrit dans `<path>.tmp` puis `rename`. Crée le dossier parent si absent.
    public func write(to url: URL? = nil) throws {
        let target = url ?? Self.path(for: desktopUUID)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let toml = try TOMLEncoder().encode(self)
        let tmp = target.appendingPathExtension("tmp")
        try toml.write(to: tmp, atomically: true, encoding: .utf8)
        // FileManager.replaceItem ne fonctionne pas si la cible n'existe pas → rename direct.
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: tmp, to: target)
    }

    /// Lecture + validation. Throw si le TOML est invalide ou si l'état est incohérent.
    public static func read(from url: URL) throws -> DesktopState {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let state = try TOMLDecoder().decode(DesktopState.self, from: raw)
        try state.validate()
        return state
    }

    /// Validation des invariants (FR-005 + data-model).
    public func validate() throws {
        guard !desktopUUID.isEmpty else { throw DesktopStateError.invalidUUID(desktopUUID) }
        // UUID format check léger : 36 chars avec tirets, ou alphanumérique non vide.
        // SkyLight peut retourner soit UUID standard, soit autre forme — on reste tolérant.
        if let current = currentStageID,
           !stages.isEmpty,
           !stages.contains(where: { $0.id == current.value }) {
            throw DesktopStateError.unknownCurrentStage(current.value)
        }
    }
}

/// Override de gaps spécifique à un desktop. Tous les champs nil → pas d'override.
public struct GapsOverride: Codable, Sendable, Equatable {
    public var top: Int?
    public var bottom: Int?
    public var left: Int?
    public var right: Int?

    public init(top: Int? = nil, bottom: Int? = nil,
                left: Int? = nil, right: Int? = nil) {
        self.top = top; self.bottom = bottom
        self.left = left; self.right = right
    }

    /// Résolution effective : remplace les valeurs globales par les overrides quand non-nil.
    public func resolve(over global: OuterGaps) -> OuterGaps {
        OuterGaps(top: top ?? global.top,
                  bottom: bottom ?? global.bottom,
                  left: left ?? global.left,
                  right: right ?? global.right)
    }
}

/// Miroir Codable d'un Stage, sans dépendre du target RoadieStagePlugin.
/// Les champs collent à ceux de `Stage` (Sources/RoadieStagePlugin/Stage.swift).
public struct PersistedStage: Codable, Sendable {
    public var id: String
    public var displayName: String
    public var memberWindows: [PersistedMember]
    public var lastActiveAt: Date

    public init(id: String, displayName: String,
                memberWindows: [PersistedMember] = [],
                lastActiveAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.memberWindows = memberWindows
        self.lastActiveAt = lastActiveAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case memberWindows = "members"
        case lastActiveAt = "last_active_at"
    }
}

public struct PersistedMember: Codable, Sendable {
    public var cgWindowID: UInt32
    public var bundleID: String
    public var titleHint: String
    public var savedFrame: PersistedRect?

    public init(cgWindowID: UInt32, bundleID: String,
                titleHint: String, savedFrame: PersistedRect? = nil) {
        self.cgWindowID = cgWindowID
        self.bundleID = bundleID
        self.titleHint = titleHint
        self.savedFrame = savedFrame
    }

    enum CodingKeys: String, CodingKey {
        case cgWindowID = "cg_window_id"
        case bundleID = "bundle_id"
        case titleHint = "title_hint"
        case savedFrame = "saved_frame"
    }
}

public struct PersistedRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

public enum DesktopStateError: Error, CustomStringConvertible {
    case invalidUUID(String)
    case unknownCurrentStage(String)

    public var description: String {
        switch self {
        case .invalidUUID(let s): return "invalid desktop UUID: '\(s)'"
        case .unknownCurrentStage(let s): return "current_stage_id '\(s)' not in stages"
        }
    }
}
