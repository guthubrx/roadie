import Foundation

/// Fiche de compatibilité d'un workflow avec Roadie (SPEC-088 FR-010).
struct AlfredCompatibilityReport: Equatable, Sendable {
    enum State: String, Sendable {
        /// Toutes ses briques sont exécutées.
        case complete
        /// Au moins une entrée marche entièrement.
        case partial
        case unusable
    }

    let id: String
    let name: String
    let bundleID: String
    let source: AlfredWorkflow.Source
    let keywords: [String]
    let state: State
    /// Briques ou interpréteurs absents, triés.
    let missing: [String]
    /// Le workflow parle à Alfred lui-même (AppleScript vers `com.runningwithcrayons.Alfred`).
    let mentionsAlfred: Bool
}

enum AlfredCompatibility {
    /// Entrées par lesquelles Roadie démarre un workflow.
    static var entryTypes: Set<String> { ["input.scriptfilter", "input.keyword"] }

    /// État d'un workflow : briques non exécutées, interpréteurs absents, entrées complètes. O(o + c).
    static func report(_ workflow: AlfredWorkflow) -> AlfredCompatibilityReport {
        let supported = AlfredWorkflowEngine.supportedTypes
        var missingByObject: [String: String] = [:]
        for object in workflow.objects.values {
            if !supported.contains(object.type) && !entryTypes.contains(object.type) {
                missingByObject[object.uid] = object.type
            } else if let script = AlfredScript(object: object),
                      case .failure(let failure) = AlfredScriptRunner.argv(for: script, arguments: [], folder: workflow.folder) {
                missingByObject[object.uid] = failure.message
            }
        }
        func reachable(_ start: String) -> Set<String> {
            var seen: Set<String> = [], stack = [start]
            while let uid = stack.popLast() {
                guard seen.insert(uid).inserted else { continue }
                stack += (workflow.connections[uid] ?? []).map(\.destination).filter { workflow.objects[$0] != nil }
            }
            return seen
        }
        let entries = workflow.objects.values.filter { entryTypes.contains($0.type) }
        let completeEntry = entries.contains { reachable($0.uid).allSatisfy { missingByObject[$0] == nil } }
        let state: AlfredCompatibilityReport.State = missingByObject.isEmpty && !entries.isEmpty ? .complete
            : completeEntry ? .partial : .unusable
        let keywords = AlfredWorkflowIndex.entries([workflow]).map(\.keyword)
        return AlfredCompatibilityReport(id: workflow.id, name: workflow.name, bundleID: workflow.bundleID, source: workflow.source,
                                         keywords: Array(Set(keywords)).sorted(), state: state,
                                         missing: Array(Set(missingByObject.values)).sorted(), mentionsAlfred: mentionsAlfred(workflow))
    }

    /// Recherche de l'identifiant d'Alfred dans `info.plist` et les scripts du dossier (1 Mo au plus chacun). O(f).
    static func mentionsAlfred(_ workflow: AlfredWorkflow) -> Bool {
        let markers = ["com.runningwithcrayons.Alfred", "application \"Alfred", "Application(\"com.runningwithcrayons", "Application('com.runningwithcrayons"]
        let files = ((try? FileManager.default.contentsOfDirectory(at: workflow.folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { ["plist", "sh", "zsh", "js", "py", "rb", "applescript", "scpt", ""].contains($0.pathExtension) }
        for file in files {
            guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < 1_048_576,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if markers.contains(where: text.contains) { return true }
        }
        return false
    }

    /// Fiches de tous les workflows d'un dossier, et totaux par état. O(W × (o + c)).
    static func check(folder: URL) -> [AlfredCompatibilityReport] {
        AlfredWorkflowIndex.children(of: folder).compactMap { AlfredWorkflow.load(folder: $0, source: .roadie) }.map(report)
    }
}
