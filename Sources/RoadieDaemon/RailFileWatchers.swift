import Darwin
import Foundation

/// Surveille un fichier ou un dossier et appelle `onChange` à chaque modification (SPEC-016 FR-026).
///
/// Le descripteur est fermé une seule fois, par le cancel handler de la source : `stop()` et `start()` ne
/// font que l'annuler. Un double `close()` pourrait fermer un descripteur déjà réattribué à un autre fichier.
/// Si le fichier est renommé ou supprimé (écriture atomique par remplacement), la surveillance se réarme.
@MainActor
final class RailFileWatcher {
    private let path: () -> String
    private let observedFile: (() -> String)?
    private var observedStamp: [Int64]?
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

    /// `path` est évalué à chaque (ré)armement : le chemin peut dépendre d'un état (dossier créé entre-temps).
    init(path: @escaping () -> String, observedFile: (() -> String)? = nil, onChange: @escaping @MainActor () -> Void) {
        self.path = path
        self.observedFile = observedFile
        self.onChange = onChange
    }

    func start() {
        stop()
        let watchedPath = path()
        observedStamp = observedFile.map { Self.stamp($0()) }
        let fd = open(watchedPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let mustRearm = source.data.contains(.rename) || source.data.contains(.delete)
            Task { @MainActor in
                // Une source annulée entre-temps (stop ou réarmement) ne doit plus rien déclencher.
                guard let self, self.source === source else { return }
                if let observedFile = self.observedFile {
                    let stamp = Self.stamp(observedFile())
                    if stamp != self.observedStamp {
                        self.observedStamp = stamp
                        self.onChange()
                    }
                } else {
                    self.onChange()
                }
                if mustRearm {
                    self.start()
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    /// Le dossier reste observé même si le fichier n’existe pas encore.
    private static func stamp(_ path: String) -> [Int64] {
        var info = stat()
        guard stat(path, &info) == 0 else { return [-1] }
        return [Int64(info.st_ino), Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec), Int64(info.st_size)]
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
