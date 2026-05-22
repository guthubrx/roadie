import Foundation
import Testing
import RoadieDaemon

@Suite
struct FileLockTests {
    private func uniqueLockPath() -> String {
        let dir = NSTemporaryDirectory() + "roadie-filelock-test-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/lock-\(UUID().uuidString.prefix(8)).lock"
    }

    @Test
    func acquireAndReleaseExclusive() throws {
        let path = uniqueLockPath()
        let lock = FileLock(path: path)
        try lock.acquire(mode: .exclusive)
        lock.release()
        // Second acquire OK apres release.
        try lock.acquire(mode: .exclusive)
        lock.release()
    }

    @Test
    func withLockExecutesBlockAndReleases() throws {
        let path = uniqueLockPath()
        var executed = false
        try FileLock.withLock(path: path) {
            executed = true
        }
        #expect(executed)
        // Apres withLock, on peut re-acquire immediatement.
        try FileLock.withLock(path: path) {
            #expect(true)
        }
    }

    @Test
    func sharedLockAllowsConcurrentReads() throws {
        let path = uniqueLockPath()
        let a = FileLock(path: path)
        let b = FileLock(path: path)
        try a.acquire(mode: .shared)
        // Deuxieme shared lock doit reussir immediatement (non bloquant en LOCK_SH).
        try b.acquire(mode: .shared)
        a.release()
        b.release()
    }

    @Test
    func lockPathForDataURL() {
        let dataURL = URL(fileURLWithPath: "/tmp/stages.json")
        #expect(FileLock.lockPath(for: dataURL) == "/tmp/stages.json.lock")
    }

    @Test
    func snapshotServiceDoesNotPersistWhenReaderModeEnabled() throws {
        // Test integratif minimal : on ne peut pas facilement injecter un mock
        // StageStore depuis l'exterieur, mais on peut verifier que la decision
        // de persistance respecte l'env var.
        setenv("ROADIE_PERSIST_STATE_CHANGES", "0", 1)
        #expect(SnapshotService.defaultPersistStateChanges == false)
        setenv("ROADIE_PERSIST_STATE_CHANGES", "1", 1)
        #expect(SnapshotService.defaultPersistStateChanges == true)
        unsetenv("ROADIE_PERSIST_STATE_CHANGES")
        #expect(SnapshotService.defaultPersistStateChanges == true) // default
    }
}
