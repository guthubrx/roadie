import Darwin
import RoadieCore
import Foundation

/// Prépare une copie sur le volume cible, puis échange atomiquement les deux éléments.
enum StagedFileReplacement {
    static func withDirectoryLock<T>(_ directory: URL, _ body: () throws -> T) throws -> T {
        let lockPath = directory.resolvingSymlinksInPath().path + ".lock"
        return try FileLock.withLock(path: lockPath, mode: .exclusive, block: body)
    }

    static func atomicSwap(_ first: URL, _ second: URL) throws {
        guard renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path, UInt32(RENAME_SWAP)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func install(from source: URL, to target: URL, replace: Bool,
                        swap: (URL, URL) throws -> Void = atomicSwap) throws {
        let manager = FileManager.default
        let directory = target.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // L'index des workflows lit uniquement les enfants contenant directement info.plist.
        // Le fichier préparé est un niveau plus bas, sans réserver de nom de workflow utilisateur.
        let workspace = directory.appendingPathComponent(".roadie-replacement-\(UUID().uuidString)")
        try manager.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let prepared = workspace.appendingPathComponent("item")
        defer {
            do { try manager.removeItem(at: workspace) }
            catch {
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSFileNoSuchFileError {
                    fputs(tr("roadie: impossible de supprimer le dossier de remplacement \(workspace.path): \(error)\n", "roadie: cannot delete the replacement folder \(workspace.path): \(error)\n"), stderr)
                }
            }
        }
        try manager.copyItem(at: source, to: prepared)
        if manager.fileExists(atPath: target.path) {
            guard replace else { throw CocoaError(.fileWriteFileExists) }
            try swap(prepared, target)
        } else {
            try manager.moveItem(at: prepared, to: target)
        }
    }
}
