import ApplicationServices
import Foundation
import Testing
@testable import RoadieAX

/// SPEC-051 A-02 : un relevé réutilise l'index AX d'une application s'il couvre ses fenêtres visibles.
@Suite struct Spec051WindowIndexReuseTests {
    private let index = AXApplicationWindows(pid: 60, entries: [
        (id: 1, element: AXUIElementCreateApplication(601)),
        (id: 2, element: AXUIElementCreateApplication(602)),
    ])

    @Test func coveringIndexIsReused() {
        #expect(LiveSystemSnapshotProvider.reusableIndex(index, required: [1, 2])?.pid == 60)
        #expect(LiveSystemSnapshotProvider.reusableIndex(index, required: [2])?.pid == 60)
    }

    @Test func newWindowForcesAnotherEnumeration() {
        #expect(LiveSystemSnapshotProvider.reusableIndex(index, required: [1, 2, 3]) == nil)
    }

    @Test func missingIndexOrUnknownNeedEnumerates() {
        #expect(LiveSystemSnapshotProvider.reusableIndex(nil, required: [1]) == nil)
        #expect(LiveSystemSnapshotProvider.reusableIndex(index, required: nil) == nil)
        #expect(LiveSystemSnapshotProvider.reusableIndex(index, required: []) == nil)
    }
}
