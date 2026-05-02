import XCTest
@testable import RoadieCore

@MainActor
final class EventBusRailEventsTests: XCTestCase {

    // MARK: - wallpaperClick

    func testWallpaperClickFields() {
        let event = DesktopEvent.wallpaperClick(x: 800, y: 600, displayID: 1234)
        XCTAssertEqual(event.name, "wallpaper_click")
        XCTAssertEqual(event.payload["x"], "800")
        XCTAssertEqual(event.payload["y"], "600")
        XCTAssertEqual(event.payload["display_id"], "1234")
    }

    func testWallpaperClickJSONLine() {
        let event = DesktopEvent.wallpaperClick(x: 100, y: 200, displayID: 42)
        let json = event.toJSONLine()
        XCTAssertTrue(json.contains("\"event\":\"wallpaper_click\""), "manque event")
        XCTAssertTrue(json.contains("\"ts\":"), "manque ts")
        XCTAssertTrue(json.contains("\"version\":1"), "manque version")
        XCTAssertTrue(json.contains("\"x\":\"100\""), "manque x")
        XCTAssertTrue(json.contains("\"y\":\"200\""), "manque y")
        XCTAssertTrue(json.contains("\"display_id\":\"42\""), "manque display_id")
        XCTAssertTrue(json.hasSuffix("\n"), "doit se terminer par newline")
    }

    // MARK: - stageRenamed

    func testStageRenamedFields() {
        let event = DesktopEvent.stageRenamed(stageID: "2", oldName: "Work", newName: "Coding")
        XCTAssertEqual(event.name, "stage_renamed")
        XCTAssertEqual(event.payload["stage_id"], "2")
        XCTAssertEqual(event.payload["old_name"], "Work")
        XCTAssertEqual(event.payload["new_name"], "Coding")
    }

    func testStageRenamedJSONLine() {
        let event = DesktopEvent.stageRenamed(stageID: "1", oldName: "A", newName: "B")
        let json = event.toJSONLine()
        XCTAssertTrue(json.contains("\"event\":\"stage_renamed\""))
        XCTAssertTrue(json.contains("\"stage_id\":\"1\""))
        XCTAssertTrue(json.contains("\"old_name\":\"A\""))
        XCTAssertTrue(json.contains("\"new_name\":\"B\""))
    }

    // MARK: - thumbnailUpdated

    func testThumbnailUpdatedFields() {
        let event = DesktopEvent.thumbnailUpdated(wid: 9999)
        XCTAssertEqual(event.name, "thumbnail_updated")
        XCTAssertEqual(event.payload["wid"], "9999")
    }

    func testThumbnailUpdatedJSONLine() {
        let event = DesktopEvent.thumbnailUpdated(wid: 12345)
        let json = event.toJSONLine()
        XCTAssertTrue(json.contains("\"event\":\"thumbnail_updated\""))
        XCTAssertTrue(json.contains("\"wid\":\"12345\""))
    }

    // MARK: - publish → subscriber

    func testPublishReachesSubscriber() async {
        let bus = EventBus()
        let stream = bus.subscribe()
        let event = DesktopEvent.thumbnailUpdated(wid: 42)
        bus.publish(event)

        var received: DesktopEvent?
        for await e in stream {
            received = e
            break
        }
        XCTAssertEqual(received?.name, "thumbnail_updated")
        XCTAssertEqual(received?.payload["wid"], "42")
    }

    func testWallpaperClickPublishReachesSubscriber() async {
        let bus = EventBus()
        let stream = bus.subscribe()
        let event = DesktopEvent.wallpaperClick(x: 50, y: 75, displayID: 1)
        bus.publish(event)

        for await e in stream {
            XCTAssertEqual(e.name, "wallpaper_click")
            XCTAssertEqual(e.payload["x"], "50")
            break
        }
    }
}
