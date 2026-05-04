import Foundation
import RoadieCore
import TOMLKit

// MARK: - StagePersistenceV2

/// Protocole de persistance orienté scope (SPEC-018).
/// Contrairement à StagePersistence (V1), chaque opération porte un StageScope
/// complet (displayUUID + desktopID + stageID), ce qui permet le stockage
/// hiérarchique par display/desktop sans couplage vers StageManager.
public protocol StagePersistenceV2: Sendable {
    /// Charge tous les stages connus, quelle que soit leur localisation.
    func loadAll() throws -> [StageScope: Stage]
    /// Persiste un stage à l'emplacement décrit par `scope`.
    func save(_ stage: Stage, at scope: StageScope) throws
    /// Supprime le fichier de stage associé à `scope`.
    func delete(at scope: StageScope) throws
    /// Persiste le scope actif (nil = aucun stage actif).
    func saveActiveStage(_ scope: StageScope?) throws
    /// Charge le scope actif depuis la source de vérité.
    func loadActiveStage() throws -> StageScope?
}

// MARK: - FlatStagePersistence

/// Implémentation mode global (compat V1) : stocke `<stagesDir>/<stageID>.toml`.
/// Les scopes retournés sont toujours `.global(stageID)`.
/// Compatible 100% avec le format SPEC-002 existant.
public final class FlatStagePersistence: StagePersistenceV2, @unchecked Sendable {
    private let stagesDir: String

    public init(stagesDir: String) {
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: self.stagesDir, withIntermediateDirectories: true)
    }

    public func loadAll() throws -> [StageScope: Stage] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: stagesDir)) ?? []
        var result: [StageScope: Stage] = [:]
        for entry in entries where entry.hasSuffix(".toml") && entry != "active.toml" {
            let path = "\(stagesDir)/\(entry)"
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
                  let stage = try? TOMLDecoder().decode(Stage.self, from: raw)
            else {
                logWarn("flat_stage_file_corrupt", ["path": path])
                continue
            }
            result[.global(stage.id)] = stage
        }
        return result
    }

    public func save(_ stage: Stage, at scope: StageScope) throws {
        // Ignore displayUUID et desktopID : mode flat.
        let path = "\(stagesDir)/\(stage.id.value).toml"
        let toml = try TOMLEncoder().encode(stage)
        try atomicWrite(toml, to: path)
        // SPEC-025 FR-009 — GC silencieux .legacy.* > 7 jours.
        FileBackedStagePersistence.gcLegacyFiles(in: stagesDir, olderThanDays: 7)
    }

    public func delete(at scope: StageScope) throws {
        let path = "\(stagesDir)/\(scope.stageID.value).toml"
        try? FileManager.default.removeItem(atPath: path)
    }

    public func saveActiveStage(_ scope: StageScope?) throws {
        let path = "\(stagesDir)/active.toml"
        let dict: [String: String] = ["current_stage": scope?.stageID.value ?? ""]
        let toml = try TOMLEncoder().encode(dict)
        try atomicWrite(toml, to: path)
    }

    public func loadActiveStage() throws -> StageScope? {
        let path = "\(stagesDir)/active.toml"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let parsed = try? TOMLDecoder().decode([String: String].self, from: raw),
              let active = parsed["current_stage"],
              !active.isEmpty
        else { return nil }
        return .global(StageID(active))
    }
}

// MARK: - NestedStagePersistence

/// Implémentation mode per_display : stocke `<stagesDir>/<displayUUID>/<desktopID>/<stageID>.toml`.
/// Le stage actif par contexte (display, desktop) est dans `_active.toml` au même niveau.
public final class NestedStagePersistence: StagePersistenceV2, @unchecked Sendable {
    private let stagesDir: String

