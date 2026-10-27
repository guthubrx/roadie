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
    /// Ordres donnés à Alfred par ses scripts (SPEC-093 FR-006) : traduits par Roadie, et non traduits.
    var orders: [String] = []
    var untranslated: [String] = []
    /// Au moins un ordre à Alfred (une simple citation, comme un dossier de cache, ne compte pas).
    var mentionsAlfred: Bool { !orders.isEmpty || !untranslated.isEmpty }
}

enum AlfredCompatibility {
    /// Entrées par lesquelles Roadie démarre un workflow.
    static var entryTypes: Set<String> {
        ["input.scriptfilter", "input.keyword", "input.listfilter", "input.filefilter", "trigger.hotkey", "trigger.external",
         "trigger.action", "trigger.universalaction", "trigger.fallback"]
    }

    /// État d'un workflow : briques non exécutées, interpréteurs absents, entrées complètes. O(o + c).
    static func report(_ workflow: AlfredWorkflow, tasksRoot: URL = AlfredAutomationTasks.root) -> AlfredCompatibilityReport {
        let supported = AlfredWorkflowEngine.supportedTypes
        var missingByObject: [String: String] = [:]
        for object in workflow.objects.values {
            if !supported.contains(object.type) && !entryTypes.contains(object.type) {
                missingByObject[object.uid] = object.type
            } else if object.type == "automation.task", AlfredAutomationTasks.task(object.string("taskuid") ?? "", root: tasksRoot) == nil {
                missingByObject[object.uid] = "tâches d'automatisation absentes (roadie workflow tasks update)"
            } else if object.type == "userinterface.grid", let source = object.int("inputtype"), source != 0 {
                // Source de la grille (SPEC-092 FR-002) : 1 = script du dossier ; toute autre est inconnue.
                if source != 1 {
                    missingByObject[object.uid] = "userinterface.grid:inputtype:\(source)"
                } else if case .failure(let failure) = AlfredScriptRunner.argv(for: AlfredScript(language: 8, source: "", file: object.string("inputfile") ?? ""),
                                                                               arguments: [], folder: workflow.folder) {
                    missingByObject[object.uid] = failure.message
                }
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
        let alfredOrders = orders(workflow)
        return AlfredCompatibilityReport(id: workflow.id, name: workflow.name, bundleID: workflow.bundleID, source: workflow.source,
                                         keywords: Array(Set(keywords)).sorted(), state: state,
                                         missing: Array(Set(missingByObject.values)).sorted(), orders: alfredOrders.translated,
                                         untranslated: alfredOrders.untranslated)
    }

    /// Ordres à Alfred des scripts en ligne et des fichiers de script du dossier (1 Mo au plus chacun),
    /// reconnus par les motifs de la traduction (SPEC-093 research R6). O(f × n).
    static func orders(_ workflow: AlfredWorkflow) -> (translated: [String], untranslated: [String]) {
        var texts = workflow.objects.values.flatMap { object in ["script", "applescript"].compactMap { object.string($0) } }
        let files = ((try? FileManager.default.contentsOfDirectory(at: workflow.folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { ["sh", "zsh", "js", "py", "rb", "applescript", ""].contains($0.pathExtension) }
        for file in files {
            guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < 1_048_576,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            texts.append(text)
        }
        return AlfredBridge.orders(in: texts.joined(separator: "\n"))
    }

    /// Fiches de tous les workflows d'un dossier, et totaux par état. O(W × (o + c)).
    static func check(folder: URL) -> [AlfredCompatibilityReport] {
        AlfredWorkflowIndex.children(of: folder).compactMap { AlfredWorkflow.load(folder: $0, source: .roadie) }.map { report($0) }
    }
}
