import Foundation
import Testing
import RoadieDaemon

@Suite
struct ComponentLockFileTests {
    private func uniqueComponent() -> String {
        "spec011-test-\(UUID().uuidString.prefix(8))"
    }

    @Test
    func acquireWritesPidFileAndReleaseRemovesIt() throws {
        let component = uniqueComponent()
        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        let path = ComponentLockFile.pidFilePath(for: component)
        #expect(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(content == String(ProcessInfo.processInfo.processIdentifier))
        lock.release()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test
    func doubleAcquireOnSameLiveProcessThrowsAlreadyRunning() throws {
        let component = uniqueComponent()
        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        defer { lock.release() }

        let competing = ComponentLockFile(component: component)
        do {
            try competing.acquire()
            Issue.record("expected ComponentLockError.alreadyRunning")
        } catch ComponentLockError.alreadyRunning(let pid) {
            #expect(pid == ProcessInfo.processInfo.processIdentifier)
        }
    }

    @Test
    func acquireOverwritesStalePidFile() throws {
        let component = uniqueComponent()
        let path = ComponentLockFile.pidFilePath(for: component)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        // PID 1 (launchd) est garanti vivant donc on simule une stale via PID volontairement
        // grand qui ne peut pas correspondre a un process reel.
        let stalePid: Int32 = 999_999
        try "\(stalePid)\n".write(toFile: path, atomically: true, encoding: .utf8)

        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        defer { lock.release() }

        let content = try String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(content == String(ProcessInfo.processInfo.processIdentifier))
    }

    @Test
    func registryReturnsActiveLocksWithStartedAt() throws {
        let component = uniqueComponent()
        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        defer { lock.release() }

        let entries = ComponentLockFile.registry()
        let match = entries.first { $0.component == component }
        #expect(match != nil)
        #expect(match?.pid == ProcessInfo.processInfo.processIdentifier)
        #expect(match?.startedAt != nil)
    }
}