    public init(stagesDir: String) {
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: self.stagesDir, withIntermediateDirectories: true)
    }

    public func loadAll() throws -> [StageScope: Stage] {
        var result: [StageScope: Stage] = [:]
        let uuids = (try? FileManager.default.contentsOfDirectory(atPath: stagesDir)) ?? []
        for uuid in uuids where !uuid.hasPrefix("_") && !uuid.hasSuffix(".toml") {
            let uuidDir = "\(stagesDir)/\(uuid)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: uuidDir, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            try loadDesktopsForUUID(uuid: uuid, uuidDir: uuidDir, into: &result)
        }
        return result
    }

    private func loadDesktopsForUUID(
        uuid: String,
        uuidDir: String,
        into result: inout [StageScope: Stage]
    ) throws {
        let desktopDirs = (try? FileManager.default.contentsOfDirectory(atPath: uuidDir)) ?? []
        for desktopStr in desktopDirs where !desktopStr.hasPrefix("_") {
            guard let desktopID = Int(desktopStr) else { continue }
            let desktopDir = "\(uuidDir)/\(desktopID)"
            loadStagesInDirectory(
                dir: desktopDir, uuid: uuid, desktopID: desktopID, into: &result)
        }
    }

    private func loadStagesInDirectory(
        dir: String,
        uuid: String,
        desktopID: Int,
        into result: inout [StageScope: Stage]
    ) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for file in files where file.hasSuffix(".toml") && file != "_active.toml" {
            let path = "\(dir)/\(file)"
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
                  let stage = try? TOMLDecoder().decode(Stage.self, from: raw)
            else {
                logWarn("nested_stage_file_corrupt", ["path": path])
                continue
            }
            let scope = StageScope(displayUUID: uuid, desktopID: desktopID, stageID: stage.id)
            result[scope] = stage
        }
    }

    public func save(_ stage: Stage, at scope: StageScope) throws {
        let dir = contextDir(for: scope)
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/\(stage.id.value).toml"
        let toml = try TOMLEncoder().encode(stage)
        try atomicWrite(toml, to: path)
        // SPEC-025 FR-009 — GC silencieux .legacy.* > 7 jours dans tous les
        // sous-dossiers (récursif via stagesDir, car les .legacy peuvent être
        // au niveau stagesDir/* legacy historiques).
        FileBackedStagePersistence.gcLegacyFiles(in: dir, olderThanDays: 7)
        FileBackedStagePersistence.gcLegacyFiles(in: stagesDir, olderThanDays: 7)
    }

    public func delete(at scope: StageScope) throws {
        let path = "\(contextDir(for: scope))/\(scope.stageID.value).toml"
        try? FileManager.default.removeItem(atPath: path)
    }

    public func saveActiveStage(_ scope: StageScope?) throws {
        guard let scope, !scope.isGlobal else { return }
        let dir = contextDir(for: scope)
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/_active.toml"
        let dict: [String: String] = ["current_stage": scope.stageID.value]
        let toml = try TOMLEncoder().encode(dict)
        try atomicWrite(toml, to: path)
    }

    public func loadActiveStage() throws -> StageScope? {
        // Sans contexte display/desktop précis on ne peut pas charger.
        // L'appelant doit utiliser loadActiveStage(forDisplay:desktop:).
        return nil
    }

    /// Variante contextuelle : charge le stage actif pour un display/desktop donné.
    public func loadActiveStage(forDisplay uuid: String, desktop desktopID: Int) -> StageScope? {
        let dir = "\(stagesDir)/\(uuid)/\(desktopID)"
        let path = "\(dir)/_active.toml"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let parsed = try? TOMLDecoder().decode([String: String].self, from: raw),
              let active = parsed["current_stage"],
              !active.isEmpty
        else { return nil }
        return StageScope(displayUUID: uuid, desktopID: desktopID, stageID: StageID(active))
    }

    // MARK: - Helpers

    private func contextDir(for scope: StageScope) -> String {
        "\(stagesDir)/\(scope.displayUUID)/\(scope.desktopID)"
    }
}

// MARK: - atomicWrite

/// Écriture atomique : tmpfile dans le même dossier + rename.
/// Garantit qu'un crash pendant l'écriture ne corrompt pas le fichier original.
func atomicWrite(_ content: String, to path: String) throws {
    let tmp = path + ".tmp"
    try content.write(toFile: tmp, atomically: false, encoding: .utf8)
    // moveItem remplace la destination si elle existe (atomique sur même volume).
    _ = try FileManager.default.replaceItemAt(
        URL(fileURLWithPath: path),
        withItemAt: URL(fileURLWithPath: tmp),
        backupItemName: nil,
        options: .usingNewMetadataOnly
    )
}
