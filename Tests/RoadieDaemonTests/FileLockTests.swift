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
    func persistDecisionFollowsReaderModeEnvironmentValue() {
        // Fonction pure : pas de setenv, donc pas d'effet de bord sur les suites parallèles.
        #expect(SnapshotService.persistStateChanges(environmentValue: "0") == false)
        #expect(SnapshotService.persistStateChanges(environmentValue: "off") == false)
        #expect(SnapshotService.persistStateChanges(environmentValue: "1") == true)
        #expect(SnapshotService.persistStateChanges(environmentValue: nil) == true)
    }
}
