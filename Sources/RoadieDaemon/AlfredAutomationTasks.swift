import Foundation
import RoadieCore

/// Tâche d'automatisation officielle d'Alfred (SPEC-089 FR-007, research R5) : script, langage,
/// réglages et leurs défauts, réglage qui remplace l'entrée.
struct AlfredAutomationTask: Equatable, Sendable {
    let uid: String
    let name: String
    let folder: URL
    let script: String
    let scriptType: Int
    let defaults: [String: String]
    let inputOverride: String?
}

/// Tâches lues dans `~/.roadies/alfred-tasks/Tasks/<uid>/alfredtask.json`, téléchargées à la demande
/// depuis le dépôt public `alfredapp/automation-tasks` (BSD-3) ; jamais livrées avec Roadie.
enum AlfredAutomationTasks {
    static var root: URL { URL(fileURLWithPath: NSString(string: "~/.roadies/alfred-tasks").expandingTildeInPath, isDirectory: true) }
    static let archive = "https://github.com/alfredapp/automation-tasks/archive/refs/heads/main.zip"

    /// Tâche par son identifiant (« groupe/sous-groupe/nom ») ; nil si absente. O(1) lectures.
    static func task(_ uid: String, root: URL = root) -> AlfredAutomationTask? {
        let folder = root.appendingPathComponent("Tasks").appendingPathComponent(uid, isDirectory: true)
        guard !uid.contains(".."), let data = try? Data(contentsOf: folder.appendingPathComponent("alfredtask.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? String else { return nil }
        var defaults: [String: String] = [:]
        for setting in json["configurableConfig"] as? [[String: Any]] ?? [] {
            guard let variable = setting["variable"] as? String else { continue }
            defaults[variable] = value((setting["config"] as? [String: Any])?["default"])
        }
        return AlfredAutomationTask(uid: uid, name: json["taskName"] as? String ?? uid, folder: folder, script: script,
                                    scriptType: (json["scriptType"] as? NSNumber)?.intValue ?? 11, defaults: defaults,
                                    inputOverride: json["inputOverride"] as? String)
    }

    /// Valeur d'un réglage pour l'environnement du script : vrai/faux en « 1 »/« 0 », comme Alfred.
    static func value(_ any: Any?) -> String {
        switch any {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue ? "1" : "0"
        case let number as NSNumber: number.stringValue
        case let text as String: text
        default: ""
        }
    }

    /// Réglages du workflow (`tasksettings`, remplacements faits) sur les défauts de la tâche ; un
    /// réglage `inputOverride` non vide remplace l'entrée. Script lancé dans le dossier de la tâche
    /// (aides communes `../.common/…`). O(s).
    static func run(_ task: AlfredAutomationTask, settings: [String: String], input: [String], workflow: AlfredWorkflow,
                    variables: [String: String]) async -> AlfredScriptResult {
        let merged = task.defaults.merging(settings) { $1 }
        var arguments = input
        if let override = task.inputOverride, let value = merged[override], !value.isEmpty {
            arguments = value.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        return await AlfredScriptRunner.run(AlfredScript(language: task.scriptType, source: task.script), query: arguments.joined(separator: "\t"),
                                            arguments: arguments, workflow: workflow, variables: variables.merging(merged) { $1 },
                                            directory: task.folder)
    }

    /// Télécharge l'archive publique et remplace les tâches installées ; la licence BSD est gardée à
    /// côté. Outils système (`curl`, `ditto`). Bloquant : commande en ligne seulement.
    static func update(root: URL = root) throws -> Int {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let zip = staging.appendingPathComponent("tasks.zip")
        try runTool("/usr/bin/curl", ["-fsSL", "--max-time", "120", "-o", zip.path, archive])
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard let extracted = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Tasks").path) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try install(extracted: extracted, root: root)
        let enumerator = FileManager.default.enumerator(atPath: root.appendingPathComponent("Tasks").path)
        var count = 0
        while let path = enumerator?.nextObject() as? String { if path.hasSuffix("alfredtask.json") { count += 1 } }
        return count
    }

    /// Remplace seulement Tasks et LICENSE. Les autres fichiers du dossier restent en place.
    static func install(extracted: URL, root: URL,
                        swap: (URL, URL) throws -> Void = StagedFileReplacement.atomicSwap) throws {
        let manager = FileManager.default
        // Un dossier utilisateur peut être un lien symbolique : préparer et remplacer sa cible,
        // jamais supprimer des éléments en passant par une copie du lien.
        let destination = root.resolvingSymlinksInPath()
        for name in ["Tasks", "LICENSE"] where !manager.fileExists(atPath: extracted.appendingPathComponent(name).path) {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileLock.withLock(path: destination.path + ".lock", mode: .exclusive) {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            let staging = destination.appendingPathComponent(".roadie-tasks-install-\(UUID().uuidString)")
            try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var keepStaging = false
            defer {
                if !keepStaging {
                    do { try manager.removeItem(at: staging) }
                    catch { fputs(tr("roadie: impossible de supprimer \(staging.path): \(error)\n", "roadie: cannot delete \(staging.path): \(error)\n"), stderr) }
                }
            }
            for name in ["Tasks", "LICENSE"] {
                try manager.copyItem(at: extracted.appendingPathComponent(name), to: staging.appendingPathComponent(name))
            }
            var applied: [(name: String, existed: Bool)] = []
            do {
                for name in ["Tasks", "LICENSE"] {
                    let prepared = staging.appendingPathComponent(name)
                    let target = destination.appendingPathComponent(name)
                    let existed = manager.fileExists(atPath: target.path)
                    if existed { try swap(prepared, target) }
                    else { try manager.moveItem(at: prepared, to: target) }
                    applied.append((name, existed))
                }
            } catch {
                let original = error
                for item in applied.reversed() {
                    let prepared = staging.appendingPathComponent(item.name)
                    let target = destination.appendingPathComponent(item.name)
                    do {
                        if item.existed { try swap(prepared, target) }
                        else { try manager.moveItem(at: target, to: prepared) }
                    } catch {
                        keepStaging = true
                        fputs(tr("roadie: retour arrière incomplet ; fichiers conservés dans \(staging.path): \(error)\n", "roadie: incomplete rollback; files kept in \(staging.path): \(error)\n"), stderr)
                    }
                }
                throw original
            }
        }
    }

    private static func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
    }
}
