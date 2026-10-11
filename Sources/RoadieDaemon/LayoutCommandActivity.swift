import Foundation
import os
import RoadieCore

/// Fenêtre d'activité des commandes de disposition, partagée entre processus via un fichier.
/// Les écritures (lecture du délai courant puis prolongation) se font sous `FileLock` exclusif :
/// le verrou protège à la fois les threads du processus (un descripteur par prise) et les autres
/// processus. Les lectures restent sans verrou (écriture atomique par rename).
/// Seul état en mémoire : le dernier contenu lu et la signature du fichier (SPEC-017 A7), sous verrou
/// interne. Une lecture ne relit le fichier que si sa signature a changé.
public final class LayoutCommandActivity: Sendable {
    public static let shared = LayoutCommandActivity(enabled: !TestEnvironment.isRunningTests)

    private let url: URL
    private let enabled: Bool
    private let lastRead = OSAllocatedUnfairLock<(signature: FileSignature, entries: Entries)?>(initialState: nil)

    public init(path: String = "~/.local/state/roadies/layout-command-activity", enabled: Bool = true) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.enabled = enabled
    }

    /// Activité courante : délai le plus lointain, et périmètre. `isGlobal` vrai si une commande
    /// sans scope est active (tout le tick est concerné) ; sinon seuls `scopes` le sont.
    public struct Activity: Equatable, Sendable {
        public var activeUntil: Date
        public var isGlobal: Bool
        public var scopes: Set<StageScope>

        /// Vrai si une commande active touche ce scope. La comparaison porte sur l'écran et le
        /// bureau : une commande de stage change la stage active, la stage seule ne suffit pas.
        // O(s) — s = scopes marqués.
        public func covers(_ scope: StageScope) -> Bool {
            isGlobal || scopes.contains { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }
        }
    }

    /// Marque une commande active. Sans `scopes`, l'activité est globale (comportement historique) ;
    /// avec des scopes, le maintien n'exclut que ceux-là (SPEC-016 FR-040).
    public func markActive(reason: String, scopes: Set<StageScope> = [], now: Date = Date(), holdSeconds: TimeInterval = 2.0) {
        guard enabled else { return }
        extendActiveUntil(now.addingTimeInterval(holdSeconds), scopes: scopes, reason: reason, now: now)
    }

    public func finish(reason: String = "finished", scopes: Set<StageScope> = [], now: Date = Date(), graceSeconds: TimeInterval = 1.2) {
        guard enabled else { return }
        extendActiveUntil(now.addingTimeInterval(graceSeconds), scopes: scopes, reason: reason, now: now)
    }

    public func reset() {
        withFileLock {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Rien à effacer.
            } catch {
                fputs("roadie: layout command activity not reset: \(error)\n", stderr)
            }
        }
    }

    public func isActive(now: Date = Date()) -> Bool {
        activity(now: now) != nil
    }

    /// Lecture seule : un délai expiré est simplement ignoré. Le fichier n'est plus supprimé ici,
    /// car une suppression sans verrou pouvait effacer une prolongation écrite entre-temps.
    public func activeUntil(now: Date = Date()) -> Date? {
        activity(now: now)?.activeUntil
    }

    /// Activité non expirée (globale ou par scope), nil si aucune. Lecture sans verrou.
    public func activity(now: Date = Date()) -> Activity? {
        guard enabled else { return nil }
        let entries = readEntries().pruned(now: now)
        let expiries = [entries.global].compactMap { $0 } + Array(entries.scopes.values)
        guard let activeUntil = expiries.max() else { return nil }
        return Activity(activeUntil: activeUntil, isGlobal: entries.global != nil, scopes: Set(entries.scopes.keys))
    }

    /// Prolonge le délai global ou ceux des scopes (jamais de raccourcissement) en une transaction
    /// exclusive. Les entrées expirées sont retirées au passage.
    private func extendActiveUntil(_ candidate: Date, scopes: Set<StageScope>, reason: String, now: Date) {
        withFileLock {
            var entries = readEntries().pruned(now: now)
            if scopes.isEmpty {
                entries.global = max(entries.global ?? .distantPast, candidate)
            }
            for scope in scopes {
                entries.scopes[scope] = max(entries.scopes[scope] ?? .distantPast, candidate)
            }
            do {
                try entries.payload(reason: reason).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                fputs("roadie: layout command activity not written: \(error)\n", stderr)
            }
        }
    }

    private func withFileLock(_ body: () -> Void) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileLock.withLock(path: FileLock.lockPath(for: url), mode: .exclusive, block: body)
        } catch {
            fputs("roadie: layout command activity not updated: \(error)\n", stderr)
        }
    }

    /// Contenu courant ; relu seulement si la signature du fichier a changé (A7). O(1) si inchangé.
    private func readEntries() -> Entries {
        let known = lastRead.withLock { $0 }
        switch JSONPersistence.readSigned(url, unless: known?.signature) {
        case .unchanged:
            return known?.entries ?? Entries()
        case .read(let signature, let data):
            let entries = String(data: data, encoding: .utf8).map(Entries.init(payload:)) ?? Entries()
            lastRead.withLock { $0 = (signature, entries) }
            return entries
        case .missing, .failed:
            return Entries()
        }
    }

    /// Contenu du fichier. Ligne 1 : délai global (0 si aucun), lu tel quel par les versions
    /// précédentes. Ligne 2 : raison. Lignes suivantes : `délai<TAB>écran<TAB>bureau<TAB>stage`.
    private struct Entries {
        var global: Date?
        var scopes: [StageScope: Date] = [:]

        init() {}

        init(payload: String) {
            let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
            if let first = lines.first, let timestamp = TimeInterval(first), timestamp > 0 {
                global = Date(timeIntervalSince1970: timestamp)
            }
            for line in lines.dropFirst(2) {
                let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                // Les identifiants refusent les valeurs vides ou nulles (precondition) : une ligne
                // abîmée est ignorée au lieu de faire tomber le processus.
                guard fields.count == 4,
                      let timestamp = TimeInterval(fields[0]),
                      let desktop = Int(fields[2]), desktop > 0,
                      !fields[1].isEmpty, !fields[3].isEmpty
                else { continue }
                let scope = StageScope(
                    displayID: DisplayID(rawValue: String(fields[1])),
                    desktopID: DesktopID(rawValue: desktop),
                    stageID: StageID(rawValue: String(fields[3]))
                )
                scopes[scope] = Date(timeIntervalSince1970: timestamp)
            }
        }

        func pruned(now: Date) -> Entries {
            var copy = self
            if let global, global < now { copy.global = nil }
            copy.scopes = scopes.filter { $0.value >= now }
            return copy
        }

        func payload(reason: String) -> String {
            let sanitizedReason = reason.replacingOccurrences(of: "\n", with: " ")
            var lines = ["\(global?.timeIntervalSince1970 ?? 0)", sanitizedReason]
            for (scope, expiry) in scopes {
                lines.append("\(expiry.timeIntervalSince1970)\t\(scope.displayID.rawValue)\t\(scope.desktopID.rawValue)\t\(scope.stageID.rawValue)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
