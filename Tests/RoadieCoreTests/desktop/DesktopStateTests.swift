import XCTest
@testable import RoadieCore

final class DesktopStateTests: XCTestCase {

    private func tmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadies-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Round-trip TOML

    func test_writeAndReadRoundTrip() throws {
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let stage = PersistedStage(
            id: "1", displayName: "Work",
            memberWindows: [
                PersistedMember(cgWindowID: 42, bundleID: "com.iterm2",
                                titleHint: "main",
                                savedFrame: PersistedRect(x: 10, y: 20, w: 800, h: 600))
            ]
        )
        let original = DesktopState(
            desktopUUID: "uuid-123",
            displayName: "code",
            tilerStrategy: .bsp,
            currentStageID: StageID("1"),
            gapsOverride: GapsOverride(top: 4, bottom: 30, left: 12, right: 12),
            stages: [stage]
        )
        let path = tmp.appendingPathComponent("state.toml")
        try original.write(to: path)
        let loaded = try DesktopState.read(from: path)
        XCTAssertEqual(loaded.desktopUUID, "uuid-123")
        XCTAssertEqual(loaded.displayName, "code")
        XCTAssertEqual(loaded.currentStageID?.value, "1")
        XCTAssertEqual(loaded.gapsOverride, GapsOverride(top: 4, bottom: 30, left: 12, right: 12))
        XCTAssertEqual(loaded.stages.count, 1)
        XCTAssertEqual(loaded.stages[0].memberWindows[0].cgWindowID, 42)
    }

    // MARK: - Atomic write

    func test_atomicWrite_doesNotLeaveTmpFile() throws {
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let path = tmp.appendingPathComponent("state.toml")
        let st = DesktopState(desktopUUID: "u", stages: [PersistedStage(id: "1", displayName: "a")])
        try st.write(to: path)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        XCTAssertTrue(entries.contains("state.toml"))
        XCTAssertFalse(entries.contains(where: { $0.hasSuffix(".tmp") }),
                       "le .tmp doit être renommé, pas laissé sur disque")
    }

    // MARK: - Validation

    func test_validate_rejectsEmptyUUID() {
        let st = DesktopState(desktopUUID: "")
        XCTAssertThrowsError(try st.validate()) { err in
            guard case DesktopStateError.invalidUUID(let s) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(s, "")
        }
    }

    func test_validate_rejectsUnknownCurrentStage() {
        let st = DesktopState(
            desktopUUID: "uuid",
            currentStageID: StageID("999"),
            stages: [PersistedStage(id: "1", displayName: "a")]
        )
        XCTAssertThrowsError(try st.validate()) { err in
            guard case DesktopStateError.unknownCurrentStage(let s) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(s, "999")
        }
    }

    func test_validate_acceptsEmptyStagesWithCurrentNil() throws {
        let st = DesktopState(desktopUUID: "uuid", currentStageID: nil, stages: [])
        try st.validate() // ne doit pas throw
    }

    // MARK: - Empty factory + path

    func test_empty_factoryProducesValidState() throws {
        let st = DesktopState.empty(uuid: "u-1", defaultStage: StageID("main"))
        try st.validate()
        XCTAssertEqual(st.desktopUUID, "u-1")
        XCTAssertEqual(st.stages.count, 1)
        XCTAssertEqual(st.currentStageID?.value, "main")
    }

    func test_path_endsWithUUIDToml() {
        let url = DesktopState.path(for: "deadbeef")
        XCTAssertTrue(url.path.hasSuffix("/desktops/deadbeef.toml"))
    }

    // MARK: - GapsOverride résolution

    func test_gapsOverride_resolvePartial() {
        let global = OuterGaps(top: 8, bottom: 8, left: 8, right: 8)
        let override = GapsOverride(top: 30, bottom: nil, left: nil, right: nil)
        let resolved = override.resolve(over: global)
        XCTAssertEqual(resolved, OuterGaps(top: 30, bottom: 8, left: 8, right: 8))
    }

    func test_gapsOverride_resolveFull() {
        let global = OuterGaps(top: 8, bottom: 8, left: 8, right: 8)
        let override = GapsOverride(top: 1, bottom: 2, left: 3, right: 4)
        let resolved = override.resolve(over: global)
        XCTAssertEqual(resolved, OuterGaps(top: 1, bottom: 2, left: 3, right: 4))
    }
}
