import Foundation
import Testing
@testable import RoadieDaemon

struct Spec093PersistenceSafetyTests {
    private final class FailureCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test @MainActor func clearHistoryReportsCorruptionAndPreservesTheFile() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let history = sandbox.appendingPathComponent("history.json")
        let invalid = Data("{document abîmé".utf8)
        try invalid.write(to: history)

        let response = CLICommandRouter(launcherHistoryPath: history.path).run(["launcher", "history", "--clear"])

        #expect(response.exitCode != 0)
        #expect(!response.stderr.isEmpty)
        #expect(!response.stdout.contains("historique effacé"))
        #expect(try Data(contentsOf: history) == invalid)
    }

    @Test @MainActor func clearHistoryReportsAnInaccessibleDestination() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let blockedParent = sandbox.appendingPathComponent("regular-file")
        let marker = Data("ne pas modifier".utf8)
        try marker.write(to: blockedParent)

        let response = CLICommandRouter(launcherHistoryPath: blockedParent.appendingPathComponent("history.json").path)
            .run(["launcher", "history", "--clear"])

        #expect(response.exitCode != 0)
        #expect(!response.stderr.isEmpty)
        #expect(!response.stdout.contains("historique effacé"))
        #expect(try Data(contentsOf: blockedParent) == marker)
    }

    @Test func corruptLauncherFilesAreNotOverwrittenByMutations() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let invalid = Data("{document abîmé".utf8)
        func corrupt(_ name: String) throws -> URL {
            let file = sandbox.appendingPathComponent(name)
            try invalid.write(to: file)
            return file
        }

        let history = try corrupt("history.json")
        LauncherHistoryStore(path: history.path).record("cherche")
        #expect(try Data(contentsOf: history) == invalid)
        #expect(throws: JSONPersistence.PersistenceError.self) { try LauncherHistoryStore(path: history.path).clear() }
        #expect(try Data(contentsOf: history) == invalid)

        let memory = try corrupt("memory.json")
        LauncherMemoryStore(path: memory.path).update { $0.declined["a"] = Date() }
        #expect(try Data(contentsOf: memory) == invalid)

        let aliases = try corrupt("aliases.json")
        let alias = LauncherAlias(path: "/tmp/exemple", isApp: false, bundleID: nil, name: "Exemple", stage: nil,
                                  here: false, newStage: false, position: nil)
        #expect(throws: JSONPersistence.PersistenceError.self) { try LauncherAliasStore(path: aliases.path).save(alias, as: "ex") }
        #expect(try Data(contentsOf: aliases) == invalid)

        let projects = try corrupt("projects.json")
        #expect(throws: JSONPersistence.PersistenceError.self) {
            try StageProjectStore(path: projects.path).save(StageProject(name: "Exemple", savedAt: Date(), windows: [], tree: nil))
        }
        #expect(throws: JSONPersistence.PersistenceError.self) { try StageProjectStore(path: projects.path).delete("Exemple") }
        #expect(try Data(contentsOf: projects) == invalid)

        let ranking = try corrupt("ranking.json")
        LauncherRankingStore(path: ranking.path).recordVisit("exemple", query: "ex")
        #expect(try Data(contentsOf: ranking) == invalid)
    }

    @Test func concurrentMemoryUpdatesKeepBothChanges() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let store = LauncherMemoryStore(path: sandbox.appendingPathComponent("memory.json").path)
        let arrived = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        for key in ["a", "b"] {
            DispatchQueue.global().async(group: group) {
                store.update { book in
                    arrived.signal()
                    proceed.wait()
                    book.declined[key] = Date(timeIntervalSince1970: 2_000_000_000)
                }
            }
        }
        try #require(arrived.wait(timeout: .now() + 5) == .success)
        // Avant correction, les deux lectures peuvent se terminer avant leurs écritures. Après
        // correction, le second attend le verrou ; le délai libère alors le premier.
        _ = arrived.wait(timeout: .now() + 0.5)
        proceed.signal()
        proceed.signal()
        try #require(group.wait(timeout: .now() + 5) == .success)
        #expect(Set(store.load().declined.keys) == Set(["a", "b"]))
    }

    @Test func concurrentRankingVisitsKeepEveryCount() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-ranking-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let path = sandbox.appendingPathComponent("ranking.json").path
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let visits = 32

        DispatchQueue.concurrentPerform(iterations: visits) { _ in
            LauncherRankingStore(path: path).recordVisit("exemple", query: "ex", at: now, context: "stage")
        }

        let ranking = LauncherRankingStore(path: path).load(at: now)
        #expect(ranking.exactUses("exemple", query: "ex") == visits)
        #expect(ranking.exactUses("exemple", query: "ex", context: "stage") == visits)
    }

    @Test func concurrentAliasSavesKeepEveryName() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-alias-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let path = sandbox.appendingPathComponent("aliases.json").path
        let alias = LauncherAlias(path: "/tmp/exemple", isApp: false, bundleID: nil, name: "Exemple", stage: nil,
                                  here: false, newStage: false, position: nil)
        let failures = FailureCounter()
        let names = (0..<32).map { "ex\($0)" }

        DispatchQueue.concurrentPerform(iterations: names.count) { index in
            do { try LauncherAliasStore(path: path).save(alias, as: names[index]) }
            catch { failures.increment() }
        }

        #expect(failures.value == 0)
        #expect(Set(LauncherAliasStore(path: path).load().aliases.keys) == Set(names))
    }
}
