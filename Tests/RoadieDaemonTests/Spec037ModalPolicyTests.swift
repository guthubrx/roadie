import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite struct Spec037ModalPolicyTests {
    @Test func attachedSheetIsExcludedEvenWithoutModalFlagAndMainWindowTitleIsIrrelevant() {
        var window = powerWindow(1, x:100, width:1512, height:944, app:"Firefox")
        window.title = "File Upload"
        window.role = "AXSheet"
        #expect(!SnapshotService.applyTilingPolicy(to:window,config:RoadieConfig()).isTileCandidate)
        window.role = "AXWindow";window.subrole = "AXStandardWindow"
        #expect(SnapshotService.applyTilingPolicy(to:window,config:RoadieConfig()).isTileCandidate)
    }
}
