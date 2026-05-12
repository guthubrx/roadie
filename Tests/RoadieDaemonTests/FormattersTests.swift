import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct FormattersTests {
    private func sampleDisplay(id: String = "main", isMain: Bool = true, index: Int = 0) -> DisplaySnapshot {
        let frame = Rect(x: 0, y: 0, width: 1920, height: 1080)
        return DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: index,
            name: id,
            frame: frame,
            visibleFrame: frame,
            isMain: isMain
        )
    }

    private func sampleWindow(
        id: UInt32 = 42,
        title: String = "Hello",
        appName: String = "TestApp"
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 1000,
            appName: appName,
            bundleID: "com.test.app",
            title: title,
            frame: Rect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    @Test
    func windowsReturnsHumanMessageWhenNoTileableWindows() {
        #expect(TextFormatter.windows([]) == "No tileable windows found.")
    }

    @Test
    func windowsExcludesEntriesWithoutScope() {
        let entry = ScopedWindowSnapshot(window: sampleWindow(), scope: nil)
        #expect(TextFormatter.windows([entry]) == "No tileable windows found.")
    }

    @Test
    func windowsContainsHeaderAndPayload() {
        let scope = StageScope(
            displayID: DisplayID(rawValue: "main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let entry = ScopedWindowSnapshot(window: sampleWindow(), scope: scope)
        let output = TextFormatter.windows([entry])
        #expect(output.contains("WID\tPID\tAPP\tTITLE\tSCOPE\tPIN\tFRAME"))
        #expect(output.contains("42"))
        #expect(output.contains("TestApp"))
        #expect(output.contains("Hello"))
    }

    @Test
    func displaysReturnsMessageWhenEmpty() {
        #expect(TextFormatter.displays([]) == "No displays found.")
    }

    @Test
    func displaysMarksActiveDisplay() {
        let main = sampleDisplay(id: "main", isMain: true)
        let secondary = sampleDisplay(id: "ext", isMain: false, index: 1)
        let state = PersistentStageState(activeDisplayID: main.id)
        let output = TextFormatter.displays([main, secondary], state: state)
        let lines = output.components(separatedBy: "\n")
        // First line is header, second is main (active), third is secondary
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("*"), "main display should be marked active")
        #expect(!lines[2].hasPrefix("*"), "secondary should not be marked active")
    }

    @Test
    func permissionsFormatsBooleanFlag() {
        let trusted = PermissionSnapshot(accessibilityTrusted: true)
        #expect(TextFormatter.permissions(trusted) == "accessibilityTrusted=true")
        let untrusted = PermissionSnapshot(accessibilityTrusted: false)
        #expect(TextFormatter.permissions(untrusted) == "accessibilityTrusted=false")
    }

    @Test
    func displayParkingFormatsDiagnosticFields() {
        let report = DisplayParkingReport(
            kind: .ambiguous,
            reason: .ambiguousMatch,
            originDisplayID: DisplayID(rawValue: "old"),
            originLogicalDisplayID: LogicalDisplayID(rawValue: "display:old"),
            candidateDisplayIDs: [DisplayID(rawValue: "a"), DisplayID(rawValue: "b")],
            confidence: 0.9
        )

        let output = TextFormatter.displayParking(report)

        #expect(output.contains("kind=ambiguous"))
        #expect(output.contains("reason=ambiguous_match"))
        #expect(output.contains("originDisplay=old"))
        #expect(output.contains("candidateDisplays=a,b"))
        #expect(output.contains("confidence=0.900"))
    }
}
