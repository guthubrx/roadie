import XCTest
import CoreGraphics
@testable import RoadieDesktops

/// Tests US4 — Labels de desktop (T046).
/// Couvre : validation, labels réservés, setLabel, focus par label, retrait.
final class LabelTests: XCTestCase {

    private var tmpDir: URL!
    private var registry: DesktopRegistry!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-label-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        registry = DesktopRegistry(configDir: tmpDir, count: 5)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Validation (T041)

    func testValidLabelAccepted() {
        XCTAssertTrue(isValidDesktopLabel("code"))
        XCTAssertTrue(isValidDesktopLabel("comm-2"))
        XCTAssertTrue(isValidDesktopLabel("web_front"))
        XCTAssertTrue(isValidDesktopLabel(String(repeating: "a", count: 32)))
        XCTAssertTrue(isValidDesktopLabel(""))  // vide = retrait = valide
    }

    func testLabelTooLongRejected() {
        let tooLong = String(repeating: "a", count: 33)
        XCTAssertFalse(isValidDesktopLabel(tooLong))
    }

    func testLabelInvalidCharsRejected() {
        XCTAssertFalse(isValidDesktopLabel("code!"))
        XCTAssertFalse(isValidDesktopLabel("my label"))   // espace interdit
        XCTAssertFalse(isValidDesktopLabel("a/b"))
        XCTAssertFalse(isValidDesktopLabel("a.b"))
        XCTAssertFalse(isValidDesktopLabel("ñoño"))       // non-ASCII
    }

    // MARK: - Labels réservés (T041)

    func testReservedLabelsRejected() {
        let reserved = ["prev", "next", "recent", "first", "last", "current"]
        for label in reserved {
            XCTAssertTrue(isReservedDesktopLabel(label), "'\(label)' devrait être réservé")
        }
    }

    func testNonReservedLabelNotReserved() {
        XCTAssertFalse(isReservedDesktopLabel("code"))
        XCTAssertFalse(isReservedDesktopLabel("web"))
        XCTAssertFalse(isReservedDesktopLabel(""))
    }

    // MARK: - setLabel via Registry (T042)

    func testSetLabelPersists() async throws {
        await registry.load()
        try await registry.setLabel("code", for: 1)

        // Relire depuis disque
        let registry2 = DesktopRegistry(configDir: tmpDir, count: 5)
        await registry2.load()
        let desktop = await registry2.desktop(id: 1)
        XCTAssertEqual(desktop?.label, "code")
    }

    func testSetLabelNilRemovesLabel() async throws {
        await registry.load()
        try await registry.setLabel("code", for: 1)
        try await registry.setLabel(nil, for: 1)

        let registry2 = DesktopRegistry(configDir: tmpDir, count: 5)
        await registry2.load()
        let desktop = await registry2.desktop(id: 1)
        XCTAssertNil(desktop?.label)
    }

    func testSetLabelEmptyStringRemovesLabel() async throws {
        await registry.load()
        try await registry.setLabel("code", for: 1)
        try await registry.setLabel("", for: 1)

        let desktop = await registry.desktop(id: 1)
        XCTAssertNil(desktop?.label, "Label vide doit être converti en nil")
    }

    func testSetInvalidLabelThrows() async throws {
        await registry.load()
        do {
            try await registry.setLabel("invalid label!", for: 1)
            XCTFail("setLabel devrait lever une erreur pour un label invalide")
        } catch { /* attendu */ }
    }

    func testSetReservedLabelThrows() async throws {
        await registry.load()
        for reserved in ["prev", "next", "current"] {
            do {
                try await registry.setLabel(reserved, for: 1)
                XCTFail("setLabel devrait lever une erreur pour le label réservé '\(reserved)'")
            } catch { /* attendu */ }
        }
    }

    // MARK: - Focus par label via Selector (T044)

    func testFocusByLabelResolvesID() async throws {
        await registry.load()
        // Poser un label sur desktop 3
        try await registry.setLabel("web", for: 3)

        let resolved = await resolveSelector("web", registry: registry, count: 5)
        XCTAssertEqual(resolved, 3)
    }

    func testFocusByUnknownLabelReturnsNil() async {
        await registry.load()
        let resolved = await resolveSelector("nonexistent", registry: registry, count: 5)
        XCTAssertNil(resolved)
    }

    func testFocusByLabelIsCaseSensitive() async throws {
        await registry.load()
        try await registry.setLabel("Web", for: 2)

        // "web" (lowercase) ne doit PAS matcher "Web"
        let lower = await resolveSelector("web", registry: registry, count: 5)
        XCTAssertNil(lower)

        // "Web" doit matcher
        let exact = await resolveSelector("Web", registry: registry, count: 5)
        XCTAssertEqual(exact, 2)
    }
}
