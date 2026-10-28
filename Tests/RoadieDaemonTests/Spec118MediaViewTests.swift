import Foundation
import Testing
@testable import RoadieDaemon

/// Vues Image et PDF des workflows (session 118).
struct Spec118MediaViewTests {
    @Test func imageAndPDFBricksShowTheReceivedFile() async throws {
        var fixture = WorkflowFixture()
        fixture.add("img", "userinterface.image", ["imageresizemode": 2, "stackview": true])
        fixture.add("pdf", "userinterface.pdf", ["displaymode": 3])
        let workflow = try fixture.write(files: ["shot.png": "png", "doc.pdf": "pdf"])
        let effects = RecordedEffects()
        let engine = AlfredWorkflowEngine(effects: effects)
        _ = await engine.start(workflow, at: "img", arg: ["shot.png\nautre.png"], variables: ["v": "1"])
        let image = try #require(effects.lastMedia)
        #expect(image.kind == .image && image.imageSize == .ignoreDPI && image.variables["v"] == "1")
        #expect(image.path == workflow.folder.appendingPathComponent("shot.png").path)
        _ = await engine.start(workflow, at: "pdf", arg: [workflow.folder.appendingPathComponent("doc.pdf").path])
        #expect(effects.lastMedia?.kind == .pdf && effects.lastMedia?.pdfMode == .twoPages)
    }

    @Test func missingFileStopsWithANotice() async throws {
        var fixture = WorkflowFixture()
        fixture.add("pdf", "userinterface.pdf")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let outcome = await AlfredWorkflowEngine(effects: effects).start(workflow, at: "pdf", arg: ["/nulle/part.pdf"])
        #expect(outcome.errors == ["media:file"] && effects.lastMedia == nil)
        #expect(effects.calls.contains { $0.hasPrefix("notify:") })
        #expect(AlfredWorkflowEngine.supportedTypes.isSuperset(of: ["userinterface.image", "userinterface.pdf"]))
    }
}
