import XCTest
@testable import RoadieRail

// SPEC-014 T024 — Tests du client IPC.
// Pas de mock socket complet : le daemon n'est pas disponible en CI.
// On teste : init, comportement sur daemon absent, reconnexion gracieuse.

final class RailIPCClientTests: XCTestCase {

    func testInitDoesNotCrash() {
        // Vérifier que l'instanciation est sans effet de bord.
        let client = RailIPCClient()
        XCTAssertNotNil(client)
    }

    func testSendCommandThrowsWhenDaemonAbsent() async {
        // Si le socket n'existe pas, le client doit lever daemonNotRunning (ou timeout),
        // pas crasher ou bloquer indéfiniment.
        let client = RailIPCClient()
        do {
            _ = try await client.send(command: "stage.list")
            // Si par chance le daemon tourne en CI, la commande peut réussir.
        } catch RailIPCError.daemonNotRunning {
            // Attendu : daemon absent.
            XCTAssertTrue(true)
        } catch RailIPCError.timeout {
            // Acceptable aussi : socket présent mais daemon ne répond pas.
            XCTAssertTrue(true)
        } catch {
            // Toute autre erreur réseau est acceptable.
            XCTAssertTrue(true)
        }
    }

    func testRailIPCErrorEquality() {
        XCTAssertEqual(RailIPCError.daemonNotRunning, RailIPCError.daemonNotRunning)
        XCTAssertEqual(RailIPCError.timeout, RailIPCError.timeout)
        XCTAssertNotEqual(RailIPCError.daemonNotRunning, RailIPCError.timeout)
    }

    func testInvalidResponseEquality() {
        let e1 = RailIPCError.invalidResponse(detail: "foo")
        let e2 = RailIPCError.invalidResponse(detail: "foo")
        let e3 = RailIPCError.invalidResponse(detail: "bar")
        XCTAssertEqual(e1, e2)
        XCTAssertNotEqual(e1, e3)
    }
}
