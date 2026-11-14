import AppKit
import Foundation
import os
import Testing
@testable import RoadieDaemon

@Suite(.serialized) @MainActor struct Spec156LauncherTests {
    private func wait(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(3))
        }
        return predicate()
    }

    @Test func recentFileSearchDoesNotRunOnTheRenderingThread() async {
        let main = OSAllocatedUnfairLock(initialState: false)
        let file = LauncherFile(path: "/fixture/report.txt", name: "report.txt", isFolder: false, lastUsed: Date())
        let search = LauncherFileSearch(recent: { _ in
            main.withLock { $0 = Thread.isMainThread }
            Thread.sleep(forTimeInterval: 0.025)
            return [file]
        })
        var received: [LauncherFile]?
        search.search("report", retaining: [file]) { received = $0 }
        #expect(received == nil)
        #expect(await wait { received != nil })
        search.cancel()
        #expect(received == [file])
        #expect(!main.withLock { $0 })
    }

    @Test func cancelledRecentResultsDoNotReplaceTheNextQuery() async {
        let started = OSAllocatedUnfairLock(initialState: false)
        let file = LauncherFile(path: "/fixture/old.txt", name: "old.txt", isFolder: false, lastUsed: nil)
        let search = LauncherFileSearch(recent: { _ in
            started.withLock { $0 = true }
            Thread.sleep(forTimeInterval: 0.03)
            return [file]
        })
        var oldDelivered = false
        search.search("old") { _ in oldDelivered = true }
        #expect(await wait { started.withLock { $0 } })
        search.cancel()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!oldDelivered)
    }

    @Test func railCannotTakeTheKeyboardWhenItAppears() {
        let panel = RailPanel()
        defer { panel.orderOut(nil) }
        #expect(!panel.canBecomeKey)
        panel.makeKey()
        #expect(!panel.isKeyWindow)
    }
}
