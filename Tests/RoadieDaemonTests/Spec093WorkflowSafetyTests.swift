import Foundation
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec093WorkflowSafetyTests {
    private func archive(identifier: String, in sandbox: URL) throws -> URL {
        var fixture = WorkflowFixture()
        fixture.bundleID = identifier
        let workflow = try fixture.write(in: sandbox.appendingPathComponent("source"))
        let archive = sandbox.appendingPathComponent("test.alfredworkflow")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", workflow.folder.path, archive.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return archive
    }

    @Test(arguments: [".", ".."])
    func installationRefusesReservedNamesBeforeReplacingAnything(_ identifier: String) throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let parent = sandbox.appendingPathComponent("protected")
        let workflows = parent.appendingPathComponent("workflows")
        let existing = workflows.appendingPathComponent("autre-workflow")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let parentMarker = parent.appendingPathComponent("configuration")
        let workflowMarker = existing.appendingPathComponent("donnees")
        try Data("conserver".utf8).write(to: parentMarker)
        try Data("conserver".utf8).write(to: workflowMarker)
        let file = try archive(identifier: identifier, in: sandbox)

        let response = CLICommandRouter(workflowInstallationFolder: workflows)
            .run(["workflow", "install", file.path, "--replace"])

        #expect(response.exitCode != 0)
        #expect(response.stderr.contains("identifiant de dossier invalide"))
        #expect(FileManager.default.fileExists(atPath: parentMarker.path))
        #expect(FileManager.default.fileExists(atPath: workflowMarker.path))
    }

    @Test(arguments: [".", ".."])
    func removalRefusesReservedNamesEvenWhenParentContainsPlist(_ identifier: String) throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let workflows = sandbox.appendingPathComponent("workflows")
        try FileManager.default.createDirectory(at: workflows, withIntermediateDirectories: true)
        let parentMarker = sandbox.appendingPathComponent("info.plist")
        let workflowMarker = workflows.appendingPathComponent("info.plist")
        try Data("conserver".utf8).write(to: parentMarker)
        try Data("conserver".utf8).write(to: workflowMarker)

        let response = CLICommandRouter(workflowInstallationFolder: workflows)
            .run(["workflow", "remove", identifier])

        #expect(response.exitCode != 0)
        #expect(response.stderr.contains("identifiant de dossier invalide"))
        #expect(FileManager.default.fileExists(atPath: parentMarker.path))
        #expect(FileManager.default.fileExists(atPath: workflowMarker.path))
    }

    @Test func ordinaryInstallReplaceAndRemoveStaySupported() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let workflows = sandbox.appendingPathComponent("workflows")
        let file = try archive(identifier: "test/groupe", in: sandbox)
        let target = workflows.appendingPathComponent("test-groupe")
        let router = CLICommandRouter(workflowInstallationFolder: workflows)

        #expect(router.run(["workflow", "install", file.path]).exitCode == 0)
        let marker = target.appendingPathComponent("ancien")
        try Data("ancien".utf8).write(to: marker)
        #expect(router.run(["workflow", "install", file.path]).exitCode != 0)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(router.run(["workflow", "install", file.path, "--replace"]).exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(router.run(["workflow", "remove", "test/groupe"]).exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func failedReplacementKeepsThePreviousWorkflow() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-replace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let source = sandbox.appendingPathComponent("source")
        let target = sandbox.appendingPathComponent("workflows/installed")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("nouveau".utf8).write(to: source.appendingPathComponent("info.plist"))
        let old = target.appendingPathComponent("ancien")
        try Data("conserver".utf8).write(to: old)
        var failed = false
        do {
            try StagedFileReplacement.install(from: source, to: target, replace: true) { _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        } catch { failed = true }
        #expect(failed)
        #expect(try Data(contentsOf: old) == Data("conserver".utf8))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("info.plist").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path) == ["installed"])
    }

    @Test func preparedWorkflowsAreNeverIndexed() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        for name in ["normal", ".autre", ".roadie-replacement-utilisateur"] {
            let folder = sandbox.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: folder.appendingPathComponent("info.plist"))
        }
        let prepared = sandbox.appendingPathComponent(".roadie-replacement-temporaire/item")
        try FileManager.default.createDirectory(at: prepared, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: prepared.appendingPathComponent("info.plist"))
        #expect(Set(AlfredWorkflowIndex.children(of: sandbox).map(\.lastPathComponent))
                == Set(["normal", ".autre", ".roadie-replacement-utilisateur"]))
    }

    @Test func interruptedReplacementRemainsHiddenAndIsNotDiscardedByTheNextInstall() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-leftover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let workflows = sandbox.appendingPathComponent("workflows")
        let previous = workflows.appendingPathComponent(".roadie-replacement-interrompu/item")
        let target = workflows.appendingPathComponent("actif")
        let source = sandbox.appendingPathComponent("source")
        for folder in [previous, target, source] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("workflow".utf8).write(to: folder.appendingPathComponent("info.plist"))
        }
        let retained = previous.appendingPathComponent("temoin")
        try Data("ancienne installation".utf8).write(to: retained)

        try StagedFileReplacement.install(from: source, to: target, replace: true)

        #expect(try Data(contentsOf: retained) == Data("ancienne installation".utf8))
        #expect(AlfredWorkflowIndex.children(of: workflows).map(\.lastPathComponent) == ["actif"])
    }

    @Test func previouslyValidReplacementPrefixCanStillBeInstalledAndRemoved() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-prefix-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let workflows = sandbox.appendingPathComponent("workflows")
        let identifier = ".roadie-replacement-utilisateur"
        let file = try archive(identifier: identifier, in: sandbox)
        let router = CLICommandRouter(workflowInstallationFolder: workflows)
        #expect(router.run(["workflow", "install", file.path]).exitCode == 0)
        #expect(AlfredWorkflowIndex.children(of: workflows).map(\.lastPathComponent) == [identifier])
        #expect(router.run(["workflow", "remove", identifier]).exitCode == 0)
    }

    @Test func workflowInstallationAndRemovalShareOneDirectoryLock() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let folder = sandbox.appendingPathComponent("workflows")
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            try? StagedFileReplacement.withDirectoryLock(folder) {
                firstEntered.signal()
                releaseFirst.wait()
            }
        }
        defer { releaseFirst.signal() }
        try #require(firstEntered.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async(group: group) {
            try? StagedFileReplacement.withDirectoryLock(folder) { secondEntered.signal() }
        }
        #expect(secondEntered.wait(timeout: .now() + 0.2) == .timedOut)
        releaseFirst.signal()
        #expect(secondEntered.wait(timeout: .now() + 5) == .success)
        #expect(group.wait(timeout: .now() + 5) == .success)
    }

    @Test func automationUpdatePreservesOldFilesOnFailureAndUnrelatedFilesOnSuccess() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let extracted = sandbox.appendingPathComponent("download")
        let installed = sandbox.appendingPathComponent("installed")
        for folder in [extracted, installed] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tasks"), withIntermediateDirectories: true)
        }
        let oldTask = installed.appendingPathComponent("Tasks/ancien")
        let oldLicense = installed.appendingPathComponent("LICENSE")
        let unrelated = installed.appendingPathComponent("personnel")
        try Data("ancien".utf8).write(to: oldTask)
        try Data("ancienne licence".utf8).write(to: oldLicense)
        try Data("à garder".utf8).write(to: unrelated)
        try Data("nouveau".utf8).write(to: extracted.appendingPathComponent("Tasks/nouveau"))
        try Data("nouvelle licence".utf8).write(to: extracted.appendingPathComponent("LICENSE"))

        #expect(throws: (any Error).self) {
            try AlfredAutomationTasks.install(extracted: extracted, root: installed) { _, _ in throw CocoaError(.fileWriteUnknown) }
        }
        #expect(try Data(contentsOf: oldTask) == Data("ancien".utf8))
        #expect(try Data(contentsOf: oldLicense) == Data("ancienne licence".utf8))
        #expect(try Data(contentsOf: unrelated) == Data("à garder".utf8))

        try AlfredAutomationTasks.install(extracted: extracted, root: installed)
        #expect(!FileManager.default.fileExists(atPath: oldTask.path))
        #expect(try Data(contentsOf: installed.appendingPathComponent("Tasks/nouveau")) == Data("nouveau".utf8))
        #expect(try Data(contentsOf: oldLicense) == Data("nouvelle licence".utf8))
        #expect(try Data(contentsOf: unrelated) == Data("à garder".utf8))
    }

    @Test func automationUpdateRollsBackFirstSwapIfSecondFails() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-rollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let extracted = sandbox.appendingPathComponent("download")
        let installed = sandbox.appendingPathComponent("installed")
        for folder in [extracted, installed] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tasks"), withIntermediateDirectories: true)
            try Data(folder == installed ? "ancienne".utf8 : "nouvelle".utf8).write(to: folder.appendingPathComponent("LICENSE"))
            try Data(folder == installed ? "ancien".utf8 : "nouveau".utf8).write(to: folder.appendingPathComponent("Tasks/temoin"))
        }
        var calls = 0
        #expect(throws: (any Error).self) {
            try AlfredAutomationTasks.install(extracted: extracted, root: installed) { first, second in
                calls += 1
                if calls == 2 { throw CocoaError(.fileWriteUnknown) }
                try StagedFileReplacement.atomicSwap(first, second)
            }
        }
        #expect(try Data(contentsOf: installed.appendingPathComponent("Tasks/temoin")) == Data("ancien".utf8))
        #expect(try Data(contentsOf: installed.appendingPathComponent("LICENSE")) == Data("ancienne".utf8))
    }

    @Test func automationUpdateKeepsUnrelatedConcurrentChanges() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-unrelated-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let extracted = sandbox.appendingPathComponent("download")
        let installed = sandbox.appendingPathComponent("installed")
        for folder in [extracted, installed] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tasks"), withIntermediateDirectories: true)
            try Data("licence".utf8).write(to: folder.appendingPathComponent("LICENSE"))
        }
        let unrelated = installed.appendingPathComponent("personnel")
        try Data("avant".utf8).write(to: unrelated)
        var calls = 0
        try AlfredAutomationTasks.install(extracted: extracted, root: installed) { first, second in
            calls += 1
            if calls == 1 { try Data("modifié pendant la mise à jour".utf8).write(to: unrelated) }
            try StagedFileReplacement.atomicSwap(first, second)
        }
        #expect(try Data(contentsOf: unrelated) == Data("modifié pendant la mise à jour".utf8))
    }

    @Test func automationUpdateFollowsInstalledDirectorySymlinkWithoutDeletingItsTarget() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let extracted = sandbox.appendingPathComponent("download")
        let actual = sandbox.appendingPathComponent("actual")
        let link = sandbox.appendingPathComponent("link")
        for folder in [extracted, actual] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tasks"), withIntermediateDirectories: true)
        }
        try Data("ancien".utf8).write(to: actual.appendingPathComponent("Tasks/ancien"))
        try Data("licence".utf8).write(to: extracted.appendingPathComponent("LICENSE"))
        try Data("nouveau".utf8).write(to: extracted.appendingPathComponent("Tasks/nouveau"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)

        try AlfredAutomationTasks.install(extracted: extracted, root: link)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == actual.path)
        #expect(try Data(contentsOf: actual.appendingPathComponent("Tasks/nouveau")) == Data("nouveau".utf8))
    }
}
