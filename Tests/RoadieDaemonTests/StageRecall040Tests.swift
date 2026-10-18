import Foundation
import Testing
import RoadieCore
import RoadieAX
@testable import RoadieDaemon

struct StageRecall040Tests {
    @Test(arguments: [true, false], [true, false])
    func missingPreferredMemberDoesNotBlockAnotherWindow(sameStage: Bool, fallbackSucceeds: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recall-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let display = DisplayID(rawValue: "display-main")
        let preferred = powerWindow(2, x: 100)
        let available = powerWindow(3, x: 200)
        let provider = PowerUserProvider(windows: [])
        let writer = PowerUserWriter(provider: provider)
        writer.applicationWindowFocusResults[available.id] = fallbackSucceeds
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: sameStage ? "2" : "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: preferred.id, members: [preferred, available].map {
                    PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame,
                        presentationState: sameStage && $0.id == available.id ? .maximized : nil,
                        lastSeenAt: .now, missingSince: .now)
                }),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let result = StageCommandService(service: service, store: store,
            events: EventLog(path: directory.appendingPathComponent("events.jsonl").path))
            .switchTo("2", displayID: display)
        #expect(result.changed)
        #expect(writer.focusedApplicationWindows == [preferred.id, available.id])
        #expect(writer.activatedBundleIDs == (fallbackSucceeds ? [] : [preferred.bundleID]))
        #expect(provider.focusedID == (fallbackSucceeds ? available.id : nil))
    }
}

extension StageRecall040Tests {
    @Test func candidatesExcludeConfirmedClosuresAndPreservePreferredThenFreshness() {
        let windows = (1...5).map { powerWindow(UInt32($0), x: 100) }
        var members = windows.map {
            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame,
                                  lastSeenAt: Date(timeIntervalSince1970: Double($0.id.rawValue)))
        }
        members[0].confirmedClosedAt = .now
        members[3].bundleID = ""
        members[4].presentationState = .maximized
        var stage = PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: windows[0].id, members: members)
        #expect(StageCommandService.missingFocusCandidates(in: stage).map(\.windowID) == [windows[2].id, windows[1].id])
        stage.focusedWindowID = windows[1].id
        #expect(StageCommandService.missingFocusCandidates(in: stage).map(\.windowID) == [windows[1].id, windows[2].id])
    }
}
