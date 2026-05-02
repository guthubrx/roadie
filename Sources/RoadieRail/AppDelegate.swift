import AppKit
import Foundation

// SPEC-014 T033 + T035 — AppDelegate : PID-lock + lifecycle.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: RailController?

    private static let pidPath: String =
        (NSString(string: "~/.roadies/rail.pid").expandingTildeInPath as String)

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquirePIDLock() else {
            logErr("roadie-rail: another instance is already running — exiting")
            NSApp.terminate(nil)
            return
        }
        let c = RailController()
        controller = c
        c.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        releasePIDLock()
    }

    // MARK: - PID lock

    private func acquirePIDLock() -> Bool {
        let pidPath = Self.pidPath

        // Créer le répertoire parent si nécessaire.
        let dir = (pidPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir,
            withIntermediateDirectories: true)

        // Lire le PID existant.
        if let existing = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let pid = pid_t(existing.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // kill(pid, 0) retourne 0 si le process existe.
            if kill(pid, 0) == 0 {
                return false
            }
        }

        // Écrire notre PID.
        let myPID = "\(ProcessInfo.processInfo.processIdentifier)"
        try? myPID.write(toFile: pidPath, atomically: true, encoding: .utf8)
        return true
    }

    private func releasePIDLock() {
        try? FileManager.default.removeItem(atPath: Self.pidPath)
    }
}

private func logErr(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}
