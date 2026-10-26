import Foundation
import Testing
@testable import RoadieDaemon

struct Spec088ScriptRunnerTests {
    private func workflow() throws -> AlfredWorkflow {
        var fixture = WorkflowFixture()
        fixture.name = "Lanceur"
        return try fixture.write(files: ["outil.sh": "#!/bin/bash\necho \"externe:$1\"\n"])
    }

    @Test func escapingFollowsAlfredBits() {
        let text = #"a b"c$d\e`f;g(h)"#
        #expect(AlfredScriptRunner.escape(text, bits: 0) == text)
        #expect(AlfredScriptRunner.escape(text, bits: 102) == #"a b\"c\$d\\e\`f;g(h)"#)
        #expect(AlfredScriptRunner.escape(text, bits: 68) == #"a b\"c$d\\e`f;g(h)"#)
        #expect(AlfredScriptRunner.escape(text, bits: 127) == #"a\ b\"c\$d\\e\`f\;g\(h\)"#)
    }

    @Test func interpretersByAlfredType() throws {
        let folder = URL(fileURLWithPath: "/tmp")
        #expect(try AlfredScriptRunner.argv(for: AlfredScript(language: 0, source: "s"), arguments: ["a"], folder: folder).get() == ["/bin/bash", "-c", "s", "bash", "a"])
        #expect(try AlfredScriptRunner.argv(for: AlfredScript(language: 11, source: "s"), arguments: [], folder: folder).get() == ["/bin/zsh", "--no-rcs", "-c", "s", "zsh"])
        #expect(try AlfredScriptRunner.argv(for: AlfredScript(language: 7, source: "s"), arguments: ["a"], folder: folder).get() == ["/usr/bin/osascript", "-l", "JavaScript", "-e", "s", "a"])
        #expect((try? AlfredScriptRunner.argv(for: AlfredScript(language: 10, source: "s"), arguments: [], folder: folder).get()) == nil)
        #expect((try? AlfredScriptRunner.argv(for: AlfredScript(language: 8, source: "", file: "absent.sh"), arguments: [], folder: folder).get()) == nil)
    }

    @Test func runsWithArgvEnvironmentAndFolder() async throws {
        let workflow = try workflow()
        let result = await AlfredScriptRunner.run(AlfredScript(language: 0, source: #"echo "$1|$alfred_workflow_name|$couleur|$(basename "$PWD")""#),
                                                  query: "x", arguments: ["bonjour"], workflow: workflow, variables: ["couleur": "bleu"])
        #expect(result.succeeded)
        #expect(result.text == "bonjour|Lanceur|bleu|\(workflow.folder.lastPathComponent)\n")
        let external = await AlfredScriptRunner.run(AlfredScript(language: 8, source: "", file: "outil.sh"), query: "", arguments: ["z"],
                                                    workflow: workflow, variables: [:])
        #expect(external.text == "externe:z\n")
    }

    @Test func queryModeEscapesTheText() async throws {
        let workflow = try workflow()
        let script = AlfredScript(language: 0, source: #"echo "{query}""#, usesArgv: false, escaping: 102)
        let result = await AlfredScriptRunner.run(script, query: #"a "b" $HOME"#, arguments: ["ignoré"], workflow: workflow, variables: [:])
        #expect(result.text == "a \"b\" $HOME\n")
    }

    @Test func cancelStopsTheWholeProcessGroup() async throws {
        let workflow = try workflow()
        let marker = "31.\(Int.random(in: 100...999))"
        let started = Date()
        let process = AlfredScriptRunner.start(AlfredScript(language: 0, source: "(sleep \(marker) &); sleep \(marker)"), query: "", arguments: [],
                                               workflow: workflow, variables: [:]) { _ in }
        try await Task.sleep(for: .milliseconds(300))
        process.cancel()
        try await Task.sleep(for: .milliseconds(500))
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-f", "sleep \(marker)"]
        check.standardOutput = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        #expect(check.terminationStatus == 1, "aucun processus « sleep \(marker) » ne doit rester")
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func timeoutAndOutputCap() async throws {
        let workflow = try workflow()
        let slow = await AlfredScriptRunner.run(AlfredScript(language: 0, source: "sleep 5"), query: "", arguments: [], workflow: workflow,
                                                variables: [:], timeout: 0.3)
        #expect(slow.timedOut && !slow.succeeded)
        let big = await AlfredScriptRunner.run(AlfredScript(language: 0, source: "head -c 6000000 /dev/zero"), query: "", arguments: [],
                                               workflow: workflow, variables: [:])
        #expect(big.truncated && big.output.count <= AlfredScriptRunner.maxOutput)
    }
}
