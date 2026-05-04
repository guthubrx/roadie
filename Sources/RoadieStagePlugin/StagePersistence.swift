import Foundation
import RoadieCore

// MARK: - StagePersistence

/// Protocol de persistance injecté dans StageManager.
/// Mode V1 : FileBackedStagePersistence (fichiers stages/*.toml, comportement historique).
/// Mode V2 : implémentation DesktopBackedStagePersistence dans RoadieDesktops.
/// Cette séparation permet au StageManager d'ignorer la source réelle de vérité
/// et garantit que les deux systèmes restent cohérents.
public protocol StagePersistence: Sendable {
    /// Persiste un stage (création ou mise à jour).
    func saveStage(_ stage: Stage)
    /// Supprime un stage persisté.
    func deleteStage(_ id: StageID)
    /// Persiste l'ID du stage actif (nil = aucun stage actif).
    func saveActiveStage(_ stageID: StageID?)
    /// Charge tous les stages depuis la source de vérité.
    func loadStages() -> [Stage]
    /// Charge l'ID du stage actif depuis la source de vérité.
    func loadActiveStage() -> StageID?
    /// Notifie la persistence qu'on bascule vers un nouveau desktop.
    /// Mode V1 (FileBackedStagePersistence) : no-op — c'est StageManager qui
    /// gère le swap de dossier indépendamment.
    /// Mode V2 (DesktopBackedStagePersistence) : met à jour l'ID courant pour
    /// que `loadStages()` lise le bon `RoadieDesktop`.
    func setDesktopID(_ id: Int)
    /// Vrai si la persistence lit les stages depuis des fichiers dont le chemin
    /// doit être mis à jour par StageManager lors d'un `reload(forDesktop:)`.
    /// Mode V1 : true. Mode V2 (DesktopRegistry) : false.
    var requiresPhysicalDirSwap: Bool { get }
}

// MARK: - FileBackedStagePersistence

/// Implémentation V1 : lit/écrit dans `<stagesDir>/<id>.toml`.
/// Comportement identique à l'ancien StageManager sans DesktopRegistry.
public final class FileBackedStagePersistence: StagePersistence, @unchecked Sendable {
    private let stagesDir: String

    public init(stagesDir: String) {
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: self.stagesDir, withIntermediateDirectories: true)
    }

    public func saveStage(_ stage: Stage) {
        let path = "\(stagesDir)/\(stage.id.value).toml"
        do {
            let toml = try TOMLEncoderBridge.encode(stage)
            try toml.write(toFile: path, atomically: true, encoding: .utf8)
            // SPEC-025 FR-009 — GC silencieux des .legacy.* > 7 jours dans le
            // même dossier. Idempotent. Tourne après chaque save (= au moment
            // où on touche déjà disque, coût marginal).
            Self.gcLegacyFiles(in: stagesDir, olderThanDays: 7)
        } catch {
            logError("stage save failed", ["id": stage.id.value, "err": "\(error)"])
        }
    }

    /// Supprime les fichiers `*.legacy.*` du dossier dont mtime > N jours.
    /// Silencieux par fichier (1 log avec compteur si > 0). Best-effort.
    static func gcLegacyFiles(in dir: String, olderThanDays days: Int) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var removed = 0
        for entry in entries where entry.contains(".legacy.") {
            let path = "\(dir)/\(entry)"
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime < cutoff {
                try? fm.removeItem(atPath: path)
                removed += 1
            }
        }
        if removed > 0 {
            logInfo("legacy_gc_done", ["removed": String(removed), "dir": dir])
        }
    }

    public func deleteStage(_ id: StageID) {
        let path = "\(stagesDir)/\(id.value).toml"
        try? FileManager.default.removeItem(atPath: path)
    }

    public func saveActiveStage(_ stageID: StageID?) {
        let path = "\(stagesDir)/active.toml"
        let dict: [String: String] = ["current_stage": stageID?.value ?? ""]
        if let toml = try? TOMLEncoderBridge.encodeDict(dict) {
            try? toml.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    public func loadStages() -> [Stage] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: stagesDir)
        else { return [] }
        var result: [Stage] = []
        for entry in entries where entry.hasSuffix(".toml") && entry != "active.toml" {
            let path = "\(stagesDir)/\(entry)"
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
                  let stage = try? TOMLDecoderBridge.decode(Stage.self, from: raw)
            else {
                logWarn("stage file corrupt", ["path": path])
                continue
            }
            result.append(stage)
        }
        return result
    }

    public func loadActiveStage() -> StageID? {
        let activePath = "\(stagesDir)/active.toml"
        guard let raw = try? String(contentsOfFile: activePath, encoding: .utf8),
              let parsed = try? TOMLDecoderBridge.decodeDict(raw),
              let active = parsed["current_stage"],
              !active.isEmpty
        else { return nil }
        return StageID(active)
    }

    /// No-op en mode V1 : c'est StageManager qui gère le swap du dossier.
    public func setDesktopID(_ id: Int) {}

    /// Vrai : le chemin du dossier doit être swappé par StageManager.
    public var requiresPhysicalDirSwap: Bool { true }
}

// MARK: - TOMLEncoderBridge / TOMLDecoderBridge

/// Pont léger pour encapsuler TOMLKit sans que StagePersistence.swift en importe directement.
/// Permet de conserver l'import TOMLKit localisé dans StageManager.swift (existant).
import TOMLKit

enum TOMLEncoderBridge {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        try TOMLEncoder().encode(value)
    }
    static func encodeDict(_ dict: [String: String]) throws -> String {
        try TOMLEncoder().encode(dict)
    }
}

enum TOMLDecoderBridge {
    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try TOMLDecoder().decode(type, from: string)
    }
    static func decodeDict(_ string: String) throws -> [String: String] {
        try TOMLDecoder().decode([String: String].self, from: string)
    }
}
