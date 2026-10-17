import ApplicationServices
import Testing
@testable import RoadieAX

@Suite struct Spec037AttachedWindowsTests {
    @Test func knownVisibleWindowsDoNotReadAttachedControls() {
        let root = AXUIElementCreateApplication(1001)
        var childReads = 0
        let entries = AXApplicationWindows.attachedWindowEntries(roots: [(1, root)], children: { _ in
            childReads += 1; return []
        }, identifier: { _ in nil }, isSheet: { _ in false }, requiredWindowIDs: [1])
        #expect(entries.isEmpty)
        #expect(childReads == 0)
    }

    @Test func missingVisibleXPCWindowStillResolvesThroughItsSheet() {
        let root = AXUIElementCreateApplication(1001)
        let sheet = AXUIElementCreateApplication(1002)
        let content = AXUIElementCreateApplication(1003)
        let entries = AXApplicationWindows.attachedWindowEntries(roots: [(1, root)], children: {
            CFEqual($0, root) ? [sheet] : (CFEqual($0, sheet) ? [content] : [])
        }, identifier: { CFEqual($0, sheet) ? 2 : 3 }, isSheet: { CFEqual($0, sheet) }, requiredWindowIDs: [1, 3])
        #expect(entries.compactMap(\.id) == [2, 3])
        #expect(entries.last.map { CFEqual($0.element, sheet) } == true)
    }

    @Test func xpcContentKeepsItsSheetIdentityWithoutAdoptingNormalControls() {
        let root = AXUIElementCreateApplication(1001)
        let control = AXUIElementCreateApplication(1002)
        let sheet = AXUIElementCreateApplication(1003)
        let content = AXUIElementCreateApplication(1004)
        let entries = AXApplicationWindows.attachedWindowEntries(roots: [(1,root)], children: { element in
            if CFEqual(element,root) { return [control,sheet] }
            if CFEqual(element,sheet) { return [content] }
            return []
        }, identifier: { element in
            if CFEqual(element,root) || CFEqual(element,control) { return 1 }
            return CFEqual(element,sheet) ? 2 : 3
        }, isSheet: { CFEqual($0,sheet) })
        let index = AXApplicationWindows(pid: 1001, entries: [(1,root)] + entries)
        #expect(entries.compactMap(\.id) == [2,3])
        #expect(index.element(id:1).map { CFEqual($0,root) } == true)
        #expect(index.element(id:3).map { CFEqual($0,sheet) } == true)
    }

    @Test func malformedAttachedHierarchyIsBoundedAndDoesNotReplaceTheMainWindow() {
        let root = AXUIElementCreateApplication(1001)
        let sheet = AXUIElementCreateApplication(1002)
        var reads = 0
        let entries = AXApplicationWindows.attachedWindowEntries(roots: [(1,root)], children: { _ in
            reads += 1;return [sheet,sheet,sheet]
        }, identifier: { _ in nil }, isSheet: { _ in true })
        #expect(entries.isEmpty)
        #expect(reads <= 257)
    }
}
