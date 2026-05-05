import Foundation
import Darwin
import RoadieCore

/// SPEC-026 — surveille le fichier TOML user et déclenche un reload quand il
/// change. Évite à l'utilisateur de faire `roadie daemon reload` après chaque
/// tweak de config.
///
/// Utilise `DispatchSource.makeFileSystemObjectSource` (kqueue derrière).
/// Notifie sur write/rename/delete (les éditeurs comme vim font rename).
/// Debounce 200ms pour éviter les reload en cascade pendant une sauvegarde.
@MainActor
public final class ConfigFileWatcher {
    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private static let debounceMs: UInt64 = 200_000_000   // 200ms
    private let onChange: @MainActor () -> Void

    public init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.path = (path as NSString).expandingTildeInPath
        self.onChange = onChange
    }

    public func start() {
        installWatcher()
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    private func installWatcher() {
        stop()
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            logWarn("config_watcher_open_failed", ["path": path, "errno": String(errno)])
            return
        }
        let queue = DispatchQueue.main
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        src.setCancelHandler { [weak self] in
            if let f = self?.fd, f >= 0 { close(f); self?.fd = -1 }
        }
        src.resume()
        source = src
        logInfo("config_watcher_started", ["path": path])
    }

    private func handleEvent() {
        // Beaucoup d'éditeurs font rename+delete (vim, sed). Re-installer le
        // watcher sur le nouveau fichier après le delay debounce. Sinon le fd
        // pointe vers l'inode supprimée et on ne reçoit plus rien.
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMs)
            guard let self = self else { return }
            // Re-install si le fichier a changé d'inode (rename/delete).
            self.installWatcher()
            logInfo("config_watcher_triggered", ["path": self.path])
            self.onChange()
        }
    }
}
